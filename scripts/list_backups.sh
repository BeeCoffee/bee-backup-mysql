#!/bin/bash

# =============================================================================
# SCRIPT PARA LISTAR BACKUPS DISPONÍVEIS
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Função para logging com timestamp
log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${BLUE}$message${NC}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}$message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}$message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}$message${NC}"
            ;;
        "HEADER")
            echo -e "${CYAN}$message${NC}"
            ;;
    esac
}

# Função para exibir ajuda
show_help() {
    cat << EOF
📋 LISTAGEM DE BACKUPS MARIADB/MYSQL

🎯 Uso:
    $0 [opções]

📝 Opções:
    --help, -h          Exibir esta ajuda
    --recent, -r        Mostrar apenas backups recentes (últimas 24h)
    --database DB, -d   Filtrar por database específico
    --size, -s          Ordenar por tamanho (maior primeiro)
    --date              Ordenar por data (mais recente primeiro) - padrão
    --summary           Mostrar apenas resumo estatístico
    --json              Saída em formato JSON

📋 Exemplos:
    $0                          # Listar todos os backups
    $0 --recent                 # Backups das últimas 24h
    $0 --database loja_online   # Backups de um database específico
    $0 --size                   # Ordenar por tamanho
    $0 --summary                # Apenas estatísticas

ℹ️  Informações exibidas:
    • Nome do arquivo
    • Database de origem
    • Data/hora de criação
    • Tamanho do arquivo
    • Tipo (SQL/Comprimido)
    • Idade do backup
EOF
}

# Função para converter bytes para formato legível
human_readable_size() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    local size=$bytes
    
    while [[ $size -gt 1024 && $unit -lt 4 ]]; do
        size=$((size / 1024))
        ((unit++))
    done
    
    if [[ $unit -eq 0 ]]; then
        echo "${size} ${units[$unit]}"
    else
        printf "%.1f %s" "$(echo "scale=1; $bytes / (1024^$unit)" | bc 2>/dev/null || echo "$size")" "${units[$unit]}"
    fi
}

