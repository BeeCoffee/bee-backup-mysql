#!/bin/bash

# =============================================================================
# TESTE DE DETECÇÃO USANDO CONTAINER DOCKER - VERSÃO CORRIGIDA
# =============================================================================
# Este script executa o teste de detecção dentro do container Docker

echo "🐳 TESTE DE DETECÇÃO - VIA CONTAINER DOCKER"
echo "==========================================="
echo

# Verificar se docker está disponível
if ! command -v docker &> /dev/null; then
    echo "❌ Docker não encontrado! Instale o Docker primeiro."
    exit 1
fi

# Verificar Docker Compose (plugin ou standalone)
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    echo "❌ Docker Compose não encontrado! Instale o Docker Compose primeiro."
    exit 1
fi

echo "✅ Usando: $DOCKER_COMPOSE_CMD"

echo "📁 Diretório atual: $(pwd)"
echo "🔍 Verificando se .env existe..."

if [[ ! -f .env ]]; then
    echo "❌ Arquivo .env não encontrado!"
    echo "💡 Copie o .env.example: cp .env.example .env"
    exit 1
fi

echo "✅ Arquivo .env encontrado"
echo

# Criar script de teste que será executado dentro do container
echo "🔧 Criando script temporário de detecção..."
cat > ./scripts/temp_detection_test.sh << 'EOF'
#!/bin/bash

echo "🔍 TESTE DE DETECÇÃO DENTRO DO CONTAINER"
echo "======================================="
echo
echo "📊 Configurações do ambiente:"
echo "   Database: $DATABASES"
echo "   Servidor origem: ${SOURCE_HOST}:${SOURCE_PORT}"
echo "   Usuário: $DB_USERNAME"
echo "   Limite detecção: ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB"
echo "   Tamanho do chunk: ${CHUNK_SIZE:-50000} registros"
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
log "🔌 Testando conexão com o servidor de origem..."
if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 'Conexão OK' as status;" 2>/tmp/mysql_error.log; then
    log "✅ Conexão estabelecida com sucesso!"
    echo
else
    log "❌ Erro de conexão:"
    if [[ -f /tmp/mysql_error.log ]]; then
        log "📋 Detalhes do erro: $(cat /tmp/mysql_error.log)"
    fi
    log "🔍 Verifique:"
    log "   - Servidor MySQL está rodando?"
    log "   - Credenciais estão corretas?"
    log "   - Firewall/rede permite conexão?"
    exit 1
fi

# Verificar se database existe
log "📦 Verificando se database '$DATABASES' existe..."
if mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "USE $DATABASES; SELECT 'Database encontrado' as status;" 2>/dev/null; then
    log "✅ Database '$DATABASES' encontrado"
else
    log "❌ Database '$DATABASES' não encontrado ou sem permissão!"
    exit 1
fi

echo

# Obter tamanho total do database
log "📊 Analisando tamanho total do database..."
db_size=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
    "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) 
     FROM information_schema.tables 
     WHERE table_schema='$DATABASES';" 2>/dev/null || echo "0.0")

log "   📏 Tamanho total do database: ${db_size}MB"

echo

# Listar todas as tabelas com seus tamanhos
log "📋 Listando todas as tabelas por tamanho..."
mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "
SELECT 
    table_name as 'Tabela',
    table_rows as 'Registros_Estimados',
    ROUND((data_length + index_length) / 1024 / 1024, 2) as 'Tamanho_MB'
FROM information_schema.tables 
WHERE table_schema = '$DATABASES' 
ORDER BY (data_length + index_length) DESC
LIMIT 15;
" 2>/dev/null

echo

# Detectar tabelas grandes baseado no limite configurado
log "🔍 Detectando tabelas grandes (> ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB)..."

large_tables=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
    "SELECT CONCAT(table_name, ':', ROUND((data_length + index_length) / 1024 / 1024, 2), ':', table_rows)
     FROM information_schema.tables 
     WHERE table_schema = '$DATABASES' 
     AND (data_length + index_length) > (${CHUNK_SIZE_THRESHOLD_MB:-1000} * 1024 * 1024)
     ORDER BY (data_length + index_length) DESC;" 2>/dev/null)

