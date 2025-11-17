#!/bin/bash

# =============================================================================
# BEE BACKUP - Interface Principal Simplificada
# =============================================================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Função de log
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" ;;
        "WARNING") echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message" ;;
        "ERROR") echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" ;;
    esac
}

# Função de ajuda
show_help() {
    cat << 'EOF'
🐝 BEE BACKUP - Sistema Simplificado de Backup MySQL/MariaDB

COMANDOS PRINCIPAIS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  backup                Faz backup dos bancos definidos no .env
  backup full           Faz backup de TODOS os bancos (exceto sistema)
  backup restore        Faz backup E restaura no servidor destino
  
  restore               Restaura bancos definidos no .env
  restore full          Restaura TODOS os backups disponíveis
  restore <arquivo>     Restaura um backup específico
  
  list                  Lista todos os backups disponíveis
  test                  Testa conectividade com os servidores
  clean                 Remove backups antigos (baseado em RETENTION_DAYS)

EXEMPLOS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # Fazer backup dos bancos do .env
  ./bee-backup.sh backup

  # Fazer backup de todos os bancos do servidor
  ./bee-backup.sh backup full

  # Fazer backup e restaurar automaticamente
  ./bee-backup.sh backup restore

  # Restaurar um backup específico
  ./bee-backup.sh restore /backups/backup_meudb_20251117.sql.gz

  # Ver todos os backups
  ./bee-backup.sh list

CONFIGURAÇÃO:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Edite o arquivo .env com suas configurações:
  
  SOURCE_HOST=seu_servidor_origem
  DATABASES=db1,db2,db3
  DEST_HOST=seu_servidor_destino  (opcional)

  Se DEST_HOST não for configurado, apenas faz backup.
  Se DEST_HOST estiver configurado, pode usar 'backup restore'.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
}

# Função para obter todos os databases do servidor
get_all_databases() {
    local host=$1
    local port=$2
    
    log "INFO" "🔍 Obtendo lista de databases do servidor ${host}:${port}..."
    
    # Obter lista excluindo databases do sistema
    local databases=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$host" -P"$port" \
        -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN \
        -e "SELECT schema_name FROM information_schema.schemata 
            WHERE schema_name NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');" \
        2>/dev/null)
    
    if [[ -z "$databases" ]]; then
        log "ERROR" "❌ Nenhum database encontrado ou erro na conexão"
        return 1
    fi
    
    # Converter para formato de vírgula
    echo "$databases" | tr '\n' ',' | sed 's/,$//'
}

# Função principal de backup
do_backup() {
    local mode=$1  # normal, full, ou restore
    
    log "INFO" "🐝 Iniciando processo de backup..."
    
    if [[ "$mode" == "full" ]]; then
        log "INFO" "📦 Modo: BACKUP COMPLETO (todos os bancos)"
        
        # Obter todos os databases
        local all_dbs=$(get_all_databases "$SOURCE_HOST" "$SOURCE_PORT")
        
        if [[ -z "$all_dbs" ]]; then
            log "ERROR" "❌ Não foi possível obter lista de databases"
            return 1
        fi
        
        log "SUCCESS" "✅ Databases encontrados: $all_dbs"
        export DATABASES="$all_dbs"
    elif [[ "$mode" == "restore" ]]; then
        log "INFO" "🔄 Modo: BACKUP + RESTAURAÇÃO"
        
        if [[ -z "${DEST_HOST}" ]]; then
            log "ERROR" "❌ DEST_HOST não configurado no .env"
            log "ERROR" "   Configure DEST_HOST para usar 'backup restore'"
            return 1
        fi
    else
        log "INFO" "💾 Modo: BACKUP (databases do .env)"
    fi
    
    # Executar script de backup
    /scripts/backup.sh
}

