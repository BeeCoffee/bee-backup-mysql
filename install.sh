#!/bin/bash

# =============================================================================
# SCRIPT DE INSTALAÇÃO RÁPIDA - BACKUP BEE
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# Banner
echo -e "${BLUE}"
cat << 'EOF'
 ____             _                   ____            
|  _ \           | |                 |  _ \           
| |_) | __ _  ___| | ___   _ _ __     | |_) | ___  ___ 
|  _ < / _` |/ __| |/ / | | | '_ \    |  _ < / _ \/ _ \
| |_) | (_| | (__|   <| |_| | |_) |   | |_) |  __/  __/
|____/ \__,_|\___|_|\_\\__,_| .__/    |____/ \___|\___|
                            | |                       
                            |_|                       
EOF
echo -e "${NC}"

log "INFO" "🐝 Instalação do Sistema de Backup MariaDB/MySQL"
log "INFO" "================================================"

# Verificar se Docker está instalado
if ! command -v docker >/dev/null 2>&1; then
    log "ERROR" "Docker não está instalado. Instale o Docker primeiro."
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    log "ERROR" "Docker Compose não está instalado. Instale o Docker Compose primeiro."
    exit 1
fi

log "SUCCESS" "✅ Docker e Docker Compose encontrados"

# Verificar se já existe instalação
if [[ -f ".env" ]]; then
    log "WARNING" "⚠️  Arquivo .env já existe"
    read -p "Deseja sobrescrever? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        log "INFO" "Instalação cancelada"
        exit 0
    fi
fi

# Criar diretórios necessários
log "INFO" "📁 Criando diretórios..."
mkdir -p backups logs config

# Copiar arquivo de configuração
log "INFO" "📝 Criando arquivo de configuração..."
if [[ -f ".env.example" ]]; then
    cp .env.example .env
    log "SUCCESS" "✅ Arquivo .env criado a partir do exemplo"
else
    log "ERROR" "❌ Arquivo .env.example não encontrado"
    exit 1
fi

# Configuração interativa
log "INFO" "🔧 Configuração interativa"
log "INFO" "=========================="

echo ""
read -p "🖥️  Servidor de origem (IP/hostname): " SOURCE_HOST
read -p "🔌 Porta do servidor de origem [3306]: " SOURCE_PORT
SOURCE_PORT=${SOURCE_PORT:-3306}

read -p "🎯 Servidor de destino (IP/hostname): " DEST_HOST
read -p "🔌 Porta do servidor de destino [3306]: " DEST_PORT
DEST_PORT=${DEST_PORT:-3306}

read -p "👤 Usuário do banco de dados: " DB_USERNAME
read -s -p "🔐 Senha do banco de dados: " DB_PASSWORD
echo ""

read -p "🗃️  Databases para backup (separados por vírgula): " DATABASES

read -p "⏰ Horário do backup (formato cron) [0 2 * * *]: " BACKUP_TIME
BACKUP_TIME=${BACKUP_TIME:-"0 2 * * *"}

read -p "🗓️  Dias de retenção [7]: " RETENTION_DAYS
RETENTION_DAYS=${RETENTION_DAYS:-7}

# Aplicar configurações no .env
log "INFO" "📝 Aplicando configurações..."

sed -i "s/SOURCE_HOST=.*/SOURCE_HOST=$SOURCE_HOST/" .env
sed -i "s/SOURCE_PORT=.*/SOURCE_PORT=$SOURCE_PORT/" .env
sed -i "s/DEST_HOST=.*/DEST_HOST=$DEST_HOST/" .env
sed -i "s/DEST_PORT=.*/DEST_PORT=$DEST_PORT/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
sed -i "s/DATABASES=.*/DATABASES=$DATABASES/" .env
sed -i "s|BACKUP_TIME=.*|BACKUP_TIME=$BACKUP_TIME|" .env
sed -i "s/RETENTION_DAYS=.*/RETENTION_DAYS=$RETENTION_DAYS/" .env

log "SUCCESS" "✅ Configurações aplicadas"

# Configurações opcionais
echo ""
read -p "📧 Deseja configurar notificações por email? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    read -p "   Email de origem: " EMAIL_FROM
    read -p "   Email de destino: " EMAIL_TO
    read -p "   Servidor SMTP: " SMTP_SERVER
    read -p "   Porta SMTP [587]: " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-587}
    
    sed -i "s/ENABLE_EMAIL_NOTIFICATIONS=.*/ENABLE_EMAIL_NOTIFICATIONS=true/" .env
    sed -i "s/EMAIL_FROM=.*/EMAIL_FROM=$EMAIL_FROM/" .env
    sed -i "s/EMAIL_TO=.*/EMAIL_TO=$EMAIL_TO/" .env
    sed -i "s/SMTP_SERVER=.*/SMTP_SERVER=$SMTP_SERVER/" .env
    sed -i "s/SMTP_PORT=.*/SMTP_PORT=$SMTP_PORT/" .env
    
    log "SUCCESS" "✅ Notificações por email configuradas"
fi

echo ""
read -p "🌐 Deseja configurar webhook (Slack/Discord/Teams)? (s/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Ss]$ ]]; then
    read -p "   URL do webhook: " WEBHOOK_URL
    
    sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=$WEBHOOK_URL|" .env
    
    log "SUCCESS" "✅ Webhook configurado"
fi

# Build da imagem
log "INFO" "🔨 Construindo imagem Docker..."
if docker-compose build; then
    log "SUCCESS" "✅ Imagem construída com sucesso"
else
    log "ERROR" "❌ Falha na construção da imagem"
    exit 1
fi

# Teste de conectividade
log "INFO" "🔗 Testando conectividade..."
if docker-compose run --rm mariadb-backup test; then
    log "SUCCESS" "✅ Teste de conectividade passou"
else
    log "ERROR" "❌ Falha no teste de conectividade"
    log "WARNING" "⚠️  Verifique as configurações de banco de dados"
    exit 1
fi

# Iniciar sistema
echo ""
read -p "🚀 Deseja iniciar o sistema agora? (S/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    log "INFO" "🚀 Iniciando sistema..."
    
    if docker-compose up -d; then
        log "SUCCESS" "✅ Sistema iniciado com sucesso!"
        
        echo ""
        log "INFO" "🎉 INSTALAÇÃO CONCLUÍDA!"
        log "INFO" "======================="
        log "INFO" "📋 Comandos úteis:"
        log "INFO" "   Ver logs: docker-compose logs -f"
        log "INFO" "   Status: docker-compose ps"
        log "INFO" "   Parar: docker-compose down"
        log "INFO" "   Backup manual: docker exec mariadb_backup_scheduler /scripts/manual_backup.sh --all"
        log "INFO" "   Listar backups: docker exec mariadb_backup_scheduler /scripts/list_backups.sh"
        echo ""
        log "INFO" "📁 Diretórios:"
        log "INFO" "   Backups: ./backups/"
        log "INFO" "   Logs: ./logs/"
        log "INFO" "   Config: ./config/"
        echo ""
        log "SUCCESS" "🐝 Backup Bee está pronto para trabalhar! 🍯"
    else
        log "ERROR" "❌ Falha ao iniciar o sistema"
        exit 1
    fi
else
    log "INFO" "Sistema não foi iniciado"
    log "INFO" "Para iniciar manualmente: docker-compose up -d"
fi
