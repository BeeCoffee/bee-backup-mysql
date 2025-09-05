#!/bin/bash

# =============================================================================
# SCRIPT DE MONITORAMENTO DE BACKUP EM TEMPO REAL
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

# Função para obter progresso atual
get_backup_progress() {
    local backup_pid=$1
    local backup_file=$2
    local estimated_size=$3
    
    if [[ -z "$backup_pid" || ! -d "/proc/$backup_pid" ]]; then
        return 1
    fi
    
    if [[ -f "$backup_file" ]]; then
        local current_size=$(stat -c%s "$backup_file" 2>/dev/null || echo 0)
        local current_mb=$(echo "scale=1; $current_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
        local percentage=0
        
        if [[ -n "$estimated_size" && "$estimated_size" != "0" ]]; then
            percentage=$(echo "scale=1; ($current_mb / $estimated_size) * 100" | bc 2>/dev/null || echo "0.0")
        fi
        
        echo "${current_mb}|${percentage}"
    else
        echo "0.0|0.0"
    fi
}

# Função para monitorar processo mysqldump
monitor_mysqldump() {
    local database=$1
    local max_time=${2:-21600}  # 6 horas por padrão
    
    log "INFO" "🔍 Procurando processo mysqldump para database '$database'..."
    
    local start_time=$(date +%s)
    local last_progress_time=$start_time
    local last_size=0
    local no_progress_count=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local elapsed_min=$((elapsed / 60))
        
        # Verificar se excedeu o tempo máximo
        if [[ $elapsed -gt $max_time ]]; then
            log "ERROR" "❌ Timeout: backup excedeu tempo máximo de $((max_time/3600)) horas"
            return 1
        fi
        
        # Procurar processo mysqldump ativo
        local mysqldump_pid=$(pgrep -f "mysqldump.*$database" 2>/dev/null || echo "")
        
        if [[ -z "$mysqldump_pid" ]]; then
            log "WARNING" "⚠️  Processo mysqldump não encontrado - backup pode ter finalizado ou falhado"
            return 1
        fi
        
        # Procurar arquivo de backup sendo criado
        local backup_file=$(find /backups -name "*${database}*.sql" -type f 2>/dev/null | head -1)
        
        if [[ -n "$backup_file" ]]; then
            local current_size=$(stat -c%s "$backup_file" 2>/dev/null || echo 0)
            local current_mb=$(echo "scale=1; $current_size / 1024 / 1024" | bc 2>/dev/null || echo "0.0")
            
            # Calcular velocidade de escrita
            local size_diff=$((current_size - last_size))
            local time_diff=$((current_time - last_progress_time))
            local speed_mbps=0
            
            if [[ $time_diff -gt 0 ]]; then
                speed_mbps=$(echo "scale=1; ($size_diff / 1024 / 1024) / $time_diff" | bc 2>/dev/null || echo "0.0")
            fi
            
            # Verificar se há progresso
            if [[ $current_size -eq $last_size ]]; then
                ((no_progress_count++))
                if [[ $no_progress_count -gt 10 ]]; then  # 5 minutos sem progresso
                    log "WARNING" "⚠️  Sem progresso detectado há $((no_progress_count/2)) minutos"
                fi
            else
                no_progress_count=0
                last_size=$current_size
                last_progress_time=$current_time
            fi
            
            # Log de progresso
            echo -ne "\r${BLUE}[$(date '+%H:%M:%S')]${NC} 📊 Backup em progresso: ${current_mb} MB | Velocidade: ${speed_mbps} MB/s | Tempo: ${elapsed_min}m | PID: $mysqldump_pid"
        else
            echo -ne "\r${YELLOW}[$(date '+%H:%M:%S')]${NC} ⏳ Aguardando criação do arquivo de backup... | Tempo: ${elapsed_min}m | PID: $mysqldump_pid"
        fi
        
        sleep 30
    done
}

# Função para verificar recursos do sistema
check_system_resources() {
    log "INFO" "💻 Verificando recursos do sistema..."
    
    # Uso de CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 2>/dev/null || echo "N/A")
    
    # Uso de memória
    local mem_info=$(free -m 2>/dev/null || echo "Total: N/A Available: N/A")
    
    # Espaço em disco
    local disk_info=$(df -h /backups 2>/dev/null || echo "N/A")
    
    log "INFO" "   🔧 CPU: ${cpu_usage}%"
    log "INFO" "   🧠 Memória: $mem_info"
    log "INFO" "   💾 Disco (/backups):"
    echo "$disk_info"
}

# Função para verificar logs de erro
check_error_logs() {
    local database=$1
    local error_file="/tmp/mysqldump_error_${database}.log"
    
    if [[ -f "$error_file" ]]; then
        local error_content=$(tail -10 "$error_file" 2>/dev/null)
        if [[ -n "$error_content" ]]; then
            log "WARNING" "⚠️  Erros detectados em $error_file:"
            echo "$error_content"
        fi
    fi
}

# Função principal
main() {
    local database="${1}"
    local max_time="${2:-21600}"
    
    if [[ -z "$database" ]]; then
        log "ERROR" "❌ Database não especificado"
        log "INFO" "Uso: $0 <nome_do_database> [tempo_maximo_segundos]"
        exit 1
    fi
    
    log "INFO" "🚀 Iniciando monitoramento de backup para '$database'"
    log "INFO" "⏰ Tempo máximo: $((max_time/3600))h $((max_time%3600/60))m"
    log "INFO" "========================================================"
    
    # Verificar recursos iniciais
    check_system_resources
    
    # Monitorar backup
    echo ""
    log "INFO" "📡 Iniciando monitoramento em tempo real..."
    log "INFO" "💡 Pressione Ctrl+C para interromper o monitoramento"
    echo ""
    
    # Trap para limpeza
    trap 'echo -e "\n${YELLOW}[$(date +"%H:%M:%S")] Monitoramento interrompido pelo usuário${NC}"; exit 0' SIGINT SIGTERM
    
    if monitor_mysqldump "$database" "$max_time"; then
        echo ""
        log "SUCCESS" "✅ Monitoramento concluído com sucesso"
    else
        echo ""
        log "ERROR" "❌ Problema detectado durante o backup"
        check_error_logs "$database"
        return 1
    fi
}

# Executar se chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
