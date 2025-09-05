#!/bin/bash

# =============================================================================
# SCRIPT DE BACKUP MARIADB/MYSQL
# =============================================================================

# set -e temporariamente removido para debug

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
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" >> /logs/backup.log
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" >> /logs/backup.log
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message" >> /logs/backup.log
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" >> /logs/backup.log
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
    
    # Usar MYSQL_CLIENT_OPTIONS se disponível
    if mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
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
    
    local size=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' 
            FROM information_schema.tables 
            WHERE table_schema='$database';" \
        --skip-column-names --batch 2>/dev/null || echo "0.0")
    
    echo "$size"
}

# Função para fazer backup de um database com retry automático
backup_database() {
    local database=$1
    local backup_file="/backups/${BACKUP_PREFIX:-backup}_${database}_${BACKUP_DATE}.sql"
    local max_retries=${MAX_RETRY_ATTEMPTS:-3}
    local retry_interval=${RETRY_INTERVAL:-5}
    
    log "INFO" "📦 Iniciando backup do database '$database'..."
    log "INFO" "   🚀 [ETAPA 1/5] Iniciando extração de dados (mysqldump)..."
    
    # Verificar se database existe no servidor de origem
    if ! database_exists "$database" "$SOURCE_HOST" "$SOURCE_PORT"; then
        log "ERROR" "❌ Database '$database' não existe no servidor de origem"
        ((FAILED_BACKUPS++))
        return 1
    fi
    
    # Obter tamanho do database
    local db_size=$(get_database_size "$database" "$SOURCE_HOST" "$SOURCE_PORT")
    log "INFO" "   Tamanho do database: ${db_size} MB"
    
    # Determinar se é uma base grande (>50GB) e aplicar configurações específicas
    local is_large_db=false
    if [[ $(echo "$db_size > 50000" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        is_large_db=true
        log "INFO" "   ⚡ Database grande detectado (>${db_size} MB) - aplicando configurações otimizadas"
    fi
    
    # Montar comando mysqldump otimizado
    local dump_cmd="mysqldump ${MYSQL_CLIENT_OPTIONS} -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    
    # Montar comando mysqldump otimizado
    local dump_cmd="mysqldump ${MYSQL_CLIENT_OPTIONS} -h'$SOURCE_HOST' -P'$SOURCE_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    
    # Para databases grandes, aplicar configurações especiais
    if [[ "$is_large_db" == true ]]; then
        dump_cmd="$dump_cmd --quick"
        dump_cmd="$dump_cmd --lock-tables=false"
        dump_cmd="$dump_cmd --single-transaction"
        dump_cmd="$dump_cmd --disable-keys"
        dump_cmd="$dump_cmd --extended-insert=false"
        log "INFO" "   🔧 Configurações para database grande aplicadas"
    fi
    
    # Adicionar opções personalizadas do usuário
    if [[ -n "${MYSQLDUMP_OPTIONS}" ]]; then
        dump_cmd="$dump_cmd ${MYSQLDUMP_OPTIONS}"
    fi
    
    dump_cmd="$dump_cmd '$database'"
    
    # Executar backup com sistema de retry
    local start_time=$(date +%s)
    local attempt=1
    local success=false
    
    while [[ $attempt -le $max_retries ]] && [[ "$success" == false ]]; do
        if [[ $attempt -gt 1 ]]; then
            log "WARNING" "   ⚠️  Tentativa ${attempt}/${max_retries} para backup do '$database'"
            sleep $retry_interval
        fi
        
        log "INFO" "   ⏳ Executando mysqldump (tentativa $attempt)..."
        
        if timeout ${MYSQLDUMP_TIMEOUT:-21600} bash -c "$dump_cmd" > "$backup_file" 2>/tmp/mysqldump_error_${database}.log; then
            success=true
        else
            local error_msg=$(cat /tmp/mysqldump_error_${database}.log 2>/dev/null || echo "Erro desconhecido")
            log "ERROR" "❌ Tentativa $attempt falhou: $error_msg"
            
            # Verificar se é erro de conexão que pode ser resolvido com retry
            if echo "$error_msg" | grep -iE "lost connection|timeout|connection reset|can't connect|server has gone away"; then
                if [[ $attempt -lt $max_retries ]]; then
                    log "INFO" "   🔄 Erro de conexão detectado - tentando novamente em ${retry_interval}s"
                    ((attempt++))
                    continue
                else
                    log "ERROR" "   ❌ Todas as tentativas de conexão falharam para '$database'"
                fi
            else
                log "ERROR" "   ❌ Erro não recuperável detectado - abortando backup do '$database'"
                break
            fi
        fi
        
        ((attempt++))
    done
    
    if [[ "$success" == true ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log "SUCCESS" "   ✅ [ETAPA 1/5] Extração de dados concluída (${duration}s)"
        
        # Verificar se arquivo foi criado e não está vazio
        if [[ -s "$backup_file" ]]; then
            local file_size=$(stat -c%s "$backup_file")
            local file_size_mb=$(echo "scale=1; $file_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            
            # Comprimir se habilitado
            if [[ "${BACKUP_COMPRESSION:-true}" == "true" ]]; then
                log "INFO" "   🗜️  [ETAPA 2/5] Iniciando compressão do backup..."
                local compress_start=$(date +%s)
                if gzip "$backup_file"; then
                    local compress_end=$(date +%s)
                    local compress_duration=$((compress_end - compress_start))
                    backup_file="${backup_file}.gz"
                    local compressed_size=$(stat -c%s "$backup_file")
                    local compressed_size_mb=$(echo "scale=1; $compressed_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
                    file_size_mb="$compressed_size_mb"
                    log "SUCCESS" "   ✅ [ETAPA 2/5] Compressão concluída (${compressed_size_mb} MB em ${compress_duration}s)"
                else
                    log "WARNING" "   ⚠️  [ETAPA 2/5] Falha na compressão, mantendo arquivo original"
                fi
            else
                log "INFO" "   ⏭️  [ETAPA 2/5] Compressão desabilitada, pulando..."
            fi
            
            log "SUCCESS" "✅ Backup do '$database' concluído (${file_size_mb} MB em ${duration}s)"
            TOTAL_SIZE=$(echo "$TOTAL_SIZE + $file_size_mb" | bc 2>/dev/null || echo "$TOTAL_SIZE")
            
            # Verificar integridade se habilitado
            if [[ "${VERIFY_BACKUP_INTEGRITY:-true}" == "true" ]]; then
                log "INFO" "   🔍 [ETAPA 3/5] Iniciando verificação de integridade..."
                if verify_backup_integrity "$backup_file" "$database"; then
                    log "SUCCESS" "   ✅ [ETAPA 3/5] Verificação de integridade concluída"
                else
                    log "WARNING" "   ⚠️  [ETAPA 3/5] Verificação com avisos, continuando..."
                fi
            else
                log "INFO" "   ⏭️  [ETAPA 3/5] Verificação de integridade desabilitada, pulando..."
            fi
            
            # Restaurar no servidor de destino (somente se DEST_HOST estiver configurado)
            if [[ -n "${DEST_HOST}" && "${DEST_HOST}" != "" ]]; then
                log "INFO" "   🔄 [ETAPA 4/5] Iniciando restauração no servidor de destino..."
                if restore_to_destination "$backup_file" "$database"; then
                    log "SUCCESS" "🎉 [ETAPA 5/5] Backup completo do '$database' finalizado com sucesso!"
                else
                    log "ERROR" "❌ [ETAPA 4/5] Falha na restauração do '$database', mas backup local foi salvo"
                    log "SUCCESS" "🎉 [ETAPA 4/4] Backup local do '$database' finalizado com sucesso!"
                fi
                log "INFO" "   📊 Tamanho final: ${file_size_mb} MB"
                log "INFO" "   ⏱️  Tempo total: ${duration}s"
                log "INFO" "   🎯 Backup + Restauração executados"
            else
                log "INFO" "   ⏭️  [ETAPA 4/5] DEST_HOST não configurado - pulando restauração"
                log "SUCCESS" "🎉 [ETAPA 4/4] Backup do '$database' finalizado com sucesso!"
                log "INFO" "   📊 Tamanho final: ${file_size_mb} MB"
                log "INFO" "   ⏱️  Tempo total: ${duration}s"
                log "INFO" "   💾 Somente backup executado (sem restauração)"
            fi
            
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
        log "INFO" "   ℹ️  Continuando processo (warning não crítico)"
        return 0
    fi
}

# Função para restaurar backup no servidor de destino
restore_to_destination() {
    local backup_file=$1
    local database=$2
    
    log "INFO" "   🔄 Restaurando '$database' no servidor de destino..."
    log "INFO" "      📍 Servidor: ${DEST_HOST}:${DEST_PORT}"
    log "INFO" "      👤 Usuário: ${DB_USERNAME}"
    log "INFO" "      📁 Database: ${database}"
    
    # Verificar se o banco existe no destino e criá-lo se necessário
    log "INFO" "      🔍 Verificando se o banco '$database' existe no destino..."
    local check_db_cmd="mysql ${MYSQL_CLIENT_OPTIONS} -h'$DEST_HOST' -P'$DEST_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME=\"$database\";'"
    
    if ! eval "$check_db_cmd" 2>/dev/null | grep -q "$database"; then
        log "INFO" "      🏗️  Banco '$database' não existe. Criando..."
        local create_db_cmd="mysql ${MYSQL_CLIENT_OPTIONS} -h'$DEST_HOST' -P'$DEST_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' -e 'CREATE DATABASE IF NOT EXISTS \`$database\`;'"
        if ! eval "$create_db_cmd" 2>/tmp/mysql_create_error_${database}.log; then
            log "ERROR" "   ❌ Falha ao criar banco '$database' no destino"
            if [[ -f "/tmp/mysql_create_error_${database}.log" ]]; then
                log "ERROR" "      📋 Erro detalhado: $(cat /tmp/mysql_create_error_${database}.log)"
            fi
            return 1
        fi
        log "SUCCESS" "      ✅ Banco '$database' criado com sucesso no destino"
    else
        log "INFO" "      ✅ Banco '$database' já existe no destino"
    fi
    
    # Preparar comando de restauração
    local restore_cmd="mysql ${MYSQL_CLIENT_OPTIONS} -h'$DEST_HOST' -P'$DEST_PORT' -u'$DB_USERNAME' -p'$DB_PASSWORD' -f"
    
    # Executar restauração
    local start_time=$(date +%s)
    log "INFO" "      ⏱️  Início da restauração: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ "$backup_file" == *.gz ]]; then
        log "INFO" "      🗜️  Descomprimindo e aplicando backup comprimido..."
        if { echo "USE \`$database\`;"; zcat "$backup_file"; } | eval "$restore_cmd" 2>/tmp/mysql_restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "   ✅ [ETAPA 4/5] Restauração do '$database' concluída!"
            log "INFO" "      ⏱️  Fim da restauração: $(date '+%Y-%m-%d %H:%M:%S')"
            log "INFO" "      🕐 Duração da restauração: ${duration}s"
            return 0
        else
            log "ERROR" "   ❌ [ETAPA 4/5] Falha na restauração do '$database'"
            if [[ -f "/tmp/mysql_restore_error_${database}.log" ]]; then
                log "ERROR" "      📋 Erro detalhado: $(cat /tmp/mysql_restore_error_${database}.log)"
            fi
            return 1
        fi
    else
        log "INFO" "      📄 Aplicando backup não comprimido..."
        if { echo "USE \`$database\`;"; cat "$backup_file"; } | eval "$restore_cmd" 2>/tmp/mysql_restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "   ✅ [ETAPA 4/5] Restauração do '$database' concluída!"
            log "INFO" "      ⏱️  Fim da restauração: $(date '+%Y-%m-%d %H:%M:%S')"
            log "INFO" "      🕐 Duração da restauração: ${duration}s"
            return 0
        else
            log "ERROR" "   ❌ [ETAPA 4/5] Falha na restauração do '$database'"
            if [[ -f "/tmp/mysql_restore_error_${database}.log" ]]; then
                log "ERROR" "      📋 Erro detalhado: $(cat /tmp/mysql_restore_error_${database}.log)"
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
