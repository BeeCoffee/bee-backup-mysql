#!/bin/bash

# =============================================================================
# SCRIPT DE HEALTHCHECK DO SISTEMA DE BACKUP
# =============================================================================

set -e

# Códigos de retorno
HEALTHY=0
UNHEALTHY=1

# Função para logging (simplificada para healthcheck)
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [$level] $message" 2>&1
}

# Função para verificar se o processo de agendamento está rodando
check_scheduler_process() {
    log "INFO" "Verificando processo de agendamento..."
    
    if pgrep -f "entrypoint.sh" > /dev/null; then
        log "SUCCESS" "✅ Processo de agendamento está rodando"
        return 0
    else
        log "ERROR" "❌ Processo de agendamento não está rodando"
        return 1
    fi
}

# Função para verificar conectividade com os servidores de banco
check_database_connectivity() {
    log "INFO" "Verificando conectividade com servidores de banco..."
    
    local errors=0
    
    # Verificar servidor de origem
    if [[ -n "$SOURCE_HOST" && -n "$SOURCE_PORT" && -n "$DB_USERNAME" && -n "$DB_PASSWORD" ]]; then
        if timeout 10 mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            log "SUCCESS" "✅ Conectividade com servidor de origem OK"
        else
            log "ERROR" "❌ Falha na conectividade com servidor de origem"
            ((errors++))
        fi
    else
        log "WARNING" "⚠️  Variáveis de ambiente para servidor de origem não definidas"
        ((errors++))
    fi
    
    # Verificar servidor de destino
    if [[ -n "$DEST_HOST" && -n "$DEST_PORT" && -n "$DB_USERNAME" && -n "$DB_PASSWORD" ]]; then
        if timeout 10 mysql -h"$DEST_HOST" -P"$DEST_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            log "SUCCESS" "✅ Conectividade com servidor de destino OK"
        else
            log "ERROR" "❌ Falha na conectividade com servidor de destino"
            ((errors++))
        fi
    else
        log "WARNING" "⚠️  Variáveis de ambiente para servidor de destino não definidas"
        ((errors++))
    fi
    
    return $errors
}

# Função para verificar permissões de escrita nos diretórios
check_directory_permissions() {
    log "INFO" "Verificando permissões de diretórios..."
    
    local errors=0
    
    # Verificar diretório de backups
    if [[ -d "/backups" ]]; then
        if [[ -w "/backups" ]]; then
            log "SUCCESS" "✅ Permissão de escrita em /backups OK"
        else
            log "ERROR" "❌ Sem permissão de escrita em /backups"
            ((errors++))
        fi
    else
        log "ERROR" "❌ Diretório /backups não existe"
        ((errors++))
    fi
    
    # Verificar diretório de logs
    if [[ -d "/logs" ]]; then
        if [[ -w "/logs" ]]; then
            log "SUCCESS" "✅ Permissão de escrita em /logs OK"
        else
            log "ERROR" "❌ Sem permissão de escrita em /logs"
            ((errors++))
        fi
    else
        log "ERROR" "❌ Diretório /logs não existe"
        ((errors++))
    fi
    
    return $errors
}

# Função para verificar erros recentes nos logs
check_recent_errors() {
    log "INFO" "Verificando erros recentes nos logs..."
    
    local error_count=0
    local log_files=(
        "/logs/backup.log"
        "/logs/entrypoint.log"
    )
    
    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            # Verificar erros nas últimas 24 horas
            local recent_errors=$(grep -c "\[ERROR\]" "$log_file" 2>/dev/null | tail -100 || echo "0")
            
            if [[ $recent_errors -gt 0 ]]; then
                log "WARNING" "⚠️  Encontrados $recent_errors erros recentes em $(basename "$log_file")"
                ((error_count++))
            else
                log "SUCCESS" "✅ Nenhum erro recente em $(basename "$log_file")"
            fi
        else
            log "WARNING" "⚠️  Arquivo de log não encontrado: $log_file"
        fi
    done
    
    return $error_count
}