if [[ -n "$large_tables" ]]; then
    log "⚡ TABELAS GRANDES DETECTADAS!"
    echo
    log "🎯 ESTRATÉGIA: BACKUP HÍBRIDO será usado"
    log "   - Tabelas grandes: Processadas por chunks"
    log "   - Tabelas pequenas: Backup tradicional" 
    log "   - Resultado: Arquivo único consolidado"
    echo
    
    log "🔧 Tabelas que serão processadas por CHUNKS:"
    total_chunks_estimated=0
    
    while IFS=':' read -r table_name size_mb table_rows; do
        # Calcular chunks estimados
        chunks_needed=$(( ($table_rows + ${CHUNK_SIZE:-50000} - 1) / ${CHUNK_SIZE:-50000} ))
        total_chunks_estimated=$((total_chunks_estimated + chunks_needed))
        
        # Calcular tempo estimado
        chunk_time_min=$(( ${CHUNK_TIMEOUT:-1800} / 60 ))
        table_time_hours=$(( chunks_needed * chunk_time_min / 60 ))
        
        log "   📊 $table_name:"
        log "      💾 Tamanho: ${size_mb}MB"
        log "      📝 Registros: $(printf "%'d" $table_rows)" 
        log "      📦 Chunks necessários: $chunks_needed"
        log "      ⏰ Tempo estimado: ~${table_time_hours}h (${chunk_time_min}min/chunk)"
        echo
    done <<< "$large_tables"
    
    total_time_hours=$((total_chunks_estimated * chunk_time_min / 60))
    
    echo "📈 RESUMO GERAL:"
    log "   🔢 Total de chunks estimado: $total_chunks_estimated"
    log "   ⏳ Tempo total estimado: ~${total_time_hours}h"
    log "   🎯 Estratégia: Processamento automático por chunks"
    
    echo
    log "💡 RECOMENDAÇÕES PARA OTIMIZAÇÃO:"
    if [[ $total_time_hours -gt 48 ]]; then
        log "   ⚠️  Tempo muito longo! Considere:"
        log "      - CHUNK_SIZE=100000 (chunks maiores = menos chunks)"
        log "      - CHUNK_TIMEOUT=3600 (1h por chunk)"
        log "      - Executar em final de semana"
    elif [[ $total_time_hours -gt 24 ]]; then
        log "   ⚡ Tempo considerável. Recomendações:"
        log "      - CHUNK_SIZE=75000 (chunks um pouco maiores)"
        log "      - Executar em horário de menor uso"
    else
        log "   ✅ Tempo aceitável com configurações atuais"
    fi
    
else
    log "ℹ️  NENHUMA TABELA GRANDE detectada (todas < ${CHUNK_SIZE_THRESHOLD_MB:-1000}MB)"
    log "🎯 ESTRATÉGIA: Backup tradicional será usado"
    log "   - Todas as tabelas: mysqldump tradicional"
    log "   - Tempo estimado: < 1h"
fi

echo
log "🎉 Análise de detecção concluída!"
log "💡 Para executar backup real: docker compose up"

echo
echo "🚀 PRÓXIMOS PASSOS:"
echo "   1. Se satisfeito com a análise: docker compose up"
echo "   2. Para otimizar: ajuste CHUNK_SIZE no .env"
echo "   3. Para monitorar: acompanhe logs em tempo real"
EOF

chmod +x ./scripts/temp_detection_test.sh

echo "🚀 Executando análise de detecção no container..."
echo

# Executar o script usando o modo shell
if $DOCKER_COMPOSE_CMD run --rm mariadb-backup shell /scripts/temp_detection_test.sh; then
    echo
    echo "✅ Análise de detecção concluída com sucesso!"
    echo
    echo "🎯 RESULTADO: O sistema está pronto para detectar e processar"
    echo "    tabelas grandes automaticamente usando chunks!"
    echo
else
    echo
    echo "❌ Análise falhou. Verifique as configurações no .env"
    exit 1
fi

# Limpar arquivo temporário
rm -f ./scripts/temp_detection_test.sh

echo "🧹 Arquivo temporário removido."
