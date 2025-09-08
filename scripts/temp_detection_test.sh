#!/bin/bash

# Carregar variáveis do ambiente
echo "🔍 TESTE DE DETECÇÃO DENTRO DO CONTAINER"
echo "======================================="
echo
echo "📊 Configurações:"
echo "   Database: $DATABASES"
echo "   Servidor: ${SOURCE_HOST}:${SOURCE_PORT}"
echo "   Usuário: $DB_USERNAME"
echo "   Limite: ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
echo

# Função de log
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Verificar se mysql client está disponível
if ! command -v mysql &> /dev/null; then
    log "❌ Cliente MySQL não encontrado no container!"
    exit 1
fi

log "✅ Cliente MySQL encontrado no container"

# Testar conexão
log "🔌 Testando conexão com o database..."
if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1 as test;" 2>/tmp/mysql_error.log; then
    log "✅ Conexão estabelecida com sucesso!"
else
    log "❌ Erro de conexão:"
    if [[ -f /tmp/mysql_error.log ]]; then
        log "📋 Detalhes: $(cat /tmp/mysql_error.log)"
    fi
    exit 1
fi

echo

# Função para detectar tabelas grandes
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

# Processar cada database
IFS=',' read -ra DB_ARRAY <<< "$DATABASES"
for database in "${DB_ARRAY[@]}"; do
    database=$(echo "$database" | xargs) # Remove espaços
    
    log "📦 Analisando database: '$database'"
    
    # Verificar se database existe
    if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "USE $database; SELECT 'Database exists' as status;" &>/dev/null; then
        
        # Obter tamanho total do database
        local db_size=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
            "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) 
             FROM information_schema.tables 
             WHERE table_schema='$database';" 2>/dev/null || echo "0.0")
        
        log "   📊 Tamanho total do database: ${db_size}MB"
        
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
                log "   📊 $table_name: ${size_mb}MB ($(printf "%'d" $total_rows) registros = ~$estimated_chunks chunks)"
                
                # Calcular tempo estimado
                local chunk_time_min=$(( ${CHUNK_TIMEOUT:-1800} / 60 ))
                local total_time_hours=$(( $estimated_chunks * $chunk_time_min / 60 ))
                log "      ⏰ Tempo estimado: ~${total_time_hours}h (${chunk_time_min}min/chunk)"
            done <<< "$large_tables"
            
            echo
            log "💡 RECOMENDAÇÕES PARA OTIMIZAR:"
            log "   - Para acelerar: CHUNK_SIZE=100000 (menos chunks)"
            log "   - Para mais segurança: CHUNK_SIZE=25000 (chunks menores)"
            log "   - Executar em horário de baixo uso"
        else
            log "ℹ️  Database '$database' usará backup tradicional (sem chunks)"
        fi
    else
        log "❌ Database '$database' não encontrado ou sem permissão de acesso!"
    fi
    
    echo
done

log "🎉 Teste de detecção concluído!"
log "💡 Para executar backup real: docker compose up"
