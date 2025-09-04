#!/bin/bash

# =============================================================================
# SCRIPT DE VERIFICAÇÃO DA CONFIGURAÇÃO DE EMAIL
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função para logging colorido
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "SUCCESS")
            echo -e "[${timestamp}] ${GREEN}[✅ $level]${NC} $message"
            ;;
        "ERROR")
            echo -e "[${timestamp}] ${RED}[❌ $level]${NC} $message"
            ;;
        "WARNING")
            echo -e "[${timestamp}] ${YELLOW}[⚠️ $level]${NC} $message"
            ;;
        "INFO")
            echo -e "[${timestamp}] ${BLUE}[ℹ️ $level]${NC} $message"
            ;;
        *)
            echo -e "[${timestamp}] [$level] $message"
            ;;
    esac
}

echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}                    VERIFICAÇÃO DE CONFIGURAÇÃO DE EMAIL${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# Verificar variáveis de ambiente
log "INFO" "Verificando variáveis de ambiente..."

# Verificar se as variáveis principais estão definidas
required_vars=("EMAIL_FROM" "EMAIL_TO" "SMTP_SERVER" "SMTP_PORT" "SMTP_USERNAME" "SMTP_PASSWORD")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    log "ERROR" "Variáveis obrigatórias não definidas: ${missing_vars[*]}"
    exit 1
else
    log "SUCCESS" "Todas as variáveis obrigatórias estão definidas"
fi

# Mostrar configurações (mascarar senha)
echo ""
log "INFO" "Configurações atuais:"
echo "  EMAIL_FROM: $EMAIL_FROM"
echo "  EMAIL_TO: $EMAIL_TO"
echo "  SMTP_SERVER: $SMTP_SERVER"
echo "  SMTP_PORT: $SMTP_PORT"
echo "  SMTP_USERNAME: $SMTP_USERNAME"
echo "  SMTP_PASSWORD: ${SMTP_PASSWORD:0:4}****${SMTP_PASSWORD: -4}"
echo "  SMTP_USE_TLS: ${SMTP_USE_TLS:-true}"
echo ""

# Verificar se a senha parece ser uma senha de app do Google
if [[ ${#SMTP_PASSWORD} -ne 16 || "$SMTP_PASSWORD" =~ [^a-zA-Z] ]]; then
    log "WARNING" "A senha não parece ser uma senha de app do Google"
    echo "  - Senhas de app do Google têm exatamente 16 caracteres"
    echo "  - Contêm apenas letras (sem símbolos ou números)"
    echo "  - Você pode gerar uma em: https://myaccount.google.com"
else
    log "SUCCESS" "A senha parece ser uma senha de app válida"
fi

# Verificar conectividade com o servidor SMTP
log "INFO" "Testando conectividade com o servidor SMTP..."
if timeout 10 bash -c "</dev/tcp/${SMTP_SERVER}/${SMTP_PORT}"; then
    log "SUCCESS" "Conectividade com ${SMTP_SERVER}:${SMTP_PORT} OK"
else
    log "ERROR" "Não foi possível conectar com ${SMTP_SERVER}:${SMTP_PORT}"
    log "INFO" "Verifique se a porta ${SMTP_PORT} está aberta"
fi

# Verificar se o ssmtp está instalado
log "INFO" "Verificando instalação do SSMTP..."
if command -v ssmtp >/dev/null 2>&1; then
    log "SUCCESS" "SSMTP está instalado"
else
    log "ERROR" "SSMTP não está instalado"
fi

# Verificar permissões dos arquivos de configuração
log "INFO" "Verificando arquivos de configuração..."
if [[ -f "/config/ssmtp.conf" ]]; then
    log "SUCCESS" "Arquivo ssmtp.conf existe"
else
    log "WARNING" "Arquivo ssmtp.conf não existe (será criado automaticamente)"
fi

if [[ -f "/config/revaliases" ]]; then
    log "SUCCESS" "Arquivo revaliases existe"
else
    log "WARNING" "Arquivo revaliases não existe (será criado automaticamente)"
fi

# Verificar se o email está habilitado
if [[ "${ENABLE_EMAIL_NOTIFICATIONS:-false}" == "true" ]]; then
    log "SUCCESS" "Notificações por email estão habilitadas"
else
    log "WARNING" "Notificações por email estão desabilitadas"
    echo "  Para habilitar, defina: ENABLE_EMAIL_NOTIFICATIONS=true"
fi

echo ""
echo -e "${BLUE}==============================================================================${NC}"
log "INFO" "Verificação concluída!"

if [[ ${#missing_vars[@]} -eq 0 ]]; then
    echo ""
    log "INFO" "Para testar o envio de email, execute:"
    echo "  docker exec mariadb_backup_scheduler /scripts/send_email.sh test 'Teste de configuração'"
    echo ""
    log "INFO" "Para gerar uma senha de app do Google:"
    echo "  1. Acesse: https://myaccount.google.com"
    echo "  2. Vá em Segurança → Verificação em duas etapas"
    echo "  3. Clique em 'Senhas de app'"
    echo "  4. Gere uma nova senha para 'Mail' ou 'Outro'"
    echo "  5. Substitua SMTP_PASSWORD no arquivo .env"
fi

echo ""