# Função principal de restore
do_restore() {
    local mode=$1
    
    if [[ "$mode" == "full" ]]; then
        log "INFO" "🔄 Modo: RESTAURAÇÃO COMPLETA"
        log "INFO" "📋 Restaurando todos os backups disponíveis..."
        
        # Obter lista de backups
        local backup_files=($(find /backups -name "*.sql*" -type f | sort -r))
        
        if [[ ${#backup_files[@]} -eq 0 ]]; then
            log "ERROR" "❌ Nenhum backup encontrado em /backups"
            return 1
        fi
        
        log "SUCCESS" "✅ Encontrados ${#backup_files[@]} backups"
        
        # Restaurar cada backup
        local count=0
        for backup_file in "${backup_files[@]}"; do
            ((count++))
            
            # Extrair nome do database do arquivo
            local filename=$(basename "$backup_file")
            local db_name=""
            
            if [[ "$filename" =~ ^backup_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
                db_name="${BASH_REMATCH[1]}"
            elif [[ "$filename" =~ ^backup_large_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
                db_name="${BASH_REMATCH[1]}"
            fi
            
            if [[ -n "$db_name" ]]; then
                log "INFO" "📦 [$count/${#backup_files[@]}] Restaurando: $db_name"
                /scripts/restore_backup.sh "$backup_file" "$db_name" dest
            else
                log "WARNING" "⚠️  Não foi possível identificar database de: $filename"
            fi
        done
        
        log "SUCCESS" "🎉 Restauração completa finalizada!"
        
    elif [[ -f "$mode" ]]; then
        # Arquivo específico fornecido
        log "INFO" "🔄 Restaurando backup específico: $mode"
        
        # Extrair nome do database
        local filename=$(basename "$mode")
        local db_name=""
        
        if [[ "$filename" =~ ^backup_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
            db_name="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^backup_large_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
            db_name="${BASH_REMATCH[1]}"
        else
            log "ERROR" "❌ Não foi possível identificar database do arquivo"
            log "ERROR" "   Use: ./bee-backup.sh restore <arquivo> <database_name>"
            return 1
        fi
        
        log "INFO" "📋 Database identificado: $db_name"
        /scripts/restore_backup.sh "$mode" "$db_name" dest
        
    else
        # Restaurar databases do .env
        log "INFO" "🔄 Modo: RESTAURAÇÃO (databases do .env)"
        
        if [[ -z "$DATABASES" ]]; then
            log "ERROR" "❌ DATABASES não configurado no .env"
            return 1
        fi
        
        # Processar cada database
        IFS=',' read -ra DB_ARRAY <<< "$DATABASES"
        
        for db in "${DB_ARRAY[@]}"; do
            db=$(echo "$db" | xargs)  # Trim
            
            log "INFO" "🔍 Procurando backup mais recente de: $db"
            
            # Encontrar backup mais recente
            local latest_backup=$(find /backups -name "backup*${db}*.sql*" -type f | sort -r | head -1)
            
            if [[ -z "$latest_backup" ]]; then
                log "WARNING" "⚠️  Nenhum backup encontrado para: $db"
                continue
            fi
            
            log "SUCCESS" "✅ Backup encontrado: $(basename "$latest_backup")"
            /scripts/restore_backup.sh "$latest_backup" "$db" dest
        done
    fi
}

# Função para listar backups
list_backups() {
    /scripts/list_backups.sh
}

# Função para limpar backups antigos
clean_backups() {
    log "INFO" "🧹 Limpando backups antigos (>${RETENTION_DAYS:-7} dias)..."
    
    local deleted_count=0
    
    while IFS= read -r -d '' file; do
        local filename=$(basename "$file")
        local filesize=$(stat -c%s "$file" 2>/dev/null || echo "0")
        local filesize_mb=$(echo "scale=1; $filesize / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
        
        rm "$file"
        ((deleted_count++))
        log "INFO" "   🗑️  Removido: $filename (${filesize_mb} MB)"
    done < <(find /backups -name "*.sql*" -type f -mtime +${RETENTION_DAYS:-7} -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "SUCCESS" "✅ ${deleted_count} backups antigos removidos"
    else
        log "INFO" "ℹ️  Nenhum backup antigo encontrado"
    fi
}

# Função para testar conectividade
test_connectivity() {
    log "INFO" "🧪 Testando conectividade..."
    
    # Testar origem
    log "INFO" "📡 Testando servidor origem: ${SOURCE_HOST}:${SOURCE_PORT}"
    if timeout 10 mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" \
        -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
        log "SUCCESS" "✅ Origem conectado com sucesso"
    else
        log "ERROR" "❌ Falha na conexão com origem"
        return 1
    fi
    
    # Testar destino se configurado
    if [[ -n "${DEST_HOST}" ]]; then
        log "INFO" "📡 Testando servidor destino: ${DEST_HOST}:${DEST_PORT}"
        if timeout 10 mysql ${MYSQL_CLIENT_OPTIONS} -h"$DEST_HOST" -P"$DEST_PORT" \
            -u"$DB_USERNAME" -p"$DB_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1; then
            log "SUCCESS" "✅ Destino conectado com sucesso"
        else
            log "ERROR" "❌ Falha na conexão com destino"
            return 1
        fi
    else
        log "INFO" "ℹ️  DEST_HOST não configurado (apenas backup)"
    fi
    
    log "SUCCESS" "🎉 Todos os testes passaram!"
}

# Função principal
main() {
    local command=${1:-}
    local arg2=${2:-}
    
    # Banner
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔══════════════════════════════════════════╗
    ║     🐝 BEE BACKUP - MySQL/MariaDB       ║
    ║         Sistema Simplificado             ║
    ╚══════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    case "$command" in
        "backup")
            case "$arg2" in
                "full") do_backup "full" ;;
                "restore") do_backup "restore" ;;
                *) do_backup "normal" ;;
            esac
            ;;
        
        "restore")
            do_restore "$arg2"
            ;;
        
        "list")
            list_backups
            ;;
        
        "clean")
            clean_backups
            ;;
        
        "test")
            test_connectivity
            ;;
        
        "help"|"--help"|"-h"|"")
            show_help
            ;;
        
        *)
            log "ERROR" "❌ Comando inválido: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Executar
main "$@"

