#!/bin/bash

# =============================================================================
# TESTE SIMPLES DE DETECÇÃO - EXECUÇÃO DIRETA
# =============================================================================

echo "🔍 TESTE DE DETECÇÃO DE TABELAS GRANDES - PRODUÇÃO"
echo "=================================================="
echo

# Verificar Docker Compose
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "❌ Docker Compose não encontrado!"
    exit 1
fi

echo "✅ Usando: $DOCKER_COMPOSE_CMD"

if [[ ! -f .env ]]; then
    echo "❌ Arquivo .env não encontrado!"
    exit 1
fi

echo "✅ Arquivo .env encontrado"
echo

echo "🚀 Executando análise das tabelas..."
echo

# Executar comandos diretos no container
echo "📊 1. Testando conexão..."
$DOCKER_COMPOSE_CMD run --rm mariadb-backup bash -c '
mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT \"✅ Conexão OK\" as status;"
'

echo
echo "📋 2. Listando tabelas por tamanho..."
$DOCKER_COMPOSE_CMD run --rm mariadb-backup bash -c '
mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "
SELECT 
    table_name as \"Tabela\",
    table_rows as \"Registros\",
    ROUND((data_length + index_length) / 1024 / 1024, 2) as \"Tamanho_MB\"
FROM information_schema.tables 
WHERE table_schema = \"$DATABASES\" 
ORDER BY (data_length + index_length) DESC
LIMIT 10;
"
'

echo
echo "🔍 3. Detectando tabelas grandes (>1GB)..."
$DOCKER_COMPOSE_CMD run --rm mariadb-backup bash -c '
echo "Limite configurado: ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
echo "Tamanho do chunk: ${CHUNK_SIZE:-50000} registros"
echo

large_tables=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "
SELECT CONCAT(table_name, \":\", ROUND((data_length + index_length) / 1024 / 1024, 2), \":\", table_rows)
FROM information_schema.tables 
WHERE table_schema = \"$DATABASES\" 
AND (data_length + index_length) > (${CHUNK_SIZE_THRESHOLD_MB:-1000} * 1024 * 1024)
ORDER BY (data_length + index_length) DESC;
")

if [[ -n "$large_tables" ]]; then
    echo "⚡ TABELAS GRANDES DETECTADAS!"
    echo
    echo "🎯 ESTRATÉGIA: BACKUP HÍBRIDO"
    echo "  - Tabelas grandes: chunks de ${CHUNK_SIZE:-50000} registros"
    echo "  - Tabelas pequenas: backup tradicional"
    echo
    
    total_chunks=0
    while IFS=":" read -r table_name size_mb table_rows; do
        chunks=$((($table_rows + ${CHUNK_SIZE:-50000} - 1) / ${CHUNK_SIZE:-50000}))
        total_chunks=$((total_chunks + chunks))
        time_hours=$((chunks * ${CHUNK_TIMEOUT:-1800} / 3600))
        
        echo "📊 $table_name:"
        echo "   💾 Tamanho: ${size_mb}MB"
        echo "   📝 Registros: $(printf \"%'"'"'d\" $table_rows)"
        echo "   📦 Chunks: $chunks"
        echo "   ⏰ Tempo estimado: ~${time_hours}h"
        echo
    done <<< "$large_tables"
    
    total_time=$((total_chunks * ${CHUNK_TIMEOUT:-1800} / 3600))
    echo "📈 RESUMO TOTAL:"
    echo "   🔢 Chunks totais: $total_chunks" 
    echo "   ⏳ Tempo total: ~${total_time}h"
    
    if [[ $total_time -gt 24 ]]; then
        echo
        echo "💡 RECOMENDAÇÕES:"
        echo "   - Considere CHUNK_SIZE=100000 (chunks maiores)"
        echo "   - Execute em horário de baixo uso"
        echo "   - Monitore progresso nos logs"
    fi
else
    echo "ℹ️  Nenhuma tabela > ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB detectada"
    echo "🎯 Será usado backup tradicional"
fi
'

echo
echo "🎉 Análise concluída!"
echo
echo "🚀 PRÓXIMOS PASSOS:"
echo "   1. Se satisfeito: docker compose up"
echo "   2. Para otimizar: ajuste CHUNK_SIZE no .env"
echo "   3. Monitore: tail -f logs/backup.log"
