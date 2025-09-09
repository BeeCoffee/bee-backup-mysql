#!/bin/bash

# ========================================
# SCRIPT DE DIAGNÓSTICO PARA BACKUP 200GB
# ========================================

echo "🔍 DIAGNÓSTICO DO BACKUP DE 200GB"
echo "=================================="

# Carregar configurações
if [[ -f "/app/.env" ]]; then
    set -a
    source /app/.env
    set +a
else
    echo "❌ Arquivo .env não encontrado!"
    exit 1
fi

# Função de log
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# Testar sintaxe SQL com chunk pequeno
test_chunk_syntax() {
    local database="${SOURCE_DATABASE:-asasaude}"
    local table="log_instituicao"
    
    log "INFO" "🧪 Testando sintaxe SQL para chunks..."
    
    # Testar a sintaxe problemática
    log "INFO" "   ❌ Testando sintaxe ANTIGA (deve falhar):"
    local old_cmd="mysql ${MYSQL_CLIENT_OPTIONS:-} -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' -e \"
        SELECT COUNT(*) FROM $database.$table WHERE 1=1 ORDER BY (SELECT NULL) LIMIT 1 OFFSET 0;
    \""
    
    if eval "$old_cmd" 2>/tmp/test_old_syntax.log; then
        log "WARNING" "      ⚠️  Sintaxe antiga funcionou (inesperado)"
    else
        local error_msg=$(cat /tmp/test_old_syntax.log 2>/dev/null)
        log "ERROR" "      ❌ Sintaxe antiga falhou: $error_msg"
    fi
    
    # Testar a sintaxe corrigida
    log "INFO" "   ✅ Testando sintaxe NOVA (deve funcionar):"
    local new_cmd="mysql ${MYSQL_CLIENT_OPTIONS:-} -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' -e \"
        SELECT COUNT(*) FROM $database.$table WHERE 1=1 LIMIT 1 OFFSET 0;
    \""
    
    if eval "$new_cmd" 2>/tmp/test_new_syntax.log; then
        log "SUCCESS" "      ✅ Sintaxe nova funcionou!"
    else
        local error_msg=$(cat /tmp/test_new_syntax.log 2>/dev/null)
        log "ERROR" "      ❌ Sintaxe nova falhou: $error_msg"
    fi
    
    rm -f /tmp/test_old_syntax.log /tmp/test_new_syntax.log
}

# Testar backup de chunk único
test_single_chunk() {
    local database="${SOURCE_DATABASE:-asasaude}"
    local table="log_instituicao"
    local test_file="/tmp/test_chunk.sql"
    
    log "INFO" "🧪 Testando backup de 1 chunk (1000 registros)..."
    
    local chunk_cmd="mysqldump ${MYSQL_CLIENT_OPTIONS:-} -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' \\
        --no-create-info --single-transaction --quick \\
        --lock-tables=false --skip-lock-tables --skip-add-locks \\
        --no-tablespaces --extended-insert=false --disable-keys \\
        --where='1=1 LIMIT 1000 OFFSET 0' \\
        '$database' '$table'"
    
    log "INFO" "   🔧 Comando: $chunk_cmd"
    
    if timeout 60 bash -c "$chunk_cmd" > "$test_file" 2>/tmp/test_chunk_error.log; then
        local file_size=$(stat -c%s "$test_file" 2>/dev/null || echo "0")
        if [[ "$file_size" -gt 0 ]]; then
            log "SUCCESS" "   ✅ Chunk de teste criado com sucesso (${file_size} bytes)"
            local lines=$(wc -l < "$test_file" 2>/dev/null || echo "0")
            log "INFO" "      📊 Linhas no arquivo: $lines"
            
            # Mostrar primeiras linhas para verificação
            log "INFO" "      📋 Primeiras 5 linhas:"
            head -5 "$test_file" | while IFS= read -r line; do
                log "INFO" "         $line"
            done
        else
            log "ERROR" "   ❌ Arquivo de teste vazio"
        fi
    else
        local error_msg=$(cat /tmp/test_chunk_error.log 2>/dev/null)
        log "ERROR" "   ❌ Falha no backup de teste: $error_msg"
    fi
    
    rm -f "$test_file" /tmp/test_chunk_error.log
}

# Verificar recursos disponíveis
check_resources() {
    log "INFO" "💾 Verificando recursos do sistema..."
    
    # Espaço em disco
    local disk_space=$(df -h /backups 2>/dev/null | tail -1 | awk '{print $4}' || echo "N/A")
    log "INFO" "   📁 Espaço disponível em /backups: $disk_space"
    
    # Memória
    local memory=$(free -h | grep "^Mem:" | awk '{print $7}' || echo "N/A")
    log "INFO" "   🧠 Memória livre: $memory"
    
    # Conexões ativas
    local connections=$(mysql ${MYSQL_CLIENT_OPTIONS:-} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{print $2}' || echo "N/A")
    log "INFO" "   🔌 Conexões ativas no servidor: $connections"
}

# Verificar configurações do servidor
check_server_config() {
    log "INFO" "⚙️  Verificando configurações do servidor..."
    
    # Timeout de conexão
    local wait_timeout=$(mysql ${MYSQL_CLIENT_OPTIONS:-} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "SHOW VARIABLES LIKE 'wait_timeout';" 2>/dev/null | awk '{print $2}' || echo "N/A")
    log "INFO" "   ⏰ wait_timeout: ${wait_timeout}s"
    
    # Max allowed packet
    local max_packet=$(mysql ${MYSQL_CLIENT_OPTIONS:-} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "SHOW VARIABLES LIKE 'max_allowed_packet';" 2>/dev/null | awk '{print $2}' || echo "N/A")
    log "INFO" "   📦 max_allowed_packet: $max_packet bytes"
    
    # Versão do MariaDB
    local version=$(mysql ${MYSQL_CLIENT_OPTIONS:-} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "SELECT VERSION();" 2>/dev/null || echo "N/A")
    log "INFO" "   🏷️  Versão: $version"
}

# Executar todos os testes
main() {
    log "INFO" "🚀 Iniciando diagnóstico completo..."
    
    check_resources
    check_server_config
    test_chunk_syntax
    test_single_chunk
    
    log "SUCCESS" "🎉 Diagnóstico concluído!"
    log "INFO" "📋 RECOMENDAÇÕES:"
    log "INFO" "   1. Usar CHUNK_SIZE=10000 (ao invés de 50000)"
    log "INFO" "   2. Usar CHUNK_TIMEOUT=300 (5min ao invés de 30min)"
    log "INFO" "   3. Usar CHUNK_INTERVAL_MS=2000 (2s entre chunks)"
    log "INFO" "   4. Considerar VERIFY_BACKUP_INTEGRITY=false"
    log "INFO" "   5. Rodar em horário de menor movimento"
}

# Executar
main
