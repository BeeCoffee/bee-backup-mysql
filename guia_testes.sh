#!/bin/bash

# =============================================================================
# GUIA COMPLETO DE TESTES - SISTEMA DE BACKUP POR CHUNKS
# =============================================================================

echo "🧪 GUIA DE TESTES - SISTEMA DE BACKUP POR CHUNKS"
echo "================================================"
echo

echo "📋 MÉTODOS DE TESTE DISPONÍVEIS:"
echo

echo "🔸 TESTE 1: Verificação da Integração (✅ Já executado)"
echo "   ./test_chunks_integration.sh"
echo "   - Verifica se as funções foram integradas corretamente"
echo "   - Testa sintaxe dos scripts"
echo "   - Confirma que configurações estão presentes"
echo

echo "🔸 TESTE 2: Detecção de Tabelas Grandes"
echo "   ./test_detection.sh"
echo "   - Conecta no database e analisa tamanhos das tabelas"
echo "   - Mostra quais tabelas serão processadas por chunks"
echo "   - Estima quantos chunks serão necessários"
echo "   ⚠️  Requer: Servidor MySQL acessível"
echo

echo "🔸 TESTE 3: Backup Real com Monitoramento"
echo "   docker-compose up"
echo "   - Executa backup completo com chunks automático"
echo "   - Monitora progresso em tempo real"
echo "   - Gera arquivo de backup consolidado"
echo "   ⚠️  Requer: Servidor MySQL acessível"
echo

echo "🔸 TESTE 4: Simulação com Database de Teste (Recomendado)"
echo "   docker-compose -f docker-compose.test.yml up"
echo "   - Usa database pequeno para testar fluxo completo"
echo "   - Verifica funcionamento sem impacto na produção"
echo "   - Ideal para validar antes do uso real"
echo

echo
echo "🎯 PARA SEU CASO ESPECÍFICO (asasaude com log_instituicao):"
echo

echo "1️⃣  PRIMEIRO: Verifique se servidor está acessível"
echo "   mysql -h 127.0.0.1 -P 53306 -u backup-bee -p"
echo

echo "2️⃣  SEGUNDO: Execute teste de detecção"
echo "   ./test_detection.sh"
echo "   - Deve detectar log_instituicao como tabela grande"
echo "   - Mostrará quantos chunks serão necessários"
echo

echo "3️⃣  TERCEIRO: Backup com chunks em horário de teste"
echo "   # Configure para executar imediatamente"
echo "   RUN_ON_START=true"
echo "   docker-compose up"
echo

echo
echo "📊 O QUE ESPERAR NO SEU CASO:"
echo "   🔍 Detecção: log_instituicao (~80GB) será detectada"
echo "   📦 Chunks: ~1600 chunks de 50.000 registros cada"
echo "   ⏱️  Tempo: ~30min por chunk = estimativa de 20-30h total"
echo "   💾 Resultado: Arquivo único backup_asasaude_YYYY-MM-DD.sql.gz"
echo

echo
echo "🚨 TROUBLESHOOTING:"
echo
echo "❌ Erro de conexão:"
echo "   - Verifique se MariaDB está rodando na porta 53306"
echo "   - Teste credenciais: mysql -h 127.0.0.1 -P 53306 -u backup-bee -p"
echo "   - Confirme se usuário backup-bee tem permissões"
echo

echo "❌ Chunks muito lentos:"
echo "   - Reduza CHUNK_SIZE de 50000 para 25000"
echo "   - Aumente CHUNK_TIMEOUT se necessário"
echo

echo "❌ Erro 'Lost connection' ainda acontece:"
echo "   - Reduza CHUNK_SIZE para 10000"
echo "   - Verifique se CHUNK_SIZE_THRESHOLD_MB está correto"
echo

echo
echo "💡 DICAS DE OTIMIZAÇÃO PARA TABELA DE 80GB:"
echo
echo "# Para tabela log_instituicao específica, considere:"
echo "CHUNK_SIZE=25000                 # Chunks menores"
echo "CHUNK_TIMEOUT=3600              # 1h por chunk"
echo "CHUNK_MAX_RETRIES=5             # Mais tentativas"
echo "CHUNK_SIZE_THRESHOLD_MB=500     # Detectar tabelas >500MB"
echo

echo
echo "🎉 QUANDO TUDO FUNCIONAR:"
echo "   ✅ log_instituicao será processada automaticamente por chunks"
echo "   ✅ Sem erro 'Lost connection'"
echo "   ✅ Progresso detalhado no log"
echo "   ✅ Arquivo final consolidado como sempre"
echo

echo
echo "🚀 EXECUTE QUANDO ESTIVER PRONTO:"
echo "   ./test_detection.sh     # Para ver detecção"
echo "   docker-compose up       # Para backup real"
echo
