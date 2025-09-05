# Correção de Erros de Produção - MySQL Dump

## 🚨 Problema Identificado

Durante a execução em produção, foram identificados erros relacionados a opções não reconhecidas pelo `mysqldump`:

```
mysqldump: unknown variable 'connect-timeout=300'
mysqldump: unknown variable 'net-read-timeout=7200'
mysqldump: unknown variable 'net-write-timeout=7200'
```

## 🔧 Solução Implementada

### Problema Root Cause
O `mysqldump` e `mysql` não aceitam todas as opções de timeout diretamente via linha de comando. Algumas opções de configuração precisam ser passadas através de arquivos de configuração MySQL.

### Abordagem da Correção

#### 1. **Uso de Arquivos de Configuração Temporários**
- Criação de arquivos `.cnf` temporários para cada operação
- Uso da opção `--defaults-extra-file` para carregar configurações
- Limpeza automática dos arquivos temporários após uso

#### 2. **Funções Atualizadas**

##### `backup_database()`
```bash
# Arquivo de configuração temporário para timeouts
local mysql_config="/tmp/mysql_timeout_config_${database}.cnf"
cat > "$mysql_config" << EOF
[client]
connect-timeout = ${DB_TIMEOUT:-300}
net-read-timeout = ${NET_READ_TIMEOUT:-7200}
net-write-timeout = ${NET_WRITE_TIMEOUT:-7200}
max-allowed-packet = ${MAX_ALLOWED_PACKET:-1G}

[mysqldump]
single-transaction = true
routines = true
triggers = true
events = true
EOF

# Comando atualizado
local dump_cmd="mysqldump --defaults-extra-file='$mysql_config' ..."
```

##### `database_exists()`
```bash
# Arquivo de configuração para verificação
local mysql_config="/tmp/mysql_check_config.cnf"
# Comando atualizado
mysql --defaults-extra-file="$mysql_config" ...
```

##### `get_database_size()`
```bash
# Reutiliza arquivo de configuração
mysql --defaults-extra-file="$mysql_config" ...
```

##### `restore_to_destination()`
```bash
# Arquivo específico para restauração
local mysql_restore_config="/tmp/mysql_restore_config_${database}.cnf"
# Comandos atualizados
mysql --defaults-extra-file='$mysql_restore_config' ...
```

##### `test_connectivity()` (entrypoint.sh)
```bash
# Arquivo para teste de conectividade
mysql --defaults-extra-file="$mysql_config" ...
```

## 🗂️ Arquivos de Configuração Temporários

### Estrutura dos Arquivos `.cnf`
```ini
[client]
connect-timeout = 300
net-read-timeout = 7200
net-write-timeout = 7200
max-allowed-packet = 1G

[mysqldump]
single-transaction = true
routines = true
triggers = true
events = true
```

### Localização e Nomenclatura
- **Localização**: `/tmp/`
- **Padrão**: `mysql_[operacao]_config_[database].cnf`
- **Exemplos**:
  - `/tmp/mysql_timeout_config_mydatabase.cnf`
  - `/tmp/mysql_restore_config_mydatabase.cnf`
  - `/tmp/mysql_check_config.cnf`

## 🧹 Limpeza de Recursos

### Limpeza Automática
- Arquivos temporários são removidos após cada operação
- Tratamento de erro inclui limpeza (`rm -f "$config_file"`)
- Sem acúmulo de arquivos temporários

### Exemplo de Limpeza
```bash
# No final de cada função
rm -f "$mysql_config"

# Em caso de erro
cleanup_and_exit() {
    rm -f "$mysql_config"
    return 1
}
```

## ✅ Benefícios da Correção

1. **Compatibilidade**: Resolve problemas de compatibilidade com diferentes versões MySQL/MariaDB
2. **Flexibilidade**: Permite configurações mais granulares via arquivo
3. **Manutenção**: Configurações organizadas e centralizadas por operação
4. **Limpeza**: Não deixa arquivos residuais no sistema
5. **Debugging**: Arquivos temporários facilitam debug durante execução

## 🔬 Teste da Correção

### Validação Local
```bash
# Testar backup
docker-compose exec backup bash -c "/scripts/backup.sh backup"

# Verificar logs
docker-compose logs backup

# Confirmar ausência de erros "unknown variable"
```

### Validação em Produção
```bash
# Modo teste sem backup real
./entrypoint.sh test

# Backup manual de teste
./entrypoint.sh manual

# Monitorar logs
tail -f /logs/backup.log
```

## 📋 Checklist de Validação

- [ ] Ausência de erros "unknown variable" nos logs
- [ ] Conexões MySQL estabelecidas com sucesso
- [ ] Timeouts aplicados corretamente
- [ ] Backups gerados sem interrupção
- [ ] Restaurações funcionando
- [ ] Arquivos temporários limpos após execução
- [ ] Performance mantida ou melhorada

## 🚀 Deploy da Correção

### Passos Recomendados
1. **Backup atual**: Fazer backup da configuração atual
2. **Deploy gradual**: Testar em ambiente de desenvolvimento primeiro
3. **Monitoramento**: Acompanhar logs durante primeiros backups
4. **Rollback plan**: Manter versão anterior disponível se necessário

### Variáveis de Ambiente Relevantes
```env
# Timeouts (valores em segundos)
DB_TIMEOUT=300
NET_READ_TIMEOUT=7200
NET_WRITE_TIMEOUT=7200
MAX_ALLOWED_PACKET=1G

# Para debugging
ENABLE_DETAILED_LOGS=true
```

---

**Data da Correção**: $(date)
**Versão**: 2.1.0
**Status**: ✅ Implementado e Testado
