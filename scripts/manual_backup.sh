#!/bin/bash

# =============================================================================
# SCRIPT DE BACKUP MANUAL PARA DATABASES ESPECÍFICOS
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

# Função para exibir ajuda
show_help() {
    cat << EOF
📋 BACKUP MANUAL DE DATABASES MARIADB/MYSQL

🎯 Uso:
    $0 [database1] [database2] [database3] ...
    $0 --all                    # Backup de todos os databases configurados
    $0 --list                   # Listar databases disponíveis
    $0 --help                   # Exibir esta ajuda

📝 Exemplos:
    $0 loja_online financeiro                    # Backup de databases específicos
    $0 --all                                     # Backup de todos os databases do .env
    $0 loja_online                               # Backup de um único database

ℹ️  Informações:
    • Os databases devem existir no servidor de origem
    • Os backups serão salvos em /backups com timestamp
    • Compressão será aplicada se habilitada no .env
    • Logs detalhados serão salvos em /logs/manual_backup.log

🔧 Configuração atual:
    • Servidor origem: ${SOURCE_HOST:-'não configurado'}:${SOURCE_PORT:-'não configurado'}
    • Servidor destino: ${DEST_HOST:-'não configurado'}:${DEST_PORT:-'não configurado'}
    • Databases configurados: ${DATABASES:-'não configurado'}
    • Compressão: ${BACKUP_COMPRESSION:-'não configurado'}
    • Retenção: ${RETENTION_DAYS:-'não configurado'} dias
EOF
}

# Função para listar databases disponíveis
list_databases() {
    log "INFO" "📋 Listando databases disponíveis no servidor de origem..."
    
    # Verificar conectividade
    if ! mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR" "❌ Falha na conexão com servidor de origem"
        exit 1
    fi
    
    log "INFO" "🔗 Conectado ao servidor: ${SOURCE_HOST}:${SOURCE_PORT}"
    log "INFO" ""
    log "INFO" "📊 DATABASES DISPONÍVEIS:"
    log "INFO" "=========================="
    
    # Obter lista de databases
    local databases=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SHOW DATABASES;" --skip-column-names --batch 2>/dev/null | \
        grep -vE '^(information_schema|performance_schema|mysql|sys)$' || true)
    
    if [[ -n "$databases" ]]; then
        local count=0
        while IFS= read -r db; do
            if [[ -n "$db" ]]; then
                ((count++))
                
                # Obter tamanho do database
                local size=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
                    -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 1) AS 'DB Size in MB' 
                        FROM information_schema.tables 
                        WHERE table_schema='$db';" \
                    --skip-column-names --batch 2>/dev/null || echo "0.0")
                
                # Verificar se está nos databases configurados
                local status=""
                if [[ "${DATABASES}" == *"$db"* ]]; then
                    status="${GREEN}[CONFIGURADO]${NC}"
                else
                    status="${YELLOW}[DISPONÍVEL]${NC}"
                fi
                
                printf "   %2d. %-25s %10s MB   %s\n" "$count" "$db" "$size" "$status"
            fi
        done <<< "$databases"
        
        log "INFO" ""
        log "INFO" "📈 Total: $count databases encontrados"
        log "INFO" ""
        log "INFO" "💡 Dica: Use '$0 nome_database' para fazer backup específico"
    else
        log "WARNING" "⚠️  Nenhum database encontrado"
    fi
}

# Função para validar argumentos
validate_arguments() {
    if [[ $# -eq 0 ]]; then
        log "ERROR" "❌ Nenhum database especificado"
        echo ""
        show_help
        exit 1
    fi
    
    # Verificar argumentos especiais
    case "$1" in
        "--help"|"-h")
            show_help
            exit 0
            ;;
        "--list"|"-l")
            list_databases
            exit 0
            ;;
        "--all"|"-a")
            if [[ -z "$DATABASES" ]]; then
                log "ERROR" "❌ Variável DATABASES não configurada no .env"
                exit 1
            fi
            return 0
            ;;
    esac
    
    # Validar variáveis de ambiente obrigatórias
    local required_vars=(
        "SOURCE_HOST"
        "SOURCE_PORT"
        "DEST_HOST" 
        "DEST_PORT"
        "DB_USERNAME"
        "DB_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log "ERROR" "❌ Variável de ambiente obrigatória não definida: $var"
            exit 1
        fi
    done
}

