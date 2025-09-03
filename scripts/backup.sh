#!/bin/bash

# =============================================================================
# SCRIPT DE BACKUP MARIADB/MYSQL
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_START_TIME=$(date +%s)
BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')
TOTAL_DATABASES=0
SUCCESSFUL_BACKUPS=0
FAILED_BACKUPS=0
TOTAL_SIZE=0

# Função para logging com timestamp
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" | tee -a /logs/backup.log
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" | tee -a /logs/backup.log
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message" | tee -a /logs/backup.log
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" | tee -a /logs/backup.log
            ;;
    esac
}

# Função para enviar notificações
send_notification() {
    local status=$1
    local message=$2
    
    # Email
    if [[ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" == "true" ]]; then
        /scripts/send_email.sh "$status" "$message" &
    fi
    
    # Webhook
    if [[ -n "${WEBHOOK_URL}" ]]; then
        /scripts/send_webhook.sh "$status" "$message" &
    fi
}

# Função para verificar se database existe
database_exists() {
    local database=$1
    local host=$2
    local port=$3
    
    if mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "USE $database;" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Função para obter tamanho do banco de dados
get_database_size() {
    local database=$1
    local host=$2
    local port=$3
    
    mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' 
            FROM information_schema.tables 
            WHERE table_schema='$database';" \
        --skip-column-names --batch 2>/dev/null || echo "0.0"
}

# Função para fazer backup de um database
backup_database() {
    local database=$1
    local backup_file="/backups/${BACKUP_PREFIX:-backup}_${database}_${BACKUP_DATE}.sql"
    
    log "INFO" "📦 Iniciando backup do database '$database'..."
    
    # Verificar se database existe no servidor de origem
    if ! database_exists "$database" "$SOURCE_HOST" "$SOURCE_PORT"; then
        log "ERROR" "❌ Database '$database' não existe no servidor de origem"
        ((FAILED_BACKUPS++))
        return 1
    fi
    
    # Obter tamanho do database
    local db_size=$(get_database_size "$database" "$SOURCE_HOST" "$SOURCE_PORT")
    log "INFO" "   Tamanho do database: ${db_size} MB"
    
    # Executar mysqldump
    local dump_cmd="mysqldump -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    
    # Adicionar opções personalizadas
    if [[ -n "${MYSQLDUMP_OPTIONS}" ]]; then
        dump_cmd="$dump_cmd ${MYSQLDUMP_OPTIONS}"
    fi
    
    dump_cmd="$dump_cmd '$database'"
    
    # Executar backup
    local start_time=$(date +%s)
    
    if eval "$dump_cmd" > "$backup_file" 2>/tmp/mysqldump_error_${database}.log; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        # Verificar se arquivo foi criado e não está vazio
        if [[ -s "$backup_file" ]]; then
            local file_size=$(stat -c%s "$backup_file")
            local file_size_mb=$(echo "scale=1; $file_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            
            # Comprimir se habilitado
            if [[ "${BACKUP_COMPRESSION:-true}" == "true" ]]; then
                log "INFO" "   🗜️  Comprimindo backup..."
                if gzip "$backup_file"; then
                    backup_file="${backup_file}.gz"
                    local compressed_size=$(stat -c%s "$backup_file")
                    local compressed_size_mb=$(echo "scale=1; $compressed_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
                    file_size_mb="$compressed_size_mb"
                    log "INFO" "   ✅ Compressão concluída (${compressed_size_mb} MB)"
                else
                    log "WARNING" "   ⚠️  Falha na compressão, mantendo arquivo original"
                fi
            fi
            
            log "SUCCESS" "✅ Backup do '$database' concluído (${file_size_mb} MB em ${duration}s)"
            TOTAL_SIZE=$(echo "$TOTAL_SIZE + $file_size_mb" | bc 2>/dev/null || echo "$TOTAL_SIZE")
            
            # Verificar integridade se habilitado
            if [[ "${VERIFY_BACKUP_INTEGRITY:-true}" == "true" ]]; then
                verify_backup_integrity "$backup_file" "$database"
            fi
            
            # Restaurar no servidor de destino
            restore_to_destination "$backup_file" "$database"
            
            ((SUCCESSFUL_BACKUPS++))
            return 0
        else
            log "ERROR" "❌ Arquivo de backup vazio ou não foi criado"
            if [[ -f "/tmp/mysqldump_error_${database}.log" ]]; then
                log "ERROR" "   Erro do mysqldump: $(cat /tmp/mysqldump_error_${database}.log)"
            fi
            ((FAILED_BACKUPS++))
            return 1
        fi
    else
        log "ERROR" "❌ Falha no mysqldump para '$database'"
        if [[ -f "/tmp/mysqldump_error_${database}.log" ]]; then
            log "ERROR" "   Erro: $(cat /tmp/mysqldump_error_${database}.log)"
        fi
        ((FAILED_BACKUPS++))
        return 1
    fi
}

# Função para verificar integridade do backup
verify_backup_integrity() {
    local backup_file=$1
    local database=$2
    
    log "INFO" "   🔍 Verificando integridade do backup..."
    
    # Se for arquivo comprimido, verificar se pode ser descomprimido
    if [[ "$backup_file" == *.gz ]]; then
        if gzip -t "$backup_file" 2>/dev/null; then
            log "SUCCESS" "   ✅ Integridade do arquivo comprimido verificada"
        else
            log "ERROR" "   ❌ Arquivo comprimido corrompido"
            return 1
        fi
    fi
    
    # Verificar se o arquivo contém SQL válido
    local sql_content=""
    if [[ "$backup_file" == *.gz ]]; then
        sql_content=$(zcat "$backup_file" | head -20)
    else
        sql_content=$(head -20 "$backup_file")
    fi
    
    if echo "$sql_content" | grep -q "CREATE DATABASE\|USE \`$database\`\|DROP DATABASE"; then
        log "SUCCESS" "   ✅ Conteúdo SQL válido verificado"
        return 0
    else
        log "WARNING" "   ⚠️  Conteúdo SQL pode estar incompleto"
        return 1
    fi
}

# Função para restaurar backup no servidor de destino
restore_to_destination() {
    local backup_file=$1
    local database=$2
    
    log "INFO" "   🔄 Restaurando '$database' no servidor de destino..."
    
    # Preparar comando de restauração
    local restore_cmd="mysql -h'$DEST_HOST' -P'$DEST_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    
    # Executar restauração
    local start_time=$(date +%s)
    
    if [[ "$backup_file" == *.gz ]]; then
        if zcat "$backup_file" | eval "$restore_cmd" 2>/tmp/mysql_restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "   ✅ Restauração do '$database' concluída (${duration}s)"
            return 0
        else
            log "ERROR" "   ❌ Falha na restauração do '$database'"
            if [[ -f "/tmp/mysql_restore_error_${database}.log" ]]; then
                log "ERROR" "   Erro: $(cat /tmp/mysql_restore_error_${database}.log)"
            fi
            return 1
        fi
    else
        if eval "$restore_cmd" < "$backup_file" 2>/tmp/mysql_restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "   ✅ Restauração do '$database' concluída (${duration}s)"
            return 0
        else
            log "ERROR" "   ❌ Falha na restauração do '$database'"
            if [[ -f "/tmp/mysql_restore_error_${database}.log" ]]; then
                log "ERROR" "   Erro: $(cat /tmp/mysql_restore_error_${database}.log)"
            fi
            return 1
        fi
    fi
}

# Função para limpeza de backups antigos
cleanup_old_backups() {
    local retention_days=${RETENTION_DAYS:-7}
    
    log "INFO" "🧹 Iniciando limpeza de backups antigos (>${retention_days} dias)..."
    
    local deleted_count=0
    local deleted_size=0
    
    # Encontrar e remover arquivos antigos
    while IFS= read -r -d '' file; do
        local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
        local file_size_mb=$(echo "scale=1; $file_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
        
        rm "$file"
        ((deleted_count++))
        deleted_size=$(echo "$deleted_size + $file_size_mb" | bc 2>/dev/null || echo "$deleted_size")
        
        log "INFO" "   🗑️  Removido: $(basename "$file") (${file_size_mb} MB)"
    done < <(find /backups -name "${BACKUP_PREFIX:-backup}_*.sql*" -type f -mtime +$retention_days -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "SUCCESS" "✅ Limpeza concluída: ${deleted_count} arquivos removidos (${deleted_size} MB liberados)"
    else
        log "INFO" "ℹ️  Nenhum backup antigo encontrado para remoção"
    fi
}

# Função para exibir resumo final
show_summary() {
    local script_end_time=$(date +%s)
    local total_duration=$((script_end_time - SCRIPT_START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    log "INFO" "=========================================="
    log "INFO" "📊 RESUMO FINAL DO BACKUP"
    log "INFO" "=========================================="
    log "INFO" "🗃️  Total de databases: ${TOTAL_DATABASES}"
    log "SUCCESS" "✅ Backups bem-sucedidos: ${SUCCESSFUL_BACKUPS}"
    if [[ $FAILED_BACKUPS -gt 0 ]]; then
        log "ERROR" "❌ Backups falharam: ${FAILED_BACKUPS}"
    fi
    log "INFO" "📦 Tamanho total dos backups: ${TOTAL_SIZE} MB"
    log "INFO" "⏱️  Tempo total de execução: ${minutes}m ${seconds}s"
    log "INFO" "🗂️  Diretório de backups: /backups"
    log "INFO" "=========================================="
    
    # Determinar status geral
    if [[ $FAILED_BACKUPS -eq 0 ]]; then
        log "SUCCESS" "🎉 TODOS OS BACKUPS CONCLUÍDOS COM SUCESSO!"
        send_notification "success" "Backup concluído com sucesso: ${SUCCESSFUL_BACKUPS}/${TOTAL_DATABASES} databases"
        return 0
    else
        log "ERROR" "❌ ALGUNS BACKUPS FALHARAM!"
        send_notification "error" "Backup com falhas: ${SUCCESSFUL_BACKUPS}/${TOTAL_DATABASES} databases bem-sucedidos"
        return 1
    fi
}

# Função principal
main() {
    # Verificar se bc está disponível para cálculos
    if ! command -v bc >/dev/null 2>&1; then
        log "WARNING" "⚠️  Comando 'bc' não encontrado, cálculos de tamanho podem ser imprecisos"
    fi
    
    log "INFO" "=========================================="
    log "INFO" "🚀 INICIANDO PROCESSO DE BACKUP"
    log "INFO" "=========================================="
    log "INFO" "📅 Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "🖥️  Servidor origem: ${SOURCE_HOST}:${SOURCE_PORT}"
    log "INFO" "🎯 Servidor destino: ${DEST_HOST}:${DEST_PORT}"
    log "INFO" "👤 Usuário: ${DB_USERNAME}"
    
    # Processar lista de databases
    IFS=',' read -ra DB_ARRAY <<< "${DATABASES}"
    TOTAL_DATABASES=${#DB_ARRAY[@]}
    
    # Remover espaços em branco dos nomes dos databases
    for i in "${!DB_ARRAY[@]}"; do
        DB_ARRAY[$i]=$(echo "${DB_ARRAY[$i]}" | xargs)
    done
    
    log "INFO" "📋 Databases selecionados: ${DB_ARRAY[*]}"
    log "INFO" "🔧 Opções do mysqldump: ${MYSQLDUMP_OPTIONS:-default}"
    log "INFO" "🗜️  Compressão: ${BACKUP_COMPRESSION:-true}"
    log "INFO" "🗓️  Retenção: ${RETENTION_DAYS:-7} dias"
    log "INFO" "=========================================="
    
    # Processar cada database
    for database in "${DB_ARRAY[@]}"; do
        if [[ -n "$database" ]]; then
            backup_database "$database"
        fi
    done
    
    # Limpeza de backups antigos
    cleanup_old_backups
    
    # Exibir resumo final
    show_summary
}

# Executar função principal
main "$@"