# Função para calcular idade do backup
calculate_age() {
    local file_time=$1
    local current_time=$(date +%s)
    local age_seconds=$((current_time - file_time))
    
    local days=$((age_seconds / 86400))
    local hours=$(((age_seconds % 86400) / 3600))
    local minutes=$(((age_seconds % 3600) / 60))
    
    if [[ $days -gt 0 ]]; then
        echo "${days}d ${hours}h"
    elif [[ $hours -gt 0 ]]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# Função para extrair nome do database do arquivo
extract_database_name() {
    local filename="$1"
    local db_name="unknown"
    
    # Padrões comuns de nomenclatura
    if [[ "$filename" =~ ^backup_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
        db_name="${BASH_REMATCH[1]}"
    elif [[ "$filename" =~ ^(.+)_(.+)_[0-9]{8}_[0-9]{6}\.sql ]]; then
        db_name="${BASH_REMATCH[2]}"
    elif [[ "$filename" =~ ^([^_]+)_ ]]; then
        db_name="${BASH_REMATCH[1]}"
    fi
    
    echo "$db_name"
}

# Função para obter informações detalhadas do backup
get_backup_info() {
    local file="$1"
    local filename=$(basename "$file")
    local filesize=$(stat -c%s "$file" 2>/dev/null || echo "0")
    local file_time=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    local file_date=$(stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)
    local db_name=$(extract_database_name "$filename")
    local age=$(calculate_age "$file_time")
    local type="SQL"
    
    if [[ "$filename" == *.gz ]]; then
        type="Comprimido"
    fi
    
    echo "$file|$filename|$db_name|$file_date|$filesize|$type|$age|$file_time"
}

# Função para listar backups em formato tabular
list_backups_table() {
    local files=("$@")
    local total_files=${#files[@]}
    local total_size=0
    
    if [[ $total_files -eq 0 ]]; then
        log "WARNING" "⚠️  Nenhum backup encontrado"
        return 0
    fi
    
    log "HEADER" "📊 BACKUPS DISPONÍVEIS"
    log "HEADER" "======================"
    echo ""
    
    # Header da tabela
    printf "%-4s %-35s %-15s %-20s %10s %-12s %8s\n" \
        "Nº" "Nome do Arquivo" "Database" "Data/Hora" "Tamanho" "Tipo" "Idade"
    log "HEADER" "$(printf '%.0s-' {1..100})"
    
    local count=0
    for info in "${files[@]}"; do
        ((count++))
        
        IFS='|' read -r file filename db_name file_date filesize type age file_time <<< "$info"
        
        total_size=$((total_size + filesize))
        local human_size=$(human_readable_size "$filesize")
        
        # Colorir baseado na idade
        local age_color=""
        local age_hours=$(($(date +%s) - file_time))
        age_hours=$((age_hours / 3600))
        
        if [[ $age_hours -le 24 ]]; then
            age_color="${GREEN}"  # Verde para backups recentes
        elif [[ $age_hours -le 168 ]]; then  # 7 dias
            age_color="${YELLOW}" # Amarelo para backups da semana
        else
            age_color="${RED}"    # Vermelho para backups antigos
        fi
        
        printf "%-4d %-35s %-15s %-20s %10s %-12s ${age_color}%8s${NC}\n" \
            "$count" \
            "$(echo "$filename" | cut -c1-34)" \
            "$(echo "$db_name" | cut -c1-14)" \
            "$file_date" \
            "$human_size" \
            "$type" \
            "$age"
    done
    
    echo ""
    log "HEADER" "$(printf '%.0s-' {1..100})"
    log "INFO" "📈 Total: $total_files arquivos | 💾 Tamanho total: $(human_readable_size $total_size)"
    echo ""
    
    # Legenda de cores
    log "INFO" "🎨 Legenda de cores:"
    echo -e "   ${GREEN}■${NC} Recente (24h)  ${YELLOW}■${NC} Semana (7d)  ${RED}■${NC} Antigo (>7d)"
}

# Função para listar backups em formato JSON
list_backups_json() {
    local files=("$@")
    
    echo "{"
    echo "  \"backups\": ["
    
    local count=0
    for info in "${files[@]}"; do
        ((count++))
        
        IFS='|' read -r file filename db_name file_date filesize type age file_time <<< "$info"
        
        [[ $count -gt 1 ]] && echo ","
        
        cat << EOF
    {
      "id": $count,
      "filename": "$filename",
      "full_path": "$file",
      "database": "$db_name",
      "date": "$file_date",
      "size_bytes": $filesize,
      "size_human": "$(human_readable_size $filesize)",
      "type": "$type",
      "age": "$age",
      "timestamp": $file_time
    }
EOF
    done
    
    echo ""
    echo "  ],"
    echo "  \"summary\": {"
    echo "    \"total_files\": ${#files[@]},"
    echo "    \"total_size_bytes\": $(( $(for info in "${files[@]}"; do IFS='|' read -r _ _ _ _ filesize _ _ _ <<< "$info"; echo "$filesize"; done | paste -sd+ | bc 2>/dev/null || echo 0) )),"
    echo "    \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\""
    echo "  }"
    echo "}"
}

# Função para mostrar apenas resumo
show_summary() {
    local files=("$@")
    local total_files=${#files[@]}
    local total_size=0
    local recent_count=0
    local by_database=()
    
    # Calcular estatísticas
    for info in "${files[@]}"; do
        IFS='|' read -r file filename db_name file_date filesize type age file_time <<< "$info"
        
        total_size=$((total_size + filesize))
        
        # Contar backups recentes (24h)
        local age_hours=$(($(date +%s) - file_time))
        age_hours=$((age_hours / 3600))
        if [[ $age_hours -le 24 ]]; then
            ((recent_count++))
        fi
        
        # Contar por database
        local found=false
        for i in "${!by_database[@]}"; do
            if [[ "${by_database[$i]}" == "$db_name:"* ]]; then
                local current_count=$(echo "${by_database[$i]}" | cut -d':' -f2)
                by_database[$i]="$db_name:$((current_count + 1))"
                found=true
                break
            fi
        done
        if [[ "$found" == false ]]; then
            by_database+=("$db_name:1")
        fi
    done
    
    log "HEADER" "📊 RESUMO ESTATÍSTICO DE BACKUPS"
    log "HEADER" "================================="
    echo ""
    
    log "INFO" "📁 Total de arquivos: $total_files"
    log "INFO" "💾 Tamanho total: $(human_readable_size $total_size)"
    log "INFO" "🕐 Backups recentes (24h): $recent_count"
    echo ""
    
    if [[ ${#by_database[@]} -gt 0 ]]; then
        log "INFO" "📊 Por database:"
        for db_info in "${by_database[@]}"; do
            IFS=':' read -r db count <<< "$db_info"
            printf "   %-20s %3d arquivo(s)\n" "$db" "$count"
        done
        echo ""
    fi
    
    # Mostrar arquivo mais recente e mais antigo
    if [[ $total_files -gt 0 ]]; then
        local newest_info="${files[0]}"
        local oldest_info="${files[-1]}"
        
        IFS='|' read -r _ newest_file newest_db newest_date _ _ _ _ <<< "$newest_info"
        IFS='|' read -r _ oldest_file oldest_db oldest_date _ _ _ _ <<< "$oldest_info"
        
        log "INFO" "🆕 Mais recente: $newest_file ($newest_date)"
        log "INFO" "📅 Mais antigo: $oldest_file ($oldest_date)"
    fi
}

# Função principal
main() {
    local show_recent=false
    local filter_database=""
    local sort_by="date"
    local output_format="table"
    local show_summary_only=false
    
    # Processar argumentos
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --recent|-r)
                show_recent=true
                shift
                ;;
            --database|-d)
                filter_database="$2"
                shift 2
                ;;
            --size|-s)
                sort_by="size"
                shift
                ;;
            --date)
                sort_by="date"
                shift
                ;;
            --summary)
                show_summary_only=true
                shift
                ;;
            --json)
                output_format="json"
                shift
                ;;
            *)
                log "ERROR" "❌ Opção inválida: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done
    
    # Verificar se diretório de backups existe
    if [[ ! -d "/backups" ]]; then
        log "ERROR" "❌ Diretório de backups não encontrado: /backups"
        exit 1
    fi
    
    log "INFO" "🔍 Procurando por backups em /backups..."
    
    # Encontrar arquivos de backup
    local backup_files=($(find /backups -name "*.sql*" -type f 2>/dev/null | sort))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log "WARNING" "⚠️  Nenhum backup encontrado em /backups"
        exit 0
    fi
    
    # Processar informações dos arquivos
    local backup_info=()
    for file in "${backup_files[@]}"; do
        local info=$(get_backup_info "$file")
        
        # Filtrar por database se especificado
        if [[ -n "$filter_database" ]]; then
            local db_name=$(echo "$info" | cut -d'|' -f3)
            if [[ "$db_name" != "$filter_database" ]]; then
                continue
            fi
        fi
        
        # Filtrar por período se especificado
        if [[ "$show_recent" == true ]]; then
            local file_time=$(echo "$info" | cut -d'|' -f8)
            local age_hours=$(($(date +%s) - file_time))
            age_hours=$((age_hours / 3600))
            if [[ $age_hours -gt 24 ]]; then
                continue
            fi
        fi
        
        backup_info+=("$info")
    done
    
    # Ordenar resultados
    if [[ "$sort_by" == "size" ]]; then
        # Ordenar por tamanho (maior primeiro)
        IFS=$'\n' backup_info=($(printf '%s\n' "${backup_info[@]}" | sort -t'|' -k5 -nr))
    else
        # Ordenar por data (mais recente primeiro)
        IFS=$'\n' backup_info=($(printf '%s\n' "${backup_info[@]}" | sort -t'|' -k8 -nr))
    fi
    
    # Exibir resultados
    if [[ "$show_summary_only" == true ]]; then
        show_summary "${backup_info[@]}"
    elif [[ "$output_format" == "json" ]]; then
        list_backups_json "${backup_info[@]}"
    else
        list_backups_table "${backup_info[@]}"
        
        # Mostrar instruções de uso
        echo ""
        log "INFO" "💡 Instruções de uso:"
        log "INFO" "   Restaurar: /scripts/restore_backup.sh /backups/nome_arquivo.sql.gz nome_database"
        log "INFO" "   Ver detalhes: ls -la /backups/"
        log "INFO" "   Ajuda: $0 --help"
    fi
}

# Executar apenas se script foi chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
