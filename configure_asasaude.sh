#!/bin/bash

# =============================================================================
# CONFIGURAÇÃO ESPECÍFICA PARA DATABASE ASASAUDE - SISTEMA BACKUP MYSQL
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Função para aplicar configurações específicas do asasaude
configure_asasaude() {
    log "INFO" "🔧 Aplicando configurações específicas para database 'asasaude'"
    
    # Backup do arquivo .env original
    if [[ ! -f ".env.backup" ]]; then
        cp .env .env.backup
        log "SUCCESS" "✅ Backup do .env original criado"
    fi
    
    # Configurações específicas para asasaude (200GB)
    cat > .env.asasaude << 'EOF'
# =============================================================================
# CONFIGURAÇÃO ESPECÍFICA PARA ASASAUDE - DATABASE DE 200GB
# =============================================================================

# Servidor de origem (onde estão os dados para backup)
SOURCE_HOST=10.0.0.13
SOURCE_PORT=3306

# Servidor de destino (onde os backups serão restaurados)
DEST_HOST=127.0.0.1
DEST_PORT=2211

# Credenciais de acesso aos bancos de dados
DB_USERNAME=backup-bee
DB_PASSWORD=Bee@2025&ASA

# Database específico para backup
DATABASES=asasaude

# Agendamento do backup (formato cron) - 22:00 para evitar horário de pico
BACKUP_TIME=0 22 * * *

# Retenção estendida para databases grandes
RETENTION_DAYS=14

# Compressão obrigatória para economizar espaço
BACKUP_COMPRESSION=true

# Prefixo específico
BACKUP_PREFIX=asasaude_backup

# Opções otimizadas para databases grandes
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4 --quick --lock-tables=false --set-gtid-purged=OFF --column-statistics=0 --disable-keys --extended-insert=false

# Executar backup na inicialização (false para produção)
RUN_ON_START=false

# Timezone do sistema
TZ=America/Sao_Paulo

# Nível de log detalhado
LOG_LEVEL=INFO

# =============================================================================
# CONFIGURAÇÕES OTIMIZADAS PARA DATABASE DE 200GB
# =============================================================================

# Timeout de conexão estendido (5 minutos)
DB_TIMEOUT=300

# Timeouts de rede estendidos (2 horas cada)
NET_READ_TIMEOUT=7200
NET_WRITE_TIMEOUT=7200

# Pacote máximo de 1GB
MAX_ALLOWED_PACKET=1G

# Timeout do mysqldump: 8 horas
MYSQLDUMP_TIMEOUT=28800

# Sistema de retry robusto
MAX_RETRY_ATTEMPTS=5
RETRY_INTERVAL=60

# Logs detalhados habilitados
ENABLE_DEBUG_LOGS=true

# Verificação de integridade obrigatória
VERIFY_BACKUP_INTEGRITY=true

# Configurações específicas para databases grandes
LARGE_DB_MODE=true
USE_EXTENDED_INSERT=false
DISABLE_COLUMN_STATISTICS=true
USE_QUICK_MODE=true

# =============================================================================
# CONFIGURAÇÕES DE NOTIFICAÇÕES (RECOMENDADO PARA PRODUÇÃO)
# =============================================================================

# Ativar notificações por email
ENABLE_EMAIL_NOTIFICATIONS=true

# Configurações do email
EMAIL_FROM=backup-asasaude@asasolucoes.app.br
EMAIL_TO=ti@asasolucoes.app.br,administrador@asasolucoes.app.br
EMAIL_SUBJECT_PREFIX=[BACKUP-ASASAUDE-200GB]

# Configurações do servidor SMTP
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=ti@asasolucoes.app.br
SMTP_PASSWORD=Asatec@2025
SMTP_USE_TLS=true

# =============================================================================
# CONFIGURAÇÕES DE WEBHOOK (OPCIONAL)
# =============================================================================

# URL do webhook (Slack, Teams, Discord, etc.)
WEBHOOK_URL=

# Nome do webhook
WEBHOOK_USERNAME=Backup ASASAUDE 200GB System
EOF

    log "SUCCESS" "✅ Arquivo .env.asasaude criado com configurações otimizadas"
    
    # Copiar configurações para o .env principal
    cp .env.asasaude .env
    log "SUCCESS" "✅ Configurações aplicadas ao .env principal"
    
    log "INFO" "📋 Configurações aplicadas:"
    log "INFO" "   • Database: asasaude (200GB)"
    log "INFO" "   • Servidor origem: 10.0.0.13:3306"
    log "INFO" "   • Servidor destino: 127.0.0.1:2211"
    log "INFO" "   • Horário backup: 22:00 (evitar horário de pico)"
    log "INFO" "   • Timeout mysqldump: 8 horas"
    log "INFO" "   • Sistema retry: 5 tentativas"
    log "INFO" "   • Retenção: 14 dias"
    log "INFO" "   • Notificações: email habilitadas"
    log "INFO" "   • Otimizações: configuradas para DB grande"
}

