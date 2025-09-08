#!/bin/bash

# =============================================================================
# BACKUP POR CHUNKS - SOLUÇÃO PARA TABELAS GIGANTES
# Integração com o sistema Bee-Backup
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variáveis globais
SCRIPT_START_TIME=$(date +%s)
BACKUP_DATE=$(date '+%Y%m%d_%H%M%S')

# Função para logging com timestamp
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} $message" | tee -a /logs/backup.log
            ;;
        "SUCCESS")
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} $message" | tee -a /logs/backup.log
            ;;
        "WARNING")
            echo -e "${YELLOW}[${timestamp}] [WARNING]${NC} $message" | tee -a /logs/backup.log
            ;;
        "ERROR")
            echo -e "${RED}[${timestamp}] [ERROR]${NC} $message" | tee -a /logs/backup.log
            ;;
    esac
}

# Função para backup por chunks de tabela específica
backup_table_chunks() {
    local database=$1
    local table=$2
    local chunk_size=${3:-100000}  # Default: 100k registros por chunk
    
    log "INFO" "🔧 Iniciando backup por CHUNKS da tabela '$table'"
    log "INFO" "   📦 Tamanho do chunk: $chunk_size registros"
    
    # Arquivo de saída
    local output_file="/backups/${BACKUP_PREFIX:-backup}_${database}_${table}_chunks_${BACKUP_DATE}.sql"
    local temp_dir="/tmp/chunks_${BACKUP_DATE}"
    
    # Criar diretório temporário
    mkdir -p "$temp_dir"
    
    # Obter total de registros
    log "INFO" "   📊 Contando registros na tabela '$table'..."
    local total_rows=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
        "SELECT COUNT(*) FROM $database.$table;" 2>/dev/null || echo "0")
    
    if [[ "$total_rows" == "0" ]]; then
        log "ERROR" "❌ Não foi possível contar registros ou tabela está vazia"
        return 1
    fi
    
    log "INFO" "   📈 Total de registros: $total_rows"
    
    # Calcular número de chunks
    local total_chunks=$(( ($total_rows + $chunk_size - 1) / $chunk_size ))
    log "INFO" "   📦 Total de chunks necessários: $total_chunks"
    
    # Criar header do arquivo SQL
    log "INFO" "   📝 Criando estrutura do arquivo de backup..."
    cat > "$output_file" << EOF
-- Backup por chunks da tabela $table
-- Database: $database  
-- Total de registros: $total_rows
-- Chunks: $total_chunks chunks de $chunk_size registros
-- Data: $(date)
-- Gerado por: Bee-Backup System

SET FOREIGN_KEY_CHECKS=0;
SET UNIQUE_CHECKS=0;
SET AUTOCOMMIT=0;

