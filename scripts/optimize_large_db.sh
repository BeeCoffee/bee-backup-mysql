#!/bin/bash

# =============================================================================
# SCRIPT DE OTIMIZAÇÃO PARA DATABASES GRANDES - SISTEMA BACKUP MYSQL
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR]${NC} $message"
            ;;
    esac
}

# Função para analisar database
analyze_database() {
    local database=$1
    local host=$2
    local port=$3
    
    log "INFO" "🔍 Analisando database '$database'..."
    
    # Obter informações detalhadas
    local query="
    SELECT 
        table_schema,
        COUNT(*) as table_count,
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'size_mb',
        ROUND(AVG(table_rows), 0) as avg_rows_per_table,
        MAX(table_rows) as max_rows_per_table
    FROM information_schema.tables 
    WHERE table_schema='$database' 
    GROUP BY table_schema;
    "
    
    log "INFO" "   📊 Estatísticas gerais:"
    mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "$query" 2>/dev/null || log "ERROR" "Falha ao obter estatísticas"
    
    # Identificar tabelas grandes
    local large_tables_query="
    SELECT 
        table_name,
        table_rows,
        ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'size_mb'
    FROM information_schema.tables 
    WHERE table_schema='$database' 
    AND table_rows > 1000000
    ORDER BY table_rows DESC
    LIMIT 10;
    "
    
    log "INFO" "   📋 Top 10 tabelas com mais registros:"
    mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "$large_tables_query" 2>/dev/null || log "ERROR" "Falha ao obter tabelas grandes"
}

# Função para verificar configurações do MySQL
check_mysql_config() {
    local host=$1
    local port=$2
    
    log "INFO" "🔧 Verificando configurações do MySQL..."
    
    # Verificar configurações importantes para backup
    local config_query="
    SHOW VARIABLES WHERE Variable_name IN (
        'max_allowed_packet',
        'net_read_timeout', 
        'net_write_timeout',
        'connect_timeout',
        'interactive_timeout',
        'wait_timeout',
        'innodb_lock_wait_timeout'
    );
    "
    
    mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "$config_query" 2>/dev/null || log "ERROR" "Falha ao verificar configurações"
}

# Função para sugerir otimizações
suggest_optimizations() {
    local database=$1
    local db_size=$2
    
    log "INFO" "💡 Sugestões de otimização para '$database' (${db_size} MB):"
    
    if [[ $(echo "$db_size > 50000" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        log "INFO" "   ✅ Database grande detectado - aplicar configurações especiais:"
        log "INFO" "      • Usar --quick para reduzir uso de memória"
        log "INFO" "      • Usar --single-transaction para consistência"
        log "INFO" "      • Usar --extended-insert=false para melhor recuperação de erros"
        log "INFO" "      • Aumentar timeouts: NET_READ_TIMEOUT=7200, NET_WRITE_TIMEOUT=7200"
        log "INFO" "      • Aumentar MAX_ALLOWED_PACKET=1G"
        log "INFO" "      • Configurar MYSQLDUMP_TIMEOUT=21600 (6 horas)"
        log "INFO" "      • Ativar sistema de retry: MAX_RETRY_ATTEMPTS=3"
    else
        log "INFO" "   ℹ️  Database de tamanho médio - configurações padrão são adequadas"
    fi
    
    log "INFO" "   🚀 Recomendações gerais:"
    log "INFO" "      • Executar backup em horário de baixo uso"
    log "INFO" "      • Monitorar logs durante o processo"
    log "INFO" "      • Verificar espaço em disco disponível"
    log "INFO" "      • Considerar backup incremental para bases muito grandes"
}

# Função para testar conexão otimizada
test_optimized_connection() {
    local host=$1
    local port=$2
    
    log "INFO" "🔌 Testando conexão otimizada..."
    
    # Testar com configurações otimizadas
    local test_cmd="mysql -h'$host' -P'$port' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    test_cmd="$test_cmd --connect-timeout=300"
    test_cmd="$test_cmd --net-read-timeout=7200" 
    test_cmd="$test_cmd --net-write-timeout=7200"
    
    if timeout 10 $test_cmd -e "SELECT 1;" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Conexão otimizada bem-sucedida"
        return 0
    else
        log "ERROR" "❌ Falha na conexão otimizada"
        return 1
    fi
}

# Função para estimativa de tempo
estimate_backup_time() {
    local database=$1
    local db_size=$2
    
    log "INFO" "⏱️  Estimando tempo de backup para '$database'..."
    
    # Estimativa baseada em tamanho (aproximadamente 50MB/min em condições normais)
    # Para databases grandes, a velocidade pode ser menor devido a I/O
    local estimated_minutes
    if [[ $(echo "$db_size > 50000" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        # Para DBs grandes: ~30MB/min
        estimated_minutes=$(echo "$db_size / 30" | bc -l 2>/dev/null || echo "0")
    else
        # Para DBs menores: ~50MB/min  
        estimated_minutes=$(echo "$db_size / 50" | bc -l 2>/dev/null || echo "0")
    fi
    
    local hours=$(echo "$estimated_minutes / 60" | bc -l 2>/dev/null || echo "0")
    local minutes=$(echo "$estimated_minutes % 60" | bc -l 2>/dev/null || echo "0")
    
    log "INFO" "   📅 Tempo estimado: ~$(printf "%.0f" $hours)h $(printf "%.0f" $minutes)m"
    log "INFO" "   ⚠️  Estimativa baseada em condições ideais - pode variar conforme carga do servidor"
}

# Função principal
main() {
    local database="${1:-$DATABASES}"
    
    if [[ -z "$database" ]]; then
        log "ERROR" "❌ Database não especificado"
        log "INFO" "Uso: $0 <nome_do_database>"
        exit 1
    fi
    
    log "INFO" "🚀 Iniciando análise de otimização para '$database'"
    log "INFO" "=================================================="
    
    # Verificar variáveis necessárias
    if [[ -z "$DB_USERNAME" || -z "$DB_PASSWORD" || -z "$SOURCE_HOST" || -z "$SOURCE_PORT" ]]; then
        log "ERROR" "❌ Variáveis de ambiente não configuradas"
        exit 1
    fi
    
    # Testar conexão
    if ! test_optimized_connection "$SOURCE_HOST" "$SOURCE_PORT"; then
        log "ERROR" "❌ Não é possível conectar ao servidor"
        exit 1
    fi
    
    # Obter tamanho do database
    local db_size=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' 
            FROM information_schema.tables 
            WHERE table_schema='$database';" \
        --skip-column-names --batch 2>/dev/null || echo "0.0")
    
    if [[ "$db_size" == "0.0" ]]; then
        log "ERROR" "❌ Database '$database' não encontrado ou vazio"
        exit 1
    fi
    
    log "SUCCESS" "✅ Database '$database' encontrado: ${db_size} MB"
    
    # Executar análises
    analyze_database "$database" "$SOURCE_HOST" "$SOURCE_PORT"
    check_mysql_config "$SOURCE_HOST" "$SOURCE_PORT"
    suggest_optimizations "$database" "$db_size"
    estimate_backup_time "$database" "$db_size"
    
    log "INFO" "=================================================="
    log "SUCCESS" "🎉 Análise concluída para '$database'"
}

# Verificar se o script está sendo executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