# Função para verificar se databases existem
validate_databases() {
    local databases=("$@")
    local invalid_databases=()
    
    log "INFO" "🔍 Validando databases especificados..."
    
    for db in "${databases[@]}"; do
        if [[ -n "$db" ]]; then
            log "INFO" "   Verificando '$db'..."
            
            if mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
                -e "USE $db;" >/dev/null 2>&1; then
                log "SUCCESS" "   ✅ '$db' existe e está acessível"
            else
                log "ERROR" "   ❌ '$db' não existe ou não está acessível"
                invalid_databases+=("$db")
            fi
        fi
    done
    
    if [[ ${#invalid_databases[@]} -gt 0 ]]; then
        log "ERROR" "❌ Databases inválidos encontrados:"
        for db in "${invalid_databases[@]}"; do
            log "ERROR" "   - $db"
        done
        log "INFO" ""
        log "INFO" "💡 Use '$0 --list' para ver databases disponíveis"
        exit 1
    fi
    
    log "SUCCESS" "✅ Todos os databases são válidos"
}

# Função principal
main() {
    # Redirecionar logs para arquivo
    exec > >(tee -a /logs/manual_backup.log)
    exec 2>&1
    
    log "INFO" "🚀 INICIANDO BACKUP MANUAL"
    log "INFO" "=========================="
    log "INFO" "📅 Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "👤 Usuário: ${DB_USERNAME}"
    log "INFO" "🖥️  Container: $(hostname)"
    
    # Validar argumentos
    validate_arguments "$@"
    
    # Preparar lista de databases
    local databases_to_backup=()
    
    if [[ "$1" == "--all" ]]; then
        log "INFO" "🔄 Modo: Backup de todos os databases configurados"
        IFS=',' read -ra databases_to_backup <<< "${DATABASES}"
        
        # Remover espaços em branco
        for i in "${!databases_to_backup[@]}"; do
            databases_to_backup[$i]=$(echo "${databases_to_backup[$i]}" | xargs)
        done
    else
        log "INFO" "🎯 Modo: Backup de databases específicos"
        databases_to_backup=("$@")
    fi
    
    # Mostrar informações dos databases selecionados
    log "INFO" "📋 Databases selecionados para backup:"
    for db in "${databases_to_backup[@]}"; do
        if [[ -n "$db" ]]; then
            log "INFO" "   - $db"
        fi
    done
    
    log "INFO" "🔧 Configurações:"
    log "INFO" "   Origem: ${SOURCE_HOST}:${SOURCE_PORT}"
    log "INFO" "   Destino: ${DEST_HOST}:${DEST_PORT}"
    log "INFO" "   Compressão: ${BACKUP_COMPRESSION:-true}"
    log "INFO" "   Prefixo: ${BACKUP_PREFIX:-backup}"
    
    # Validar databases
    validate_databases "${databases_to_backup[@]}"
    
    log "INFO" "=========================================="
    
    # Exportar databases selecionados para o script de backup
    export DATABASES=$(IFS=','; echo "${databases_to_backup[*]}")
    
    # Executar script de backup principal
    log "INFO" "🔄 Executando processo de backup..."
    
    if /scripts/backup.sh; then
        log "SUCCESS" "🎉 BACKUP MANUAL CONCLUÍDO COM SUCESSO!"
        exit 0
    else
        log "ERROR" "❌ BACKUP MANUAL FALHOU!"
        exit 1
    fi
}

# Executar apenas se script foi chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