USE \`$database\`;

EOF

    # Adicionar estrutura da tabela (DDL)
    log "INFO" "   🏗️ Exportando estrutura da tabela..."
    mysqldump ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
        --no-data \
        --single-transaction \
        --routines \
        --triggers \
        "$database" "$table" >> "$output_file" 2>/dev/null
    
    if [[ $? -ne 0 ]]; then
        log "ERROR" "❌ Falha ao exportar estrutura da tabela"
        return 1
    fi
    
    log "SUCCESS" "   ✅ Estrutura da tabela exportada"
    
    # Determinar coluna de ordenação (geralmente 'id' ou primeira coluna)
    local order_column=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
        "SELECT COLUMN_NAME FROM information_schema.COLUMNS 
         WHERE TABLE_SCHEMA='$database' AND TABLE_NAME='$table' 
         ORDER BY ORDINAL_POSITION LIMIT 1;" 2>/dev/null || echo "id")
    
    log "INFO" "   🔑 Usando coluna de ordenação: '$order_column'"
    
    # Processar chunks
    local successful_chunks=0
    local failed_chunks=0
    
    for (( chunk=0; chunk<$total_chunks; chunk++ )); do
        local offset=$(( $chunk * $chunk_size ))
        local chunk_num=$(( $chunk + 1 ))
        
        log "INFO" "   📦 Processando chunk $chunk_num/$total_chunks (offset: $offset)"
        
        # Tentar backup do chunk específico
        local chunk_file="$temp_dir/chunk_${chunk_num}.sql"
        local retry_count=0
        local max_retries=3
        local chunk_success=false
        
        while [[ $retry_count -lt $max_retries ]] && [[ "$chunk_success" == false ]]; do
            retry_count=$((retry_count + 1))
            
            if [[ $retry_count -gt 1 ]]; then
                log "WARNING" "     ⚠️ Tentativa $retry_count/$max_retries para chunk $chunk_num"
                sleep 10  # Pausa antes do retry
            fi
            
            # Comando mysqldump para o chunk específico
            timeout 3600 mysqldump ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
                --no-create-info \
                --single-transaction \
                --quick \
                --lock-tables=false \
                --extended-insert=false \
                --disable-keys \
                --where="1=1 ORDER BY $order_column LIMIT $chunk_size OFFSET $offset" \
                "$database" "$table" > "$chunk_file" 2>/dev/null
            
            if [[ $? -eq 0 ]] && [[ -s "$chunk_file" ]]; then
                chunk_success=true
                ((successful_chunks++))
                
                # Adicionar chunk ao arquivo principal
                cat "$chunk_file" >> "$output_file"
                rm "$chunk_file"
                
                log "SUCCESS" "     ✅ Chunk $chunk_num concluído"
            else
                log "WARNING" "     ⚠️ Chunk $chunk_num falhou (tentativa $retry_count)"
                rm -f "$chunk_file"
            fi
        done
        
        if [[ "$chunk_success" == false ]]; then
            log "ERROR" "     ❌ Chunk $chunk_num falhou após $max_retries tentativas"
            ((failed_chunks++))
        fi
        
        # Pequena pausa para não sobrecarregar o servidor
        sleep 2
        
        # Atualizar progresso
        local progress=$(( (chunk_num * 100) / total_chunks ))
        log "INFO" "     📈 Progresso: $progress% ($chunk_num/$total_chunks chunks)"
    done
    
    # Footer do arquivo SQL
    cat >> "$output_file" << EOF

COMMIT;
SET FOREIGN_KEY_CHECKS=1;
SET UNIQUE_CHECKS=1;
SET AUTOCOMMIT=1;

-- Backup por chunks concluído: $(date)
-- Chunks bem-sucedidos: $successful_chunks/$total_chunks
-- Chunks falharam: $failed_chunks/$total_chunks
EOF

    # Limpar diretório temporário
    rm -rf "$temp_dir"
    
    # Verificar resultado final
    if [[ $failed_chunks -eq 0 ]]; then
        log "SUCCESS" "🎉 Backup por chunks concluído com sucesso!"
        log "INFO" "   📁 Arquivo: $output_file"
        
        # Verificar tamanho do arquivo
        if [[ -s "$output_file" ]]; then
            local file_size=$(stat -c%s "$output_file")
            local file_size_mb=$(echo "scale=1; $file_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            
            # Comprimir se habilitado
            if [[ "${BACKUP_COMPRESSION:-true}" == "true" ]]; then
                log "INFO" "   🗜️ Comprimindo backup..."
                gzip "$output_file"
                output_file="${output_file}.gz"
                
                local compressed_size=$(stat -c%s "$output_file")
                local compressed_size_mb=$(echo "scale=1; $compressed_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
                
                log "SUCCESS" "   ✅ Backup comprimido: ${compressed_size_mb} MB"
            fi
            
            local end_time=$(date +%s)
            local duration=$((end_time - SCRIPT_START_TIME))
            
            log "SUCCESS" "✅ Backup da tabela '$table' concluído!"
            log "INFO" "   📊 Tamanho final: ${file_size_mb} MB"
            log "INFO" "   ⏱️ Tempo total: ${duration}s"
            log "INFO" "   📦 Chunks processados: $successful_chunks/$total_chunks"
            
            return 0
        else
            log "ERROR" "❌ Arquivo de backup está vazio"
            return 1
        fi
    else
        log "ERROR" "❌ Backup por chunks falhou: $failed_chunks chunks falharam"
        return 1
    fi
}

# Função para detectar tabelas grandes automaticamente
detect_large_tables() {
    local database=$1
    local size_threshold_mb=${2:-10000}  # Default: 10GB
    
    log "INFO" "🔍 Detectando tabelas grandes no database '$database' (> ${size_threshold_mb}MB)..."
    
    local large_tables=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
        "SELECT table_name, ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
         FROM information_schema.tables 
         WHERE table_schema = '$database' 
         AND (data_length + index_length) > ($size_threshold_mb * 1024 * 1024)
         ORDER BY size_mb DESC;" 2>/dev/null)
    
    if [[ -n "$large_tables" ]]; then
        log "INFO" "📊 Tabelas grandes encontradas:"
        echo "$large_tables" | while read -r table_name size_mb; do
            log "INFO" "   📦 $table_name: ${size_mb}MB"
        done
        echo "$large_tables" | cut -f1
    else
        log "INFO" "ℹ️ Nenhuma tabela grande encontrada"
    fi
}

# Função principal para backup inteligente
backup_database_smart() {
    local database=$1
    
    log "INFO" "🤖 Iniciando backup inteligente do database '$database'"
    
    # Detectar tabelas grandes
    local large_tables=$(detect_large_tables "$database" 1000)  # > 1GB
    
    if [[ -n "$large_tables" ]]; then
        log "INFO" "🔧 Usando estratégia de chunks para tabelas grandes"
        
        # Fazer backup das tabelas grandes por chunks
        echo "$large_tables" | while read -r table; do
            if [[ -n "$table" ]]; then
                backup_table_chunks "$database" "$table" 50000  # 50k registros por chunk
            fi
        done
        
        # Backup normal para tabelas pequenas
        log "INFO" "📦 Fazendo backup normal das demais tabelas..."
        
        # Obter lista de tabelas pequenas
        local small_tables=$(mysql ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" -BN -e \
            "SELECT table_name FROM information_schema.tables 
             WHERE table_schema = '$database' 
             AND (data_length + index_length) <= (1000 * 1024 * 1024);" 2>/dev/null)
        
        if [[ -n "$small_tables" ]]; then
            local small_tables_list=$(echo "$small_tables" | tr '\n' ' ')
            local backup_file="/backups/${BACKUP_PREFIX:-backup}_${database}_small_tables_${BACKUP_DATE}.sql"
            
            mysqldump ${MYSQL_CLIENT_OPTIONS} -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
                --single-transaction \
                --routines \
                --triggers \
                --add-drop-database \
                --default-character-set=utf8mb4 \
                $MYSQLDUMP_OPTIONS \
                "$database" $small_tables_list > "$backup_file"
            
            if [[ $? -eq 0 ]] && [[ "${BACKUP_COMPRESSION:-true}" == "true" ]]; then
                gzip "$backup_file"
            fi
            
            log "SUCCESS" "✅ Backup das tabelas pequenas concluído"
        fi
    else
        log "INFO" "📦 Todas as tabelas são pequenas - usando backup tradicional"
        # Usar script de backup tradicional
        /scripts/backup.sh
    fi
}

# Função principal
main() {
    local database="${1:-$DATABASES}"
    local table="$2"
    
    if [[ -z "$database" ]]; then
        log "ERROR" "❌ Database não especificado"
        echo "Uso: $0 <database> [tabela_específica]"
        exit 1
    fi
    
    log "INFO" "🚀 BACKUP POR CHUNKS - BEE-BACKUP SYSTEM"
    log "INFO" "=========================================="
    
    # Verificar variáveis de ambiente necessárias
    if [[ -z "$DB_USERNAME" || -z "$DB_PASSWORD" || -z "$SOURCE_HOST" || -z "$SOURCE_PORT" ]]; then
        log "ERROR" "❌ Variáveis de ambiente não configuradas"
        exit 1
    fi
    
    if [[ -n "$table" ]]; then
        # Backup de tabela específica por chunks
        backup_table_chunks "$database" "$table" 50000
    else
        # Backup inteligente do database completo
        backup_database_smart "$database"
    fi
    
    local script_end_time=$(date +%s)
    local total_duration=$((script_end_time - SCRIPT_START_TIME))
    local minutes=$((total_duration / 60))
    local seconds=$((total_duration % 60))
    
    log "INFO" "=========================================="
    log "SUCCESS" "🎉 PROCESSO CONCLUÍDO!"
    log "INFO" "⏱️ Tempo total: ${minutes}m ${seconds}s"
    log "INFO" "=========================================="
}

# Verificar se o script está sendo executado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
