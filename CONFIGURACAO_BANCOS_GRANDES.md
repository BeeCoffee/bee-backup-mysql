# Configuração para Bancos de Dados Grandes (200GB+)

Este guia orienta a configuração do sistema de backup para bancos de dados grandes com tabelas individuais de 30GB a 80GB.

## 🎯 Quando Usar Esta Configuração

- **Banco total**: 200GB ou mais
- **Tabelas grandes**: 30GB a 80GB individuais
- **Ambiente**: Produção com zero downtime
- **Conectividade**: Conexões remotas ou instáveis

## 🚀 Configuração Rápida

```bash
# 1. Copiar template otimizado
cp .env.example.large .env

# 2. Editar configurações básicas
vim .env

# 3. Ajustar apenas estas variáveis:
SOURCE_HOST=seu_servidor
SOURCE_PORT=sua_porta
DB_USERNAME=seu_usuario
DB_PASSWORD=sua_senha
DATABASES=seu_database
```

## ⚙️ Configurações Críticas para Bancos Grandes

### Chunking Automático (Essencial)
```bash
ENABLE_AUTO_CHUNKING=true
CHUNK_SIZE_THRESHOLD_MB=500  # Detecta tabelas >500MB
CHUNK_SIZE=50000             # Registros por chunk
CHUNK_TIMEOUT=2700          # 45min por chunk
CHUNK_MAX_RETRIES=5         # Tentativas por chunk
```

### Timeouts Otimizados
```bash
DB_TIMEOUT=21600            # 6 horas total
MYSQLDUMP_TIMEOUT=21600     # 6 horas por operação
```

### Zero Locks (Produção)
```bash
MYSQLDUMP_OPTIONS="--single-transaction --quick --lock-tables=false --no-tablespaces --skip-lock-tables --skip-add-locks --routines --triggers --default-character-set=utf8mb4 --max_allowed_packet=2G --net_buffer_length=32K --extended-insert --disable-keys"
```

## 📊 Estimativas de Performance

### Para banco de 200GB com tabela de 80GB:

| Métrica | Valor Estimado |
|---------|----------------|
| **Tempo total** | 8-12 horas |
| **Chunks gerados** | ~400-500 |
| **Espaço necessário** | ~60GB (com compressão) |
| **Tempo de restauração** | 4-6 horas |

### Breakdown por tamanho de tabela:

| Tamanho da Tabela | Chunks | Tempo Estimado |
|-------------------|--------|----------------|
| 30GB | ~150 | 2-3 horas |
| 50GB | ~250 | 4-5 horas |
| 80GB | ~400 | 6-8 horas |

## 🔧 Otimizações Específicas

### Para tabelas de 30GB:
```bash
CHUNK_SIZE=75000
CHUNK_TIMEOUT=1800  # 30min
```

### Para tabelas de 50GB:
```bash
CHUNK_SIZE=60000
CHUNK_TIMEOUT=2400  # 40min
```

### Para tabelas de 80GB:
```bash
CHUNK_SIZE=50000
CHUNK_TIMEOUT=2700  # 45min
```

## 🚨 Troubleshooting Comum

### Backup muito lento
- Aumentar `CHUNK_SIZE` para 75000-100000
- Verificar rede entre servidor e destino
- Executar durante horário de menor uso

### Timeout em chunks específicos
- Reduzir `CHUNK_SIZE` para 25000-35000
- Aumentar `CHUNK_TIMEOUT`
- Verificar se tabela tem índices adequados

### Problemas de memória
- Usar `CHUNK_SIZE=10000-25000`
- Verificar `--max_allowed_packet` no MySQL
- Monitorar uso de RAM do servidor

### Backup corrompido
- Sempre usar `--single-transaction`
- Ativar `VERIFY_BACKUP_INTEGRITY=true`
- Verificar espaço em disco suficiente

## 📱 Monitoramento

### Logs em tempo real:
```bash
docker compose logs -f mariadb-backup
tail -f logs/backup.log
```

### Verificar progresso:
```bash
# Ver backups gerados
ls -lh backups/

# Monitorar espaço em disco
df -h /path/to/backups
```

### Alertas importantes:
- Configure notificações por email
- Use webhooks para Slack/Teams
- Monitore espaço em disco (2x o tamanho do DB)

## 🔄 Estratégia de Backup para Produção

### Agendamento recomendado:
```bash
# Backup completo: 1x por dia, madrugada
BACKUP_TIME="0 2 * * *"

# Retenção: 14 dias (tempo para regenerar em caso de falha)
RETENTION_DAYS=14
```

### Validação:
1. **Sempre** testar restauração em ambiente não-produção
2. Verificar integridade dos backups semanalmente
3. Monitorar tempo de execução (detectar degradação)

## 🎛️ Configurações Avançadas

### Para ambientes com conexão instável:
```bash
CHUNK_MAX_RETRIES=7
RETRY_INTERVAL=60
CHUNK_INTERVAL_MS=500  # Pausa maior entre chunks
```

### Para maximizar velocidade (rede estável):
```bash
CHUNK_SIZE=100000
CHUNK_INTERVAL_MS=50
MYSQL_CLIENT_OPTIONS="--max_allowed_packet=4G --net_buffer_length=64K"
```

## 🛡️ Segurança e Compliance

- Use usuário com privilégios mínimos necessários
- Configure SSL se backup via rede pública
- Criptografe arquivos de backup em repouso
- Implemente rotação de senhas regularmente

---

**💡 Lembre-se**: Para bancos de dados grandes, o tempo de backup é um investimento na continuidade do negócio. Configure alertas adequados e sempre teste a restauração!
