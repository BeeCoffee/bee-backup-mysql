#!/bin/bash

# =============================================================================
# SCRIPT DE ENVIO DE NOTIFICAÇÕES POR WEBHOOK
# =============================================================================

set -e

# Função para logging
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [$level] $message" >> /logs/webhook.log
}

# Função para enviar webhook
send_webhook() {
    local status=$1
    local message=$2
    
    # Verificar se webhook está configurado
    if [[ -z "$WEBHOOK_URL" ]]; then
        log "INFO" "Webhook não configurado, ignorando notificação"
        return 0
    fi
    
    # Definir cor baseada no status
    local color=""
    local emoji=""
    case "$status" in
        "success")
            color="good"
            emoji="✅"
            ;;
        "error")
            color="danger"
            emoji="❌"
            ;;
        "warning")
            color="warning"
            emoji="⚠️"
            ;;
        *)
            color="#36a64f"
            emoji="ℹ️"
            ;;
    esac
    
    # Obter informações do sistema
    local hostname=$(hostname)
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local webhook_username="${WEBHOOK_USERNAME:-Backup System}"
    
    # Obter estatísticas de backup
    local backup_count=$(find /backups -name "*.sql*" -type f -mtime -1 | wc -l 2>/dev/null || echo "0")
    local backup_size=$(du -sh /backups 2>/dev/null | cut -f1 || echo "N/A")
    
    # Criar payload para Slack/Discord/Teams
    local payload=$(cat << EOF
{
    "username": "$webhook_username",
    "icon_emoji": ":floppy_disk:",
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji Sistema de Backup MariaDB/MySQL",
            "text": "$message",
            "fields": [
                {
                    "title": "Servidor",
                    "value": "$hostname",
                    "short": true
                },
                {
                    "title": "Data/Hora",
                    "value": "$timestamp",
                    "short": true
                },
                {
                    "title": "Origem",
                    "value": "${SOURCE_HOST}:${SOURCE_PORT}",
                    "short": true
                },
                {
                    "title": "Destino",
                    "value": "${DEST_HOST}:${DEST_PORT}",
                    "short": true
                },
                {
                    "title": "Databases",
                    "value": "${DATABASES}",
                    "short": false
                },
                {
                    "title": "Backups (24h)",
                    "value": "$backup_count arquivos",
                    "short": true
                },
                {
                    "title": "Tamanho Total",
                    "value": "$backup_size",
                    "short": true
                }
            ],
            "footer": "Sistema de Backup Automatizado",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    # Criar payload alternativo para Discord
    local discord_payload=$(cat << EOF
{
    "username": "$webhook_username",
    "avatar_url": "https://cdn-icons-png.flaticon.com/512/2906/2906274.png",
    "embeds": [
        {
            "title": "$emoji Sistema de Backup MariaDB/MySQL",
            "description": "$message",
            "color": $(case "$status" in "success") echo "65280";; "error") echo "16711680";; "warning") echo "16776960";; *) echo "3447003";; esac),
            "fields": [
                {
                    "name": "🖥️ Servidor",
                    "value": "$hostname",
                    "inline": true
                },
                {
                    "name": "📅 Data/Hora",
                    "value": "$timestamp",
                    "inline": true
                },
                {
                    "name": "📤 Origem",
                    "value": "${SOURCE_HOST}:${SOURCE_PORT}",
                    "inline": true
                },
                {
                    "name": "📥 Destino",
                    "value": "${DEST_HOST}:${DEST_PORT}",
                    "inline": true
                },
                {
                    "name": "🗃️ Databases",
                    "value": "${DATABASES}",
                    "inline": false
                },
                {
                    "name": "📦 Backups (24h)",
                    "value": "$backup_count arquivos",
                    "inline": true
                },
                {
                    "name": "💾 Tamanho Total",
                    "value": "$backup_size",
                    "inline": true
                }
            ],
            "footer": {
                "text": "Sistema de Backup Automatizado"
            },
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
        }
    ]
}
EOF
)
    
    # Criar payload para Microsoft Teams
    local teams_payload=$(cat << EOF
{
    "@type": "MessageCard",
    "@context": "http://schema.org/extensions",
    "themeColor": "$(case "$status" in "success") echo "00FF00";; "error") echo "FF0000";; "warning") echo "FFFF00";; *) echo "0076D7";; esac)",
    "summary": "Notificação de Backup",
    "sections": [
        {
            "activityTitle": "$emoji Sistema de Backup MariaDB/MySQL",
            "activitySubtitle": "$hostname - $timestamp",
            "activityImage": "https://cdn-icons-png.flaticon.com/512/2906/2906274.png",
            "text": "$message",
            "facts": [
                {
                    "name": "Servidor:",
                    "value": "$hostname"
                },
                {
                    "name": "Origem:",
                    "value": "${SOURCE_HOST}:${SOURCE_PORT}"
                },
                {
                    "name": "Destino:",
                    "value": "${DEST_HOST}:${DEST_PORT}"
                },
                {
                    "name": "Databases:",
                    "value": "${DATABASES}"
                },
                {
                    "name": "Backups (24h):",
                    "value": "$backup_count arquivos"
                },
                {
                    "name": "Tamanho Total:",
                    "value": "$backup_size"
                }
            ]
        }
    ]
}
EOF
)
    
    # Detectar tipo de webhook baseado na URL
    local selected_payload="$payload"
    if [[ "$WEBHOOK_URL" == *"discord"* ]]; then
        selected_payload="$discord_payload"
        log "INFO" "Detectado webhook do Discord"
    elif [[ "$WEBHOOK_URL" == *"outlook"* ]] || [[ "$WEBHOOK_URL" == *"teams"* ]]; then
        selected_payload="$teams_payload"
        log "INFO" "Detectado webhook do Microsoft Teams"
    else
        log "INFO" "Usando formato Slack/genérico"
    fi
    
    # Enviar webhook
    log "INFO" "Enviando notificação via webhook..."
    
    local response=$(curl -s -w "%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$selected_payload" \
        --connect-timeout 10 \
        --max-time 30 \
        "$WEBHOOK_URL" 2>>/logs/webhook.log)
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        log "SUCCESS" "Webhook enviado com sucesso (HTTP $http_code)"
        return 0
    else
        log "ERROR" "Falha no envio do webhook (HTTP $http_code)"
        log "ERROR" "Resposta: $response_body"
        return 1
    fi
}

# Função para testar webhook
test_webhook() {
    log "INFO" "Testando configuração do webhook..."
    
    if [[ -z "$WEBHOOK_URL" ]]; then
        log "ERROR" "WEBHOOK_URL não configurado"
        return 1
    fi
    
    send_webhook "info" "🧪 Teste de conectividade do webhook - Sistema funcionando corretamente!"
}

# Executar função baseada nos argumentos
case "${1:-send}" in
    "test")
        test_webhook
        ;;
    "send")
        send_webhook "${2:-info}" "${3:-Notificação do sistema de backup}"
        ;;
    *)
        echo "Uso: $0 {send|test} [status] [message]"
        echo "Status: success, error, warning, info"
        exit 1
        ;;
esac
