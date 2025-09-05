#!/bin/bash

# =============================================================================
# SCRIPT DE RESTAURAÇÃO DE BACKUP MARIADB/MYSQL
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
🔄 RESTAURAÇÃO DE BACKUP MARIADB/MYSQL

🎯 Uso:
    $0 <arquivo_backup> <nome_database> [servidor]
    $0 --list                                        # Listar backups disponíveis
    $0 --help                                        # Exibir esta ajuda

📋 Parâmetros:
    arquivo_backup   Caminho para o arquivo de backup (.sql ou .sql.gz)
    nome_database    Nome do database de destino
    servidor         'source' (origem) ou 'dest' (destino) - padrão: dest

📝 Exemplos:
    $0 /backups/backup_loja_20240903.sql.gz loja_online
    $0 /backups/backup_loja_20240903.sql.gz loja_online dest
    $0 /backups/backup_loja_20240903.sql.gz loja_online source
    $0 --list

ℹ️  Informações:
    • Suporta arquivos .sql e .sql.gz
    • Cria o database se não existir
    • Faz backup de segurança antes da restauração
    • Logs detalhados em /logs/restore.log

⚠️  ATENÇÃO:
    A restauração irá SOBRESCREVER os dados existentes no database!
    Um backup de segurança será criado automaticamente.

🔧 Configuração atual:
    • Servidor origem: ${SOURCE_HOST:-'não configurado'}:${SOURCE_PORT:-'não configurado'}
    • Servidor destino: ${DEST_HOST:-'não configurado'}:${DEST_PORT:-'não configurado'}
EOF
}