# Função para verificar espaço em disco
check_disk_space() {
    log "INFO" "Verificando espaço em disco..."
    
    local errors=0
    
    # Verificar espaço no diretório de backups
    local backup_usage=$(df /backups | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $backup_usage -gt 90 ]]; then
        log "ERROR" "❌ Espaço em disco crítico em /backups: ${backup_usage}%"
        ((errors++))
    elif [[ $backup_usage -gt 80 ]]; then
        log "WARNING" "⚠️  Espaço em disco baixo em /backups: ${backup_usage}%"
    else
        log "SUCCESS" "✅ Espaço em disco em /backups OK: ${backup_usage}%"
    fi
    
    # Verificar espaço no diretório de logs
    local log_usage=$(df /logs | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $log_usage -gt 90 ]]; then
        log "ERROR" "❌ Espaço em disco crítico em /logs: ${log_usage}%"
        ((errors++))
    elif [[ $log_usage -gt 80 ]]; then
        log "WARNING" "⚠️  Espaço em disco baixo em /logs: ${log_usage}%"
    else
        log "SUCCESS" "✅ Espaço em disco em /logs OK: ${log_usage}%"
    fi
    
    return $errors
}

# Função para verificar último backup
check_last_backup() {
    log "INFO" "Verificando último backup..."
    
    if [[ -d "/backups" ]]; then
        local last_backup=$(find /backups -name "*.sql*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        
        if [[ -n "$last_backup" ]]; then
            local backup_age=$(stat -c %Y "$last_backup" 2>/dev/null || echo "0")
            local current_time=$(date +%s)
            local age_hours=$(( (current_time - backup_age) / 3600 ))
            
            if [[ $age_hours -le 25 ]]; then  # Considerando backup diário
                log "SUCCESS" "✅ Último backup realizado há $age_hours horas"
                return 0
            else
                log "WARNING" "⚠️  Último backup realizado há $age_hours horas (pode estar atrasado)"
                return 1
            fi
        else
            log "WARNING" "⚠️  Nenhum backup encontrado"
            return 1
        fi
    else
        log "ERROR" "❌ Diretório de backups não existe"
        return 1
    fi
}

# Função para verificar configuração do agendamento
check_scheduler_configuration() {
    log "INFO" "Verificando configuração do agendamento..."
    
    if [[ -n "${BACKUP_TIME}" ]]; then
        log "SUCCESS" "✅ Configuração do agendamento OK (${BACKUP_TIME})"
        return 0
    else
        log "WARNING" "⚠️  BACKUP_TIME não está configurado"
        return 1
    fi
}

# Função para gerar estatísticas do sistema
show_system_stats() {
    log "INFO" "=========================================="
    log "INFO" "📊 ESTATÍSTICAS DO SISTEMA"
    log "INFO" "=========================================="
    
    # Informações básicas
    log "INFO" "🖥️  Hostname: $(hostname)"
    log "INFO" "👤 Usuário: ${DB_USERNAME}"
    log "INFO" "⏰ Uptime: $(uptime | cut -d',' -f1)"
    log "INFO" "🕐 Timezone: ${TZ:-UTC}"
    
    # Estatísticas de backup
    if [[ -d "/backups" ]]; then
        local backup_count=$(find /backups -name "*.sql*" -type f | wc -l)
        local backup_size=$(du -sh /backups 2>/dev/null | cut -f1 || echo "N/A")
        log "INFO" "📦 Total de backups: $backup_count arquivos"
        log "INFO" "💾 Tamanho total: $backup_size"
    fi
    
    # Últimos logs
    if [[ -f "/logs/backup.log" ]]; then
        local last_backup_log=$(tail -1 /logs/backup.log 2>/dev/null || echo "Nenhum log encontrado")
        log "INFO" "📝 Último log: $last_backup_log"
    fi
    
    log "INFO" "=========================================="
}

# Função principal do healthcheck
main() {
    local overall_status=0
    
    log "INFO" "🔍 Iniciando healthcheck do sistema de backup..."
    
    # Verificação essencial: processo de agendamento
    if ! check_scheduler_process; then
        overall_status=1
    fi
    
    # Verificação essencial: permissões de diretório
    if ! check_directory_permissions; then
        overall_status=1
    fi
    
    # Verificações adicionais (não críticas para healthcheck)
    check_disk_space || true
    check_recent_errors || true
    check_last_backup || true
    check_scheduler_configuration || true
    
    # Verificar conectividade apenas se as variáveis estiverem definidas
    if [[ -n "$SOURCE_HOST" && -n "$DEST_HOST" ]]; then
        if ! check_database_connectivity; then
            overall_status=1
        fi
    else
        log "WARNING" "⚠️  Pulando teste de conectividade (variáveis não definidas)"
    fi
    
    # Resultado final
    if [[ $overall_status -eq 0 ]]; then
        log "SUCCESS" "✅ HEALTHCHECK PASSOU - Sistema saudável"
    else
        log "ERROR" "❌ HEALTHCHECK FALHOU - Sistema com problemas"
    fi
    
    exit $overall_status
}

# Executar healthcheck
main "$@"
