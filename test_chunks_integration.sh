#!/bin/bash

# =============================================================================
# SCRIPT DE TESTE - INTEGRAÇÃO DO SISTEMA DE CHUNKS
# =============================================================================
# Este script testa a integração do sistema de backup por chunks no script principal

set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 TESTE DE INTEGRAÇÃO - SISTEMA DE CHUNKS${NC}"
echo -e "${BLUE}=================================================${NC}"
echo

# Diretório base do projeto
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${YELLOW}📁 Verificando estrutura dos arquivos...${NC}"

# 1. Verificar se arquivos existem
files_to_check=(
    "$BASE_DIR/scripts/backup.sh"
    "$BASE_DIR/.env.example"
    "$BASE_DIR/backup_chunks_helper.sh"
)

for file in "${files_to_check[@]}"; do
    if [[ -f "$file" ]]; then
        echo -e "   ✅ $file"
    else
        echo -e "   ❌ $file ${RED}(ARQUIVO NÃO ENCONTRADO)${NC}"
        exit 1
    fi
done

echo

# 2. Verificar se funções foram adicionadas no backup.sh
echo -e "${YELLOW}🔍 Verificando funções no backup.sh...${NC}"

functions_to_check=(
    "detect_large_tables"
    "backup_table_chunks"
)

for func in "${functions_to_check[@]}"; do
    if grep -q "^$func()" "$BASE_DIR/scripts/backup.sh"; then
        echo -e "   ✅ Função $func encontrada"
    else
        echo -e "   ❌ Função $func ${RED}(NÃO ENCONTRADA)${NC}"
        exit 1
    fi
done

echo

# 3. Verificar se as configurações estão no .env.example
echo -e "${YELLOW}⚙️  Verificando configurações no .env.example...${NC}"

config_vars=(
    "CHUNK_SIZE_THRESHOLD_MB"
    "CHUNK_SIZE"
    "ENABLE_AUTO_CHUNKING"
    "CHUNK_TIMEOUT"
    "CHUNK_MAX_RETRIES"
)

for var in "${config_vars[@]}"; do
    if grep -q "^$var=" "$BASE_DIR/.env.example" || grep -q "^# $var=" "$BASE_DIR/.env.example"; then
        echo -e "   ✅ Configuração $var encontrada"
    else
        echo -e "   ❌ Configuração $var ${RED}(NÃO ENCONTRADA)${NC}"
        exit 1
    fi
done

echo

# 4. Verificar integração na função backup_database
echo -e "${YELLOW}🔗 Verificando integração na função backup_database...${NC}"

if grep -q "detect_large_tables" "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ Chamada para detect_large_tables encontrada"
else
    echo -e "   ❌ Chamada para detect_large_tables ${RED}(NÃO ENCONTRADA)${NC}"
    exit 1
fi

if grep -q "backup_table_chunks" "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ Chamada para backup_table_chunks encontrada"
else
    echo -e "   ❌ Chamada para backup_table_chunks ${RED}(NÃO ENCONTRADA)${NC}"
    exit 1
fi

if grep -q "MODO HÍBRIDO" "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ Lógica de backup híbrido encontrada"
else
    echo -e "   ❌ Lógica de backup híbrido ${RED}(NÃO ENCONTRADA)${NC}"
    exit 1
fi

echo

# 5. Teste de sintaxe do bash
echo -e "${YELLOW}✅ Testando sintaxe dos scripts...${NC}"

if bash -n "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ backup.sh - Sintaxe válida"
else
    echo -e "   ❌ backup.sh ${RED}(ERRO DE SINTAXE)${NC}"
    exit 1
fi

if bash -n "$BASE_DIR/backup_chunks_helper.sh"; then
    echo -e "   ✅ backup_chunks_helper.sh - Sintaxe válida"
else
    echo -e "   ❌ backup_chunks_helper.sh ${RED}(ERRO DE SINTAXE)${NC}"
    exit 1
fi

echo

# 6. Verificar se variáveis estão sendo usadas corretamente
echo -e "${YELLOW}📊 Verificando uso das variáveis de configuração...${NC}"

if grep -q 'CHUNK_SIZE_THRESHOLD_MB' "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ CHUNK_SIZE_THRESHOLD_MB sendo utilizada"
else
    echo -e "   ⚠️  CHUNK_SIZE_THRESHOLD_MB não encontrada no script"
fi

if grep -q 'CHUNK_SIZE' "$BASE_DIR/scripts/backup.sh"; then
    echo -e "   ✅ CHUNK_SIZE sendo utilizada"
else
    echo -e "   ⚠️  CHUNK_SIZE não encontrada no script"
fi

echo

# 7. Relatório final
echo -e "${GREEN}🎉 TESTE DE INTEGRAÇÃO CONCLUÍDO${NC}"
echo -e "${GREEN}===================================${NC}"
echo
echo -e "${GREEN}✅ SUCESSO:${NC} Sistema de backup por chunks integrado com sucesso!"
echo
echo -e "${BLUE}📋 RESUMO DA INTEGRAÇÃO:${NC}"
echo -e "   🔧 Funções de chunks adicionadas ao backup.sh"
echo -e "   ⚙️  Configurações adicionadas ao .env.example"  
echo -e "   🔗 Lógica de backup híbrido implementada"
echo -e "   ✅ Todos os testes de sintaxe passaram"
echo
echo -e "${PURPLE}🚀 PRÓXIMOS PASSOS:${NC}"
echo -e "   1. Configure suas variáveis no arquivo .env"
echo -e "   2. Teste o backup com: ${BLUE}./backup_chunks_helper.sh test${NC}"
echo -e "   3. Execute um backup real para validar"
echo
echo -e "${YELLOW}💡 DICA:${NC} Para bancos com tabelas >1GB, o sistema automaticamente"
echo -e "   detectará e usará backup por chunks, evitando timeouts!"
echo

exit 0
