#!/bin/bash

# =============================================================================
# SCRIPT DE CONFIGURAÇÃO AUTOMÁTICA PARA BANCOS GRANDES
# =============================================================================

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 CONFIGURAÇÃO AUTOMÁTICA PARA BANCOS GRANDES (200GB+)${NC}"
echo -e "${BLUE}=========================================================${NC}"
echo ""

# Verificar se já existe .env
if [[ -f .env ]]; then
    echo -e "${YELLOW}⚠️  Arquivo .env já existe!${NC}"
    read -p "Deseja fazer backup do atual e criar novo? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        mv .env .env.backup.$(date +%Y%m%d_%H%M%S)
        echo -e "${GREEN}✅ Backup criado: .env.backup.$(date +%Y%m%d_%H%M%S)${NC}"
    else
        echo -e "${RED}❌ Operação cancelada${NC}"
        exit 1
    fi
fi

# Copiar template para bancos grandes
cp .env.example.large .env
echo -e "${GREEN}✅ Template para bancos grandes copiado${NC}"

echo ""
echo -e "${BLUE}📋 CONFIGURAÇÃO INTERATIVA${NC}"
echo -e "${BLUE}===========================${NC}"

# Configurações básicas
read -p "🔗 Host do servidor de origem: " SOURCE_HOST
read -p "🔌 Porta do servidor de origem (padrão 3306): " SOURCE_PORT
SOURCE_PORT=${SOURCE_PORT:-3306}

read -p "👤 Usuário do banco de dados: " DB_USERNAME
read -s -p "🔐 Senha do banco de dados: " DB_PASSWORD
echo

read -p "🗄️  Nome do database para backup: " DATABASE_NAME

echo ""
echo -e "${BLUE}⚙️  CONFIGURAÇÕES AVANÇADAS${NC}"
echo -e "${BLUE}===========================${NC}"

echo "Escolha o perfil de performance:"
echo "1) Conservador (mais seguro, mais lento)"
echo "2) Balanceado (recomendado)"
echo "3) Agressivo (mais rápido, maior risco)"
read -p "Opção (1-3): " PERFORMANCE_PROFILE

case $PERFORMANCE_PROFILE in
    1)
        CHUNK_SIZE=25000
        CHUNK_TIMEOUT=1800
        echo -e "${GREEN}✅ Perfil Conservador selecionado${NC}"
        ;;
    2)
        CHUNK_SIZE=50000
        CHUNK_TIMEOUT=2700
        echo -e "${GREEN}✅ Perfil Balanceado selecionado${NC}"
        ;;
    3)
        CHUNK_SIZE=75000
        CHUNK_TIMEOUT=3600
        echo -e "${GREEN}✅ Perfil Agressivo selecionado${NC}"
        ;;
    *)
        CHUNK_SIZE=50000
        CHUNK_TIMEOUT=2700
        echo -e "${YELLOW}⚠️  Opção inválida, usando Balanceado${NC}"
        ;;
esac

# Configurar notificações
read -p "📧 Email para notificações: " EMAIL_TO
read -p "📤 Email remetente: " EMAIL_FROM

echo ""
echo -e "${BLUE}🔧 APLICANDO CONFIGURAÇÕES...${NC}"

# Aplicar configurações no arquivo .env
sed -i "s/SOURCE_HOST=.*/SOURCE_HOST=$SOURCE_HOST/" .env
sed -i "s/SOURCE_PORT=.*/SOURCE_PORT=$SOURCE_PORT/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
sed -i "s/DATABASES=.*/DATABASES=$DATABASE_NAME/" .env
sed -i "s/CHUNK_SIZE=.*/CHUNK_SIZE=$CHUNK_SIZE/" .env
sed -i "s/CHUNK_TIMEOUT=.*/CHUNK_TIMEOUT=$CHUNK_TIMEOUT/" .env
sed -i "s/EMAIL_TO=.*/EMAIL_TO=$EMAIL_TO/" .env
sed -i "s/EMAIL_FROM=.*/EMAIL_FROM=$EMAIL_FROM/" .env

echo -e "${GREEN}✅ Configurações aplicadas com sucesso!${NC}"

echo ""
echo -e "${BLUE}📊 RESUMO DA CONFIGURAÇÃO${NC}"
echo -e "${BLUE}=========================${NC}"
echo -e "🔗 Servidor: ${GREEN}$SOURCE_HOST:$SOURCE_PORT${NC}"
echo -e "🗄️  Database: ${GREEN}$DATABASE_NAME${NC}"
echo -e "📦 Chunk Size: ${GREEN}$CHUNK_SIZE registros${NC}"
echo -e "⏱️  Timeout por Chunk: ${GREEN}$CHUNK_TIMEOUT segundos${NC}"
echo -e "📧 Notificações: ${GREEN}$EMAIL_TO${NC}"

echo ""
echo -e "${BLUE}🚀 PRÓXIMOS PASSOS${NC}"
echo -e "${BLUE}===============${NC}"
echo "1. Revisar configurações detalhadas em .env"
echo "2. Testar backup manual:"
echo -e "   ${YELLOW}docker compose up -d${NC}"
echo -e "   ${YELLOW}docker compose exec mariadb-backup /scripts/manual_backup.sh $DATABASE_NAME${NC}"
echo "3. Verificar logs em:"
echo -e "   ${YELLOW}docker compose logs -f${NC}"
echo "4. Configurar SMTP se necessário"

echo ""
echo -e "${GREEN}🎉 Configuração concluída!${NC}"
echo -e "${BLUE}📖 Para mais informações, consulte: CONFIGURACAO_BANCOS_GRANDES.md${NC}"
