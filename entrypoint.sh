#!/bin/bash

# =============================================================================
# ENTRYPOINT SCRIPT - Sistema de Backup MariaDB/MySQL
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging com timestamp
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" | tee -a /logs/entrypoint.log
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" | tee -a /logs/entrypoint.log
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message" | tee -a /logs/entrypoint.log
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" | tee -a /logs/entrypoint.log
            ;;
        *)
            echo -e "[${timestamp}] $level $message" | tee -a /logs/entrypoint.log
            ;;
    esac
}

# Função de cleanup em caso de interrupção
cleanup() {
    log "INFO" "🧹 Limpando recursos e finalizando processos..."
    killall crond 2>/dev/null || true
    exit 0
}

# Configurar trap para cleanup
trap cleanup SIGTERM SIGINT

# Função para validar variáveis de ambiente obrigatórias
validate_environment() {
    log "INFO" "🔍 Validando variáveis de ambiente..."
    
    local required_vars=(
        "SOURCE_HOST"
        "SOURCE_PORT" 
        "DB_USERNAME"
        "DB_PASSWORD"
        "DATABASES"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "ERROR" "❌ Variáveis de ambiente obrigatórias não definidas:"
        for var in "${missing_vars[@]}"; do
            log "ERROR" "   - $var"
        done
        exit 1
    fi
    
    log "SUCCESS" "✅ Todas as variáveis obrigatórias estão definidas"
}

# Função para testar conectividade com os servidores
test_connectivity() {
    log "INFO" "🔗 Testando conectividade com servidores de banco de dados..."
    
    # Criar arquivo de configuração temporário para testes
    local mysql_config="/tmp/mysql_test_config.cnf"
    cat > "$mysql_config" << EOF
[client]
connect-timeout = ${DB_TIMEOUT:-30}
EOF
    
    # Teste servidor de origem
    log "INFO" "Testando conexão com servidor de origem: ${SOURCE_HOST}:${SOURCE_PORT}"
    if timeout ${DB_TIMEOUT:-30} mysql --defaults-extra-file="$mysql_config" ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Conexão com servidor de origem bem-sucedida"
    else
        log "ERROR" "❌ Falha na conexão com servidor de origem"
        log "WARNING" "⚠️  Continuando sem teste de conectividade - use backup manual para testar"
        rm -f "$mysql_config"
        return 1
    fi
    
    # Teste servidor de destino (somente se configurado)
    if [[ -n "${DEST_HOST}" && "${DEST_HOST}" != "" ]]; then
        log "INFO" "Testando conexão com servidor de destino: ${DEST_HOST}:${DEST_PORT}"
        if timeout ${DB_TIMEOUT:-30} mysql --defaults-extra-file="$mysql_config" ${MYSQL_CLIENT_OPTIONS} -h"$DEST_HOST" -P"$DEST_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            log "SUCCESS" "✅ Conexão com servidor de destino bem-sucedida"
        else
            log "ERROR" "❌ Falha na conexão com servidor de destino"
            rm -f "$mysql_config"
            exit 1
        fi
    else
        log "INFO" "ℹ️  DEST_HOST não configurado - modo somente backup"
    fi
    
    # Limpar arquivo de configuração temporário
    rm -f "$mysql_config"
}

# Função para configurar o cron
setup_cron() {
    log "INFO" "⏰ Configurando agendamento do cron..."
    
    # Criar arquivo de cron
    local cron_file="/tmp/backup_cron"
    
    # Configurar variáveis de ambiente no cron
    {
        echo "SHELL=/bin/bash"
        echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        echo ""
        echo "# Variáveis de ambiente para o backup"
        echo "SOURCE_HOST=${SOURCE_HOST}"
        echo "SOURCE_PORT=${SOURCE_PORT}"
        echo "DEST_HOST=${DEST_HOST}"
        echo "DEST_PORT=${DEST_PORT}"
        echo "DB_USERNAME=${DB_USERNAME}"
        echo "DB_PASSWORD=${DB_PASSWORD}"
        echo "DATABASES=${DATABASES}"
        echo "RETENTION_DAYS=${RETENTION_DAYS:-7}"
        echo "BACKUP_COMPRESSION=${BACKUP_COMPRESSION:-true}"
        echo "BACKUP_PREFIX=${BACKUP_PREFIX:-backup}"
        echo "MYSQLDUMP_OPTIONS=${MYSQLDUMP_OPTIONS}"
        echo "TZ=${TZ:-America/Sao_Paulo}"
        echo "ENABLE_EMAIL_NOTIFICATIONS=${ENABLE_EMAIL_NOTIFICATIONS:-false}"
        echo "EMAIL_FROM=${EMAIL_FROM}"
        echo "EMAIL_TO=${EMAIL_TO}"
        echo "SMTP_SERVER=${SMTP_SERVER}"
        echo "SMTP_PORT=${SMTP_PORT}"
        echo "WEBHOOK_URL=${WEBHOOK_URL}"
        echo ""
        echo "# Agendamento do backup"
        echo "${BACKUP_TIME:-0 2 * * *} /bee-backup.sh backup >> /logs/backup.log 2>&1"
    } > "$cron_file"
    
    # Instalar o cron
    crontab "$cron_file" 2>/dev/null || {
        # Se falhar, copiar para /etc/cron.d/
        log "INFO" "Configurando cron via /etc/cron.d/"
        echo "0 18 * * * backup /scripts/backup.sh >> /logs/backup.log 2>&1" > /etc/cron.d/backup-mysql
        chmod 0644 /etc/cron.d/backup-mysql
    }
    rm -f "$cron_file"
    
    log "SUCCESS" "✅ Cron configurado com sucesso"
    log "INFO" "📅 Agendamento: ${BACKUP_TIME:-0 2 * * *}"
}

# Função para inicializar diretórios
initialize_directories() {
    log "INFO" "📁 Inicializando diretórios..."
    
    # Criar diretórios se não existirem
    mkdir -p /backups /logs /config
    
    # Verificar permissões de escrita
    if [[ ! -w /backups ]]; then
        log "ERROR" "❌ Sem permissão de escrita em /backups"
        exit 1
    fi
    
    if [[ ! -w /logs ]]; then
        log "ERROR" "❌ Sem permissão de escrita em /logs"
        exit 1
    fi
    
    log "SUCCESS" "✅ Diretórios inicializados com sucesso"
}

# Função para exibir informações do sistema
show_system_info() {
    log "INFO" "ℹ️  Informações do sistema:"
    log "INFO" "   Container: $(hostname)"
    log "INFO" "   Usuário: $(whoami)"
    log "INFO" "   Timezone: ${TZ:-UTC}"
    log "INFO" "   Servidor origem: ${SOURCE_HOST}:${SOURCE_PORT}"
    if [[ -n "${DEST_HOST}" && "${DEST_HOST}" != "" ]]; then
        log "INFO" "   Servidor destino: ${DEST_HOST}:${DEST_PORT}"
        log "INFO" "   Modo: Backup + Restauração"
    else
        log "INFO" "   Servidor destino: Não configurado"
        log "INFO" "   Modo: Somente Backup"
    fi
    log "INFO" "   Databases: ${DATABASES}"
    log "INFO" "   Retenção: ${RETENTION_DAYS:-7} dias"
    log "INFO" "   Compressão: ${BACKUP_COMPRESSION:-true}"
}

# Função principal
main() {
    local mode="${1:-cron}"
    
    log "INFO" "🚀 Iniciando sistema de backup MariaDB/MySQL"
    log "INFO" "🔧 Modo de execução: $mode"
    
    # Inicializar sistema
    initialize_directories
    validate_environment
    show_system_info
    
    case "$mode" in
        "cron")
            log "INFO" "📋 Iniciando em modo agendado (cron)"
            if ! test_connectivity; then
                log "WARNING" "⚠️  Falha no teste de conectividade, mas continuando em modo cron"
            fi
            setup_cron
            
            # Executar backup inicial se configurado
            if [[ "${RUN_ON_START:-false}" == "true" ]]; then
                log "INFO" "🔄 Executando backup inicial..."
                /bee-backup.sh backup
            fi
            
            log "INFO" "⏰ Iniciando daemon cron..."
            
            # Iniciar o cron em background
            crond -f -d 0 &
            local cron_pid=$!
            
            log "SUCCESS" "✅ Daemon cron iniciado com PID $cron_pid"
            log "INFO" "📅 Próximo backup agendado para: ${BACKUP_TIME:-0 2 * * *}"
            
            # Loop principal para manter o container vivo
            while true; do
                if ! kill -0 $cron_pid 2>/dev/null; then
                    log "ERROR" "❌ Daemon cron parou! Reiniciando..."
                    crond -f -d 0 &
                    cron_pid=$!
                    log "SUCCESS" "✅ Daemon cron reiniciado com PID $cron_pid"
                fi
                sleep 30
            done
            ;;
        
        # Comandos simplificados - delegar para bee-backup.sh
        "backup"|"restore"|"list"|"test"|"clean")
            exec /bee-backup.sh "$@"
            ;;
            
        "shell")
            log "INFO" "🐚 Iniciando shell interativo"
            exec /bin/bash
            ;;
        
        "healthcheck")
            exec /scripts/healthcheck.sh
            ;;
            
        *)
            # Qualquer outro comando, tenta executar via bee-backup.sh
            exec /bee-backup.sh "$@"
            ;;
    esac
}

# Executar função principal com argumentos
main "$@"