# Função para testar configurações
test_asasaude_config() {
    log "INFO" "🧪 Testando configurações para asasaude..."
    
    # Carregar variáveis
    source .env
    
    # Testar conexão com servidor de origem
    log "INFO" "🔌 Testando conexão com servidor de origem..."
    if timeout 30 mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='asasaude';" 2>/dev/null | grep -q "asasaude"; then
        log "SUCCESS" "✅ Conexão com servidor de origem OK - database asasaude encontrado"
    else
        log "ERROR" "❌ Falha na conexão com servidor de origem ou database não encontrado"
        return 1
    fi
    
    # Testar conexão com servidor de destino
    log "INFO" "🎯 Testando conexão com servidor de destino..."
    if timeout 30 mysql -h"$DEST_HOST" -P"$DEST_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT 1;" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Conexão com servidor de destino OK"
    else
        log "WARNING" "⚠️  Falha na conexão com servidor de destino - backup continuará (somente local)"
    fi
    
    # Verificar espaço em disco
    log "INFO" "💾 Verificando espaço em disco..."
    local available_space=$(df /backups | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [[ $available_gb -ge 300 ]]; then
        log "SUCCESS" "✅ Espaço disponível: ${available_gb}GB (suficiente para backup de 200GB comprimido)"
    else
        log "WARNING" "⚠️  Espaço disponível: ${available_gb}GB (pode ser insuficiente)"
        log "WARNING" "   💡 Recomendado: pelo menos 300GB livres"
    fi
    
    # Obter tamanho atual do database
    log "INFO" "📊 Obtendo tamanho atual do database..."
    local current_size=$(mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024 / 1024, 2) AS 'DB Size in GB' 
            FROM information_schema.tables 
            WHERE table_schema='asasaude';" \
        --skip-column-names --batch 2>/dev/null || echo "0.0")
    
    log "INFO" "   📈 Tamanho atual: ${current_size} GB"
}

# Função para recomendar configurações adicionais do MySQL
recommend_mysql_config() {
    log "INFO" "💡 Recomendações de configuração para o servidor MySQL:"
    echo ""
    log "INFO" "   📝 Adicione ao my.cnf do servidor de origem:"
    echo "   [mysqld]"
    echo "   max_allowed_packet = 1G"
    echo "   net_read_timeout = 7200"
    echo "   net_write_timeout = 7200" 
    echo "   connect_timeout = 300"
    echo "   interactive_timeout = 28800"
    echo "   wait_timeout = 28800"
    echo "   innodb_lock_wait_timeout = 120"
    echo ""
    log "INFO" "   🔄 Após aplicar, reinicie o MySQL: systemctl restart mysql"
    echo ""
}

# Função para gerar comando de backup manual
generate_manual_command() {
    log "INFO" "🚀 Comandos para execução manual:"
    echo ""
    echo "# 1. Executar backup manual:"
    echo "docker-compose exec mariadb-backup /app/entrypoint.sh backup"
    echo ""
    echo "# 2. Monitorar backup em tempo real:"
    echo "docker-compose exec mariadb-backup /app/entrypoint.sh monitor asasaude"
    echo ""
    echo "# 3. Analisar database antes do backup:"
    echo "docker-compose exec mariadb-backup /app/entrypoint.sh optimize asasaude"
    echo ""
    echo "# 4. Ver logs em tempo real:"
    echo "docker-compose exec mariadb-backup tail -f /logs/backup.log"
    echo ""
}

# Função principal
main() {
    local action="${1:-configure}"
    
    case $action in
        "configure")
            log "INFO" "🚀 Configurando sistema para database asasaude..."
            configure_asasaude
            recommend_mysql_config
            generate_manual_command
            ;;
        "test")
            log "INFO" "🧪 Testando configurações..."
            test_asasaude_config
            ;;
        "restore")
            log "INFO" "🔄 Restaurando configuração original..."
            if [[ -f ".env.backup" ]]; then
                cp .env.backup .env
                log "SUCCESS" "✅ Configuração original restaurada"
            else
                log "ERROR" "❌ Backup original não encontrado"
                exit 1
            fi
            ;;
        *)
            log "ERROR" "❌ Ação inválida: $action"
            log "INFO" "Ações disponíveis: configure, test, restore"
            exit 1
            ;;
    esac
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