# Função para listar backups disponíveis
list_backups() {
    log "INFO" "📋 Listando backups disponíveis..."
    
    if [[ ! -d "/backups" ]]; then
        log "ERROR" "❌ Diretório de backups não encontrado: /backups"
        exit 1
    fi
    
    log "INFO" ""
    log "INFO" "📊 BACKUPS DISPONÍVEIS:"
    log "INFO" "======================="
    
    local backup_files=($(find /backups -name "*.sql*" -type f | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "WARNING" "⚠️  Nenhum backup encontrado em /backups"
        return 0
    fi
    
    local count=0
    for file in "${backup_files[@]}"; do
        ((count++))
        
        local filename=$(basename "$file")
        local filesize=$(stat -c%s "$file" 2>/dev/null || echo "0")
        local filesize_mb=$(echo "scale=1; $filesize / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
        local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        
        # Extrair nome do database do arquivo
        local db_name=""
        if [[ "$filename" =~ ^backup_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
            db_name="${BASH_REMATCH[1]}"
        elif [[ "$filename" =~ ^(.+)_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
            db_name="${BASH_REMATCH[2]}"
        fi
        
        printf "   %2d. %-40s %10s MB   %s   [%s]\n" \
            "$count" "$filename" "$filesize_mb" "$file_date" "${db_name:-unknown}"
    done
    
    log "INFO" ""
    log "INFO" "📈 Total: $count backups encontrados"
    log "INFO" ""
    log "INFO" "💡 Uso: $0 /backups/nome_do_arquivo.sql.gz nome_database"
}

# Função para validar argumentos
validate_arguments() {
    case "${1:-}" in
        "--help"|"-h")
            show_help
            exit 0
            ;;
        "--list"|"-l")
            list_backups
            exit 0
            ;;
        "")
            log "ERROR" "❌ Arquivo de backup não especificado"
            echo ""
            show_help
            exit 1
            ;;
    esac
    
    if [[ -z "${2:-}" ]]; then
        log "ERROR" "❌ Nome do database não especificado"
        echo ""
        show_help
        exit 1
    fi
    
    # Validar variáveis de ambiente
    local required_vars=("SOURCE_HOST" "SOURCE_PORT" "DEST_HOST" "DEST_PORT" "DB_USERNAME" "DB_PASSWORD")
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log "ERROR" "❌ Variável de ambiente obrigatória não definida: $var"
            exit 1
        fi
    done
}

# Função para validar arquivo de backup
validate_backup_file() {
    local backup_file="$1"
    
    log "INFO" "🔍 Validando arquivo de backup..."
    
    # Verificar se arquivo existe
    if [[ ! -f "$backup_file" ]]; then
        log "ERROR" "❌ Arquivo de backup não encontrado: $backup_file"
        exit 1
    fi
    
    # Verificar se arquivo não está vazio
    if [[ ! -s "$backup_file" ]]; then
        log "ERROR" "❌ Arquivo de backup está vazio: $backup_file"
        exit 1
    fi
    
    # Verificar extensão do arquivo
    if [[ ! "$backup_file" =~ \.(sql|sql\.gz)$ ]]; then
        log "ERROR" "❌ Formato de arquivo não suportado. Use .sql ou .sql.gz"
        exit 1
    fi
    
    # Verificar integridade se for arquivo comprimido
    if [[ "$backup_file" == *.gz ]]; then
        log "INFO" "   Verificando integridade do arquivo comprimido..."
        if ! gzip -t "$backup_file" 2>/dev/null; then
            log "ERROR" "❌ Arquivo comprimido corrompido"
            exit 1
        fi
        log "SUCCESS" "   ✅ Arquivo comprimido íntegro"
    fi
    
    # Verificar conteúdo básico do SQL
    local sql_content=""
    if [[ "$backup_file" == *.gz ]]; then
        sql_content=$(zcat "$backup_file" | head -20)
    else
        sql_content=$(head -20 "$backup_file")
    fi
    
    if echo "$sql_content" | grep -q "CREATE DATABASE\|USE \`\|DROP DATABASE\|INSERT INTO"; then
        log "SUCCESS" "✅ Conteúdo SQL válido detectado"
    else
        log "WARNING" "⚠️  Conteúdo SQL pode estar incompleto"
    fi
    
    # Mostrar informações do arquivo
    local filesize=$(stat -c%s "$backup_file")
    local filesize_mb=$(echo "scale=1; $filesize / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
    local file_date=$(stat -c %y "$backup_file" | cut -d'.' -f1)
    
    log "INFO" "📄 Informações do arquivo:"
    log "INFO" "   Nome: $(basename "$backup_file")"
    log "INFO" "   Tamanho: ${filesize_mb} MB"
    log "INFO" "   Data: $file_date"
}

# Função para criar backup de segurança
create_safety_backup() {
    local database="$1"
    local host="$2"
    local port="$3"
    
    log "INFO" "💾 Criando backup de segurança do database '$database'..."
    
    # Verificar se database existe
    if ! mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "USE $database;" >/dev/null 2>&1; then
        log "WARNING" "⚠️  Database '$database' não existe no servidor, não é necessário backup de segurança"
        return 0
    fi
    
    local backup_file="/backups/safety_backup_${database}_$(date '+%Y%m%d_%H%M%S').sql"
    
    # Executar backup de segurança
    local dump_cmd="mysqldump -h'$host' -P'$port' -u'$DB_USERNAME' -p'$DB_PASSWORD'"
    if [[ -n "${MYSQLDUMP_OPTIONS}" ]]; then
        dump_cmd="$dump_cmd ${MYSQLDUMP_OPTIONS}"
    fi
    dump_cmd="$dump_cmd '$database'"
    
    if eval "$dump_cmd" > "$backup_file" 2>/dev/null; then
        # Comprimir backup de segurança
        if gzip "$backup_file" 2>/dev/null; then
            backup_file="${backup_file}.gz"
        fi
        
        local filesize=$(stat -c%s "$backup_file")
        local filesize_mb=$(echo "scale=1; $filesize / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
        
        log "SUCCESS" "✅ Backup de segurança criado: $(basename "$backup_file") (${filesize_mb} MB)"
        return 0
    else
        log "ERROR" "❌ Falha ao criar backup de segurança"
        return 1
    fi
}

# Função para restaurar backup
restore_backup() {
    local backup_file="$1"
    local database="$2"
    local server="${3:-dest}"
    
    # Definir servidor de destino
    local host port
    if [[ "$server" == "source" ]]; then
        host="$SOURCE_HOST"
        port="$SOURCE_PORT"
        log "INFO" "🎯 Servidor de destino: ORIGEM (${host}:${port})"
    else
        host="$DEST_HOST"
        port="$DEST_PORT"
        log "INFO" "🎯 Servidor de destino: DESTINO (${host}:${port})"
    fi
    
    # Testar conectividade
    log "INFO" "🔗 Testando conectividade com servidor..."
    if ! timeout 10 mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR" "❌ Falha na conexão com servidor: ${host}:${port}"
        exit 1
    fi
    log "SUCCESS" "✅ Conectividade confirmada"
    
    # Criar backup de segurança
    create_safety_backup "$database" "$host" "$port"
    
    # Criar database se não existir
    log "INFO" "🗃️  Criando database '$database' se não existir..."
    if mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "CREATE DATABASE IF NOT EXISTS \`$database\`;" 2>/dev/null; then
        log "SUCCESS" "✅ Database '$database' pronto"
    else
        log "ERROR" "❌ Falha ao criar database '$database'"
        exit 1
    fi
    
    # Executar restauração
    log "INFO" "🔄 Iniciando restauração..."
    log "WARNING" "⚠️  ATENÇÃO: Os dados existentes serão sobrescritos!"
    
    local start_time=$(date +%s)
    local restore_cmd="mysql -h'$host' -P'$port' -u'$DB_USERNAME' -p'$DB_PASSWORD' '$database'"
    
    # Executar restauração baseada no tipo de arquivo
    if [[ "$backup_file" == *.gz ]]; then
        log "INFO" "   Restaurando arquivo comprimido..."
        if zcat "$backup_file" | eval "$restore_cmd" 2>/tmp/restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "✅ Restauração concluída em ${duration} segundos"
        else
            log "ERROR" "❌ Falha na restauração"
            if [[ -f "/tmp/restore_error_${database}.log" ]]; then
                log "ERROR" "   Erro: $(cat /tmp/restore_error_${database}.log)"
            fi
            exit 1
        fi
    else
        log "INFO" "   Restaurando arquivo SQL..."
        if eval "$restore_cmd" < "$backup_file" 2>/tmp/restore_error_${database}.log; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            log "SUCCESS" "✅ Restauração concluída em ${duration} segundos"
        else
            log "ERROR" "❌ Falha na restauração"
            if [[ -f "/tmp/restore_error_${database}.log" ]]; then
                log "ERROR" "   Erro: $(cat /tmp/restore_error_${database}.log)"
            fi
            exit 1
        fi
    fi
    
    # Verificar se restauração foi bem-sucedida
    log "INFO" "🔍 Verificando integridade da restauração..."
    local table_count=$(mysql -h"$host" -P"$port" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$database';" \
        --skip-column-names --batch 2>/dev/null || echo "0")
    
    if [[ $table_count -gt 0 ]]; then
        log "SUCCESS" "✅ Restauração verificada: $table_count tabelas encontradas"
    else
        log "WARNING" "⚠️  Nenhuma tabela encontrada após restauração"
    fi
}

# Função principal
main() {
    # Redirecionar logs para arquivo
    exec > >(tee -a /logs/restore.log)
    exec 2>&1
    
    log "INFO" "🔄 INICIANDO RESTAURAÇÃO DE BACKUP"
    log "INFO" "=================================="
    log "INFO" "📅 Data/Hora: $(date '+%Y-%m-%d %H:%M:%S')"
    log "INFO" "👤 Usuário: ${DB_USERNAME}"
    log "INFO" "🖥️  Container: $(hostname)"
    
    # Validar argumentos
    validate_arguments "$@"
    
    local backup_file="$1"
    local database="$2"
    local server="${3:-dest}"
    
    log "INFO" "📋 Parâmetros da restauração:"
    log "INFO" "   Arquivo: $backup_file"
    log "INFO" "   Database: $database"
    log "INFO" "   Servidor: $server"
    
    # Validar arquivo de backup
    validate_backup_file "$backup_file"
    
    log "INFO" "=================================="
    
    # Confirmar operação
    echo ""
    echo -e "${YELLOW}⚠️  ATENÇÃO: Esta operação irá sobrescrever os dados existentes!${NC}"
    echo -e "${YELLOW}   Um backup de segurança será criado automaticamente.${NC}"
    echo ""
    
    # Em modo interativo, pedir confirmação
    if [[ -t 0 ]]; then
        read -p "Continuar com a restauração? (s/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            log "INFO" "❌ Restauração cancelada pelo usuário"
            exit 0
        fi
    fi
    
    # Executar restauração
    restore_backup "$backup_file" "$database" "$server"
    
    log "SUCCESS" "🎉 RESTAURAÇÃO CONCLUÍDA COM SUCESSO!"
    log "INFO" "=================================="
}

# Executar apenas se script foi chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
