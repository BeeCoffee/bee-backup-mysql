#!/bin/bash

# =============================================================================
# TESTE DE DETECÇÃO DE TABELAS GRANDES
# =============================================================================
# Este script testa apenas a detecção de tabelas grandes sem fazer backup

set -euo pipefail

# Carregar configurações do .env
if [[ -f .env ]]; then
    source .env
else
    echo "❌ Arquivo .env não encontrado!"
    exit 1
fi

echo "🔍 TESTE DE DETECÇÃO DE TABELAS GRANDES"
echo "======================================"
echo
echo "📊 Conectando no database: $DATABASES"
echo "🏠 Servidor: ${SOURCE_HOST}:${SOURCE_PORT}"
echo "👤 Usuário: $DB_USERNAME"
echo "⚙️  Limite: ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
echo

# Função de log simples
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Função para detectar tabelas grandes (copiada do backup.sh)
detect_large_tables() {
    local database=$1
    local host=$2
    local port=$3
    local size_threshold_mb=${4:-1000}
    
    log "🔍 Detectando tabelas grandes (> ${size_threshold_mb}MB) no database '$database'..."
    
    local large_tables=$(mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
        "SELECT CONCAT(table_name, ':', ROUND((data_length + index_length) / 1024 / 1024, 2))
         FROM information_schema.tables 
         WHERE table_schema = '$database' 
         AND (data_length + index_length) > ($size_threshold_mb * 1024 * 1024)
         ORDER BY (data_length + index_length) DESC;" 2>/dev/null)
    
    if [[ -n "$large_tables" ]]; then
        log "⚡ Tabelas grandes encontradas:"
        echo "$large_tables" | while IFS=':' read -r table_name size_mb; do
            log "   📊 $table_name: ${size_mb}MB"
        done
        echo "$large_tables"
    else
        log "ℹ️  Nenhuma tabela grande encontrada (todas < ${size_threshold_mb}MB)"
    fi
}

# Testar conexão
log "🔌 Testando conexão com o database..."
if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" &>/dev/null; then
    log "✅ Conexão estabelecida com sucesso!"
else
    log "❌ Erro de conexão! Verifique as credenciais no .env"
    exit 1
fi

echo

# Processar cada database
IFS=',' read -ra DB_ARRAY <<< "$DATABASES"
for database in "${DB_ARRAY[@]}"; do
    database=$(echo "$database" | xargs) # Remove espaços
    
    log "📦 Analisando database: '$database'"
    
    # Verificar se database existe
    if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "USE $database;" &>/dev/null; then
        
        # Detectar tabelas grandes
        large_tables=$(detect_large_tables "$database" "$SOURCE_HOST" "$SOURCE_PORT" "${CHUNK_SIZE_THRESHOLD_MB:-1000}")
        
        if [[ -n "$large_tables" ]]; then
            echo
            log "🎯 RESULTADO: Database '$database' tem tabelas grandes!"
            log "📋 Estratégia que será usada: BACKUP HÍBRIDO"
            log "   - Tabelas grandes: Processadas por chunks de ${CHUNK_SIZE:-50000} registros"
            log "   - Demais tabelas: Backup tradicional"
            log "   - Resultado final: Arquivo único consolidado"
            
            echo
            log "🔧 Tabelas que serão processadas por chunks:"
            while IFS=':' read -r table_name size_mb; do
                local total_rows=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
                    "SELECT COUNT(*) FROM $database.$table_name;" 2>/dev/null || echo "0")
                local estimated_chunks=$(( ($total_rows + ${CHUNK_SIZE:-50000} - 1) / ${CHUNK_SIZE:-50000} ))
                log "   📊 $table_name: ${size_mb}MB ($total_rows registros = ~$estimated_chunks chunks)"
            done <<< "$large_tables"
        else
            log "ℹ️  Database '$database' usará backup tradicional (sem chunks)"
        fi
    else
        log "❌ Database '$database' não encontrado!"
    fi
    
    echo
done

log "🎉 Teste de detecção concluído!"
log "💡 Para executar backup real: docker-compose up"
