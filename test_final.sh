#!/bin/bash

# =============================================================================
# TESTE DIRETO NO CONTAINER - SEM ENTRYPOINT
# =============================================================================

echo "🔍 TESTE DE DETECÇÃO - BYPASS ENTRYPOINT"
echo "========================================"
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

if [[ ! -f .env ]]; then
    echo "❌ Arquivo .env não encontrado!"
    exit 1
fi

echo "✅ Configurações encontradas"
echo

# Usar --entrypoint para bypass do entrypoint personalizado
echo "🚀 Executando análise direta no container..."
echo

echo "📊 1. Testando conexão..."
$DOCKER_COMPOSE_CMD run --rm --entrypoint="" mariadb-backup bash -c '
source /app/entrypoint.sh > /dev/null 2>&1 || true
mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT \"✅ Conexão OK\" as status;" 2>/dev/null
'

echo
echo "📋 2. Listando tabelas por tamanho..."
$DOCKER_COMPOSE_CMD run --rm --entrypoint="" mariadb-backup bash -c '
source /app/entrypoint.sh > /dev/null 2>&1 || true
mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "
SELECT 
    table_name as \"📊 Tabela\",
    FORMAT(table_rows, 0) as \"📝 Registros\",
    CONCAT(ROUND((data_length + index_length) / 1024 / 1024, 1), \" MB\") as \"💾 Tamanho\"
FROM information_schema.tables 
WHERE table_schema = \"$DATABASES\" 
ORDER BY (data_length + index_length) DESC
LIMIT 10;
" 2>/dev/null
'

echo
echo "🔍 3. Detectando tabelas grandes..."
$DOCKER_COMPOSE_CMD run --rm --entrypoint="" mariadb-backup bash -c '
source /app/entrypoint.sh > /dev/null 2>&1 || true

echo "⚙️  Configurações:"
echo "   Limite: ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
echo "   Chunk size: ${CHUNK_SIZE:-50000} registros"
echo "   Timeout/chunk: $((${CHUNK_TIMEOUT:-1800}/60)) minutos"
echo

# Buscar tabelas grandes
large_tables=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e "
SELECT CONCAT(table_name, \":\", ROUND((data_length + index_length) / 1024 / 1024, 1), \":\", IFNULL(table_rows, 0))
FROM information_schema.tables 
WHERE table_schema = \"$DATABASES\" 
AND (data_length + index_length) > (${CHUNK_SIZE_THRESHOLD_MB:-1000} * 1024 * 1024)
ORDER BY (data_length + index_length) DESC;
" 2>/dev/null)

if [[ -n "$large_tables" ]]; then
    echo "⚡ TABELAS GRANDES DETECTADAS!"
    echo
    echo "🎯 ESTRATÉGIA: BACKUP HÍBRIDO"
    echo "   ✅ Tabelas grandes: processadas por chunks"
    echo "   ✅ Tabelas pequenas: backup tradicional"
    echo "   ✅ Resultado: arquivo único consolidado"
    echo
    
    total_chunks=0
    total_time_min=0
    
    echo "🔧 ANÁLISE DETALHADA:"
    while IFS=":" read -r table_name size_mb table_rows; do
        if [[ $table_rows -gt 0 ]]; then
            chunks=$((($table_rows + ${CHUNK_SIZE:-50000} - 1) / ${CHUNK_SIZE:-50000}))
        else
            chunks=1
        fi
        total_chunks=$((total_chunks + chunks))
        time_min=$((chunks * ${CHUNK_TIMEOUT:-1800} / 60))
        total_time_min=$((total_time_min + time_min))
        
        echo
        echo "   📊 $table_name"
        echo "      💾 Tamanho: ${size_mb}MB"
        echo "      📝 Registros: $(printf \"%'"'"'d\" $table_rows)"
        echo "      📦 Chunks: $chunks"
        echo "      ⏰ Tempo: ${time_min}min (~$((time_min/60))h)"
        
    done <<< "$large_tables"
    
    total_hours=$((total_time_min / 60))
    
    echo
    echo "📈 RESUMO FINAL:"
    echo "   🔢 Total de chunks: $total_chunks"
    echo "   ⏳ Tempo total estimado: ${total_hours}h ${total_time_min}min"
    
    echo
    if [[ $total_hours -gt 48 ]]; then
        echo "⚠️  RECOMENDAÇÕES (tempo muito longo):"
        echo "   - CHUNK_SIZE=100000 (reduz chunks pela metade)"
        echo "   - CHUNK_TIMEOUT=3600 (1h por chunk)"
        echo "   - Executar em final de semana"
    elif [[ $total_hours -gt 24 ]]; then
        echo "💡 RECOMENDAÇÕES (tempo considerável):"
        echo "   - CHUNK_SIZE=75000 (reduz chunks)"
        echo "   - Executar em horário de baixo uso"
    else
        echo "✅ CONFIGURAÇÕES ADEQUADAS"
        echo "   - Tempo aceitável para execução"
    fi
    
else
    echo "ℹ️  NENHUMA TABELA > ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
    echo
    echo "🎯 ESTRATÉGIA: BACKUP TRADICIONAL"
    echo "   ✅ Todas as tabelas: mysqldump padrão"
    echo "   ✅ Tempo estimado: < 30min"
fi
'

echo
echo "🎉 ANÁLISE CONCLUÍDA!"
echo
echo "🚀 AÇÕES RECOMENDADAS:"
echo "   1. ✅ Revisar análise acima"
echo "   2. 🔧 Ajustar .env se necessário"
echo "   3. 🚀 Executar: docker compose up"
echo "   4. 📊 Monitorar: tail -f logs/backup.log"
