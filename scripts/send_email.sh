#!/bin/bash

# =============================================================================
# SCRIPT DE ENVIO DE NOTIFICAÇÕES POR EMAIL
# =============================================================================

set -e

# Função para logging
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [$level] $message" >> /logs/email.log
}

# Função para configurar ssmtp
configure_ssmtp() {
    log "INFO" "Configurando SSMTP para envio de emails..."
    
    # Criar configuração do ssmtp
    cat > /config/ssmtp.conf << EOF
# Configuração automática do SSMTP
root=${EMAIL_FROM}
mailhub=${SMTP_SERVER}:${SMTP_PORT}
hostname=$(hostname)
AuthUser=${SMTP_USERNAME:-$EMAIL_FROM}
AuthPass=${SMTP_PASSWORD}
UseSTARTTLS=Yes
UseTLS=No
FromLineOverride=YES
AuthMethod=LOGIN
TLS_CA_File=/etc/ssl/certs/ca-certificates.crt
EOF
    
    # Criar aliases
    echo "root:${EMAIL_TO}" > /config/revaliases
    
    log "SUCCESS" "SSMTP configurado com sucesso"
}

# Função para enviar email
send_email() {
    local status=$1
    local message=$2
    local subject_prefix="${EMAIL_SUBJECT_PREFIX:-[BACKUP-MYSQL]}"
    
    # Verificar se email está habilitado
    if [[ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" != "true" ]]; then
        log "INFO" "Notificações por email desabilitadas"
        return 0
    fi
    
    # Verificar variáveis obrigatórias
    if [[ -z "$EMAIL_FROM" || -z "$EMAIL_TO" || -z "$SMTP_SERVER" ]]; then
        log "ERROR" "Configurações de email incompletas"
        return 1
    fi
    
    # Configurar SSMTP
    configure_ssmtp
    
    # Definir assunto baseado no status
    local subject=""
    local icon=""
    case "$status" in
        "success")
            subject="$subject_prefix ✅ Backup Concluído com Sucesso"
            icon="✅"
            ;;
        "error")
            subject="$subject_prefix ❌ Falha no Backup"
            icon="❌"
            ;;
        "warning")
            subject="$subject_prefix ⚠️ Backup com Avisos"
            icon="⚠️"
            ;;
        *)
            subject="$subject_prefix ℹ️ Notificação de Backup"
            icon="ℹ️"
            ;;
    esac
    
    # Obter informações do sistema
    local hostname=$(hostname)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime=$(uptime | cut -d',' -f1)
    
    # Obter estatísticas de backup
    local backup_count=$(find /backups -name "*.sql*" -type f -mtime -1 | wc -l)
    local backup_size=$(du -sh /backups 2>/dev/null | cut -f1 || echo "N/A")
    
    # Criar corpo do email
    local email_body=$(cat << EOF
Subject: $subject
To: $EMAIL_TO
From: $EMAIL_FROM
MIME-Version: 1.0
Content-Type: text/html; charset=UTF-8

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { background-color: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { background-color: #2c3e50; color: white; padding: 15px; border-radius: 5px; margin-bottom: 20px; }
        .status-success { background-color: #27ae60; }
        .status-error { background-color: #e74c3c; }
        .status-warning { background-color: #f39c12; }
        .info-table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        .info-table th, .info-table td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        .info-table th { background-color: #f8f9fa; font-weight: bold; }
        .footer { margin-top: 20px; font-size: 12px; color: #666; }
        .message-box { background-color: #f8f9fa; padding: 15px; border-left: 4px solid #007bff; margin: 15px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header status-${status}">
            <h2>$icon Sistema de Backup MariaDB/MySQL</h2>
            <p>Notificação do servidor: $hostname</p>
        </div>
        
        <div class="message-box">
            <h3>Detalhes da Operação:</h3>
            <p>$message</p>
        </div>
        
        <table class="info-table">
            <tr>
                <th>Informação</th>
                <th>Valor</th>
            </tr>
            <tr>
                <td>Data/Hora</td>
                <td>$timestamp</td>
            </tr>
            <tr>
                <td>Servidor</td>
                <td>$hostname</td>
            </tr>
            <tr>
                <td>Uptime</td>
                <td>$uptime</td>
            </tr>
            <tr>
                <td>Servidor Origem</td>
                <td>${SOURCE_HOST}:${SOURCE_PORT}</td>
            </tr>
            <tr>
                <td>Servidor Destino</td>
                <td>${DEST_HOST}:${DEST_PORT}</td>
            </tr>
            <tr>
                <td>Databases</td>
                <td>${DATABASES}</td>
            </tr>
            <tr>
                <td>Backups (24h)</td>
                <td>$backup_count arquivos</td>
            </tr>
            <tr>
                <td>Tamanho Total</td>
                <td>$backup_size</td>
            </tr>
            <tr>
                <td>Retenção</td>
                <td>${RETENTION_DAYS:-7} dias</td>
            </tr>
        </table>
        
        <div class="footer">
            <p>Este email foi enviado automaticamente pelo sistema de backup.</p>
            <p>Para ver os logs completos, acesse: docker exec -it mariadb_backup_scheduler tail -f /logs/backup.log</p>
        </div>
    </div>
</body>
</html>
EOF
)
    
    # Enviar email
    log "INFO" "Enviando notificação por email para: $EMAIL_TO"
    
    if echo "$email_body" | ssmtp -C/config/ssmtp.conf -v "$EMAIL_TO" 2>>/logs/email.log; then
        log "SUCCESS" "Email enviado com sucesso"
        return 0
    else
        log "ERROR" "Falha no envio do email"
        return 1
    fi
}

# Executar função principal
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    send_email "${1:-info}" "${2:-Notificação do sistema de backup}"
fi
