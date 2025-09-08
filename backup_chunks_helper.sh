#!/bin/bash

# =============================================================================
# MANUAL DE USO - BACKUP POR CHUNKS
# =============================================================================

echo "🚀 BEE-BACKUP SYSTEM - BACKUP POR CHUNKS"
echo "=========================================="
echo ""

case "${1:-help}" in
    "help"|"--help"|"-h")
        echo "📋 COMANDOS DISPONÍVEIS:"
        echo ""
        echo "1. 🔧 Backup de tabela específica por chunks:"
        echo "   docker-compose exec mariadb-backup /scripts/backup_chunks.sh asasaude log_instituicao"
        echo ""
        echo "2. 🤖 Backup inteligente (detecta tabelas grandes automaticamente):"
        echo "   docker-compose exec mariadb-backup /scripts/backup_chunks.sh asasaude"
        echo ""
        echo "3. 🔍 Detectar tabelas grandes:"
        echo "   docker-compose exec mariadb-backup /scripts/backup_chunks.sh detect asasaude"
        echo ""
        echo "4. 📊 Monitorar progresso:"
        echo "   docker-compose exec mariadb-backup tail -f /logs/backup.log"
        echo ""
        echo "5. 📁 Listar backups gerados:"
        echo "   docker-compose exec mariadb-backup ls -lah /backups/"
        echo ""
        ;;
        
    "test")
        echo "🧪 TESTANDO CONFIGURAÇÃO..."
        echo ""
        
        # Verificar se container está rodando
        if docker-compose ps mariadb-backup | grep -q "Up"; then
            echo "✅ Container mariadb-backup está rodando"
        else
            echo "❌ Container mariadb-backup não está rodando"
            echo "   Execute: docker-compose up -d"
            exit 1
        fi
        
        # Testar conexão com banco
        echo "🔌 Testando conexão com banco..."
        docker-compose exec mariadb-backup mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
            -e "SELECT 'Conexão OK' as status, NOW() as timestamp;" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✅ Conexão com banco funcionando"
        else
            echo "❌ Erro na conexão com banco - verifique .env"
            exit 1
        fi
        
        # Verificar se tabela log_instituicao existe
        echo "🔍 Verificando tabela log_instituicao..."
        ROWS=$(docker-compose exec mariadb-backup mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
            -BN -e "SELECT COUNT(*) FROM asasaude.log_instituicao;" 2>/dev/null || echo "0")
        
        if [ "$ROWS" -gt 0 ]; then
            echo "✅ Tabela log_instituicao encontrada: $ROWS registros"
            
            # Calcular tamanho
            SIZE=$(docker-compose exec mariadb-backup mysql -h"$SOURCE_HOST" -P"$SOURCE_PORT" -u"$DB_USERNAME" -p"$DB_PASSWORD" \
                -BN -e "SELECT ROUND((data_length + index_length) / 1024 / 1024, 2) 
                        FROM information_schema.tables 
                        WHERE table_schema = 'asasaude' AND table_name = 'log_instituicao';" 2>/dev/null || echo "0")
            
            echo "📊 Tamanho da tabela: ${SIZE} MB"
            
            if [ $(echo "$SIZE > 1000" | bc -l 2>/dev/null || echo "0") -eq 1 ]; then
                echo "⚡ Tabela grande detectada - backup por chunks recomendado!"
            else
                echo "ℹ️  Tabela pequena - backup tradicional pode funcionar"
            fi
        else
            echo "❌ Tabela log_instituicao não encontrada ou vazia"
        fi
        
        echo ""
        echo "🎯 TESTE CONCLUÍDO!"
        ;;
        
    "detect")
        echo "🔍 DETECTANDO TABELAS GRANDES..."
        docker-compose exec mariadb-backup /scripts/backup_chunks.sh detect asasaude
        ;;
        
    "log_instituicao"|"chunks")
        echo "🚀 INICIANDO BACKUP POR CHUNKS DA TABELA log_instituicao..."
        echo ""
        
        # Verificar se já existe algum backup rodando
        if docker-compose exec mariadb-backup ps aux | grep -q mysqldump; then
            echo "⚠️  ATENÇÃO: Já existe um processo mysqldump rodando!"
            echo "   Processos ativos:"
            docker-compose exec mariadb-backup ps aux | grep mysqldump
            echo ""
            echo "   Deseja continuar mesmo assim? (y/N)"
            read -r response
            if [[ "$response" != "y" && "$response" != "Y" ]]; then
                echo "❌ Operação cancelada"
                exit 1
            fi
        fi
        
        echo "📊 Iniciando backup por chunks..."
        echo "   ⏱️  Tempo estimado: 2-4 horas"
        echo "   📦 Chunks de 50.000 registros"
        echo "   🗜️  Compressão automática habilitada"
        echo ""
        
        # Executar backup por chunks
        docker-compose exec mariadb-backup /scripts/backup_chunks.sh asasaude log_instituicao
        
        echo ""
        echo "✅ Backup por chunks finalizado!"
        echo "📁 Verificar arquivos em /backups/"
        ;;
        
    "smart")
        echo "🤖 INICIANDO BACKUP INTELIGENTE..."
        echo ""
        echo "   🔍 Detectando tabelas grandes automaticamente"
        echo "   📦 Tabelas > 1GB usarão chunks"
        echo "   ⚡ Tabelas pequenas usarão método tradicional"
        echo ""
        
        docker-compose exec mariadb-backup /scripts/backup_chunks.sh asasaude
        ;;
        
    "monitor")
        echo "📊 MONITORANDO LOGS DE BACKUP..."
        echo "   (Pressione Ctrl+C para sair)"
        echo ""
        docker-compose exec mariadb-backup tail -f /logs/backup.log
        ;;
        
    "list")
        echo "📁 BACKUPS DISPONÍVEIS:"
        docker-compose exec mariadb-backup ls -lah /backups/ | grep -E "(chunks|log_instituicao)"
        ;;
        
    "status")
        echo "📊 STATUS DO SISTEMA:"
        echo ""
        
        # Status do container
        echo "🐳 Container:"
        docker-compose ps mariadb-backup
        echo ""
        
        # Processos ativos
        echo "⚙️  Processos mysqldump ativos:"
        docker-compose exec mariadb-backup ps aux | grep mysqldump | grep -v grep || echo "   Nenhum processo ativo"
        echo ""
        
        # Espaço em disco
        echo "💾 Espaço em disco:"
        docker-compose exec mariadb-backup df -h /backups
        ;;
        
    *)
        echo "❌ Comando não reconhecido: $1"
        echo ""
        echo "Use: $0 help para ver comandos disponíveis"
        exit 1
        ;;
esac
