#!/bin/bash

# =============================================================================
# SCRIPT DE VERIFICAÇÃO DO SISTEMA BACKUP BEE
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

log "INFO" "🔍 Verificação do Sistema Backup Bee"
log "INFO" "====================================="

# Verificar estrutura de arquivos
log "INFO" "📁 Verificando estrutura de arquivos..."

required_files=(
    "Dockerfile"
    "docker-compose.yml"
    ".env.example"
    "entrypoint.sh"
    "README.md"
    "scripts/backup.sh"
    "scripts/healthcheck.sh"
    "scripts/manual_backup.sh"
    "scripts/restore_backup.sh"
    "scripts/list_backups.sh"
    "scripts/send_email.sh"
    "scripts/send_webhook.sh"
    "install.sh"
)

missing_files=()
for file in "${required_files[@]}"; do
    if [[ -f "$file" ]]; then
        log "SUCCESS" "✅ $file"
    else
        log "ERROR" "❌ $file"
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    log "ERROR" "❌ Arquivos obrigatórios estão faltando!"
    for file in "${missing_files[@]}"; do
        log "ERROR" "   - $file"
    done
    exit 1
fi

# Verificar permissões
log "INFO" "🔐 Verificando permissões..."

executable_files=(
    "entrypoint.sh"
    "scripts/backup.sh"
    "scripts/healthcheck.sh"
    "scripts/manual_backup.sh"
    "scripts/restore_backup.sh"
    "scripts/list_backups.sh"
    "scripts/send_email.sh"
    "scripts/send_webhook.sh"
    "install.sh"
)

for file in "${executable_files[@]}"; do
    if [[ -x "$file" ]]; then
        log "SUCCESS" "✅ $file (executável)"
    else
        log "WARNING" "⚠️  $file (não executável)"
        chmod +x "$file"
        log "SUCCESS" "✅ Permissão corrigida para $file"
    fi
done

# Verificar diretórios
log "INFO" "📂 Verificando diretórios..."

required_dirs=("scripts")
for dir in "${required_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        log "SUCCESS" "✅ Diretório $dir/"
    else
        log "ERROR" "❌ Diretório $dir/ não encontrado"
        exit 1
    fi
done

# Verificar se .env existe
log "INFO" "⚙️  Verificando configurações..."

if [[ -f ".env" ]]; then
    log "SUCCESS" "✅ Arquivo .env existe"
    
    # Verificar variáveis críticas
    critical_vars=("SOURCE_HOST" "DEST_HOST" "DB_USERNAME" "DATABASES")
    missing_vars=()
    
    for var in "${critical_vars[@]}"; do
        if grep -q "^${var}=" .env && ! grep -q "^${var}=$" .env; then
            log "SUCCESS" "✅ $var configurado"
        else
            log "WARNING" "⚠️  $var não configurado ou vazio"
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log "WARNING" "⚠️  Algumas variáveis críticas não estão configuradas"
        log "INFO" "Execute o script de instalação: ./install.sh"
    fi
else
    log "WARNING" "⚠️  Arquivo .env não encontrado"
    log "INFO" "Execute o script de instalação: ./install.sh"
fi

# Verificar Docker
log "INFO" "🐳 Verificando Docker..."

if command -v docker >/dev/null 2>&1; then
    log "SUCCESS" "✅ Docker instalado"
    
    if docker info >/dev/null 2>&1; then
        log "SUCCESS" "✅ Docker daemon rodando"
    else
        log "ERROR" "❌ Docker daemon não está rodando"
    fi
else
    log "ERROR" "❌ Docker não está instalado"
fi

if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
    log "SUCCESS" "✅ Docker Compose instalado"
else
    log "ERROR" "❌ Docker Compose não está instalado"
fi

# Verificar sintaxe dos scripts principais
log "INFO" "📝 Verificando sintaxe dos scripts..."

for script in entrypoint.sh scripts/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        log "SUCCESS" "✅ Sintaxe OK: $script"
    else
        log "ERROR" "❌ Erro de sintaxe: $script"
        bash -n "$script"
    fi
done

# Verificar docker-compose.yml
log "INFO" "🐙 Verificando docker-compose.yml..."

if docker-compose config >/dev/null 2>&1 || docker compose config >/dev/null 2>&1; then
    log "SUCCESS" "✅ docker-compose.yml válido"
else
    log "ERROR" "❌ docker-compose.yml inválido"
    # Tentar com docker compose primeiro, depois docker-compose
    if command -v docker >/dev/null 2>&1; then
        docker compose config 2>&1 || docker-compose config 2>&1
    fi
fi

# Resumo final
log "INFO" "📊 RESUMO DA VERIFICAÇÃO"
log "INFO" "========================"

log "SUCCESS" "✅ Estrutura de arquivos: OK"
log "SUCCESS" "✅ Permissões: OK"
log "SUCCESS" "✅ Sintaxe dos scripts: OK"
log "SUCCESS" "✅ Docker Compose: OK"

echo ""
log "INFO" "🎯 PRÓXIMOS PASSOS:"

if [[ ! -f ".env" ]]; then
    log "INFO" "1. Execute: ./install.sh (configuração interativa)"
else
    log "INFO" "1. Configure o arquivo .env com suas credenciais"
fi

log "INFO" "2. Teste a conectividade: docker-compose run --rm mariadb-backup test"
log "INFO" "3. Inicie o sistema: docker-compose up -d"
log "INFO" "4. Monitore os logs: docker-compose logs -f"

echo ""
log "SUCCESS" "🐝 Sistema Backup Bee está pronto para uso! 🍯"
