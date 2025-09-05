# 📝 CONFIGURAÇÕES PARA DATABASES GRANDES - GUIA COMPLETO

## 🎯 **RESUMO DAS ALTERAÇÕES NO .env.example**

O arquivo `.env.example` foi atualizado com configurações específicas para databases grandes, incluindo:

### **✅ Novas Variáveis Adicionadas:**

#### **Timeouts Estendidos:**
```bash
NET_READ_TIMEOUT=600          # Timeout de leitura da rede MySQL
NET_WRITE_TIMEOUT=600         # Timeout de escrita da rede MySQL
MAX_ALLOWED_PACKET=128M       # Tamanho máximo de pacote MySQL
MYSQLDUMP_TIMEOUT=3600        # Timeout geral do mysqldump
```

#### **Sistema de Retry Aprimorado:**
```bash
MAX_RETRY_ATTEMPTS=3          # Número de tentativas
RETRY_INTERVAL=5              # Intervalo entre tentativas
```

#### **Configurações Específicas para DBs Grandes:**
```bash
LARGE_DB_MODE=auto            # Detecção automática de DB grande
USE_EXTENDED_INSERT=true      # Usar extended insert
DISABLE_COLUMN_STATISTICS=false  # Desabilitar estatísticas
USE_QUICK_MODE=false          # Usar modo quick
```

---

## 📊 **GUIA POR TAMANHO DE DATABASE**

### **📦 DATABASES PEQUENOS (<1GB):**
- ✅ Use configurações padrão
- ⏰ `MYSQLDUMP_TIMEOUT=1800` (30 min)
- 🔌 `DB_TIMEOUT=30`

### **📦 DATABASES MÉDIOS (1GB-50GB):**
- 🔌 `DB_TIMEOUT=300` (5 min)
- ⏰ `MYSQLDUMP_TIMEOUT=7200` (2 horas)
- 🌐 `NET_READ_TIMEOUT=3600`, `NET_WRITE_TIMEOUT=3600`

### **📦 DATABASES GRANDES (50GB-200GB):**
```bash
DB_TIMEOUT=300
NET_READ_TIMEOUT=7200
NET_WRITE_TIMEOUT=7200
MYSQLDUMP_TIMEOUT=21600       # 6 horas
MAX_RETRY_ATTEMPTS=5
RETRY_INTERVAL=60
USE_QUICK_MODE=true
USE_EXTENDED_INSERT=false
```

### **📦 DATABASES MUITO GRANDES (>200GB):**
```bash
DB_TIMEOUT=300
NET_READ_TIMEOUT=7200
NET_WRITE_TIMEOUT=7200
MAX_ALLOWED_PACKET=1G
MYSQLDUMP_TIMEOUT=28800       # 8 horas
MAX_RETRY_ATTEMPTS=5
RETRY_INTERVAL=60
ENABLE_DEBUG_LOGS=true
RETENTION_DAYS=14
BACKUP_TIME=0 22 * * *        # Horário noturno
```

---

## 🔧 **OPÇÕES MYSQLDUMP OTIMIZADAS**

### **Configuração Padrão:**
```bash
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4
```

### **Para Databases Grandes:**
```bash
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4 --quick --lock-tables=false --set-gtid-purged=OFF --column-statistics=0 --disable-keys --extended-insert=false
```

**Explicação das opções adicionais:**
- `--quick`: Reduz uso de memória
- `--lock-tables=false`: Evita travamentos
- `--set-gtid-purged=OFF`: Compatibilidade
- `--column-statistics=0`: MySQL 8.0+ otimização
- `--disable-keys`: Acelera importação
- `--extended-insert=false`: Melhor recuperação de erros

---

## 🚨 **TROUBLESHOOTING**

### **Erro: "Lost connection to server during query"**
```bash
# Aumente os timeouts de rede:
NET_READ_TIMEOUT=7200
NET_WRITE_TIMEOUT=7200
DB_TIMEOUT=300
```

### **Erro: "Timeout waiting for mysqldump"**
```bash
# Aumente o timeout geral:
MYSQLDUMP_TIMEOUT=28800  # 8 horas
```

### **Problemas de Memória no Servidor**
```bash
# Ative modo econômico:
USE_QUICK_MODE=true
USE_EXTENDED_INSERT=false
MAX_ALLOWED_PACKET=512M
```

### **Tabelas Travadas**
```bash
# Adicione às opções do mysqldump:
MYSQLDUMP_OPTIONS="... --lock-tables=false --single-transaction"
```

---

## ⚙️ **COMO APLICAR AS CONFIGURAÇÕES**

### **1. Para um Novo Projeto:**
```bash
# Copiar arquivo exemplo
cp .env.example .env

# Editar conforme o tamanho do seu database
nano .env
```

### **2. Para Database Grande Existente:**
```bash
# Usar o script de configuração específico
./configure_asasaude.sh configure

# Ou editar manualmente o .env com as configurações recomendadas
```

### **3. Testar Configurações:**
```bash
# Rebuild do container
docker-compose down
docker-compose build --no-cache
docker-compose up -d

# Testar configurações
docker-compose exec mariadb-backup /app/entrypoint.sh test
```

---

## 📈 **ESTIMATIVAS DE TEMPO**

| Tamanho DB | Tempo Estimado | Configuração Recomendada |
|------------|----------------|--------------------------|
| <1GB       | 5-15 min       | Padrão                   |
| 1-10GB     | 15min-2h       | Timeouts médios          |
| 10-50GB    | 1-4h           | Timeouts estendidos      |
| 50-200GB   | 3-8h           | Modo otimizado           |
| >200GB     | 6-12h          | Configuração completa    |

---

## 💡 **DICAS IMPORTANTES**

### **Para Produção:**
- ✅ Execute backups em horários de baixo uso
- ✅ Monitor logs durante os primeiros backups
- ✅ Verifique espaço em disco regularmente
- ✅ Mantenha retenção adequada (14+ dias para DBs grandes)

### **Para Desenvolvimento:**
- ⚠️  Use configurações menos agressivas
- ⚠️  Considere backup apenas de estrutura para testes
- ⚠️  Implemente backup incremental se possível

### **Monitoramento:**
- 📊 Use `monitor` mode para acompanhar progresso
- 📊 Verifique logs de erro regularmente  
- 📊 Configure notificações por email/webhook

---

*Documentação atualizada em: $(date '+%Y-%m-%d %H:%M:%S')*  
*Arquivo: .env.example*  
*Status: ✅ Configurações otimizadas para databases grandes*
