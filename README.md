# 🐝 Bee Backup - Sistema Simplificado de Backup MySQL/MariaDB

![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-003545?style=for-the-badge&logo=mariadb&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)

**Sistema super simples para backup e restore de bancos MySQL/MariaDB usando Docker.**

---

## 🚀 Início Rápido (3 passos)

### 1️⃣ Configure o `.env`

```bash
cp .env.example .env
nano .env
```

```env
# Servidor de origem (onde estão os bancos)
SOURCE_HOST=192.168.1.100
SOURCE_PORT=3306

# Bancos para backup (separados por vírgula)
DATABASES=meu_banco,outro_banco

# Credenciais
DB_USERNAME=backup_user
DB_PASSWORD=sua_senha

# Servidor de destino (OPCIONAL - só se quiser restaurar automaticamente)
DEST_HOST=192.168.1.200
DEST_PORT=3306
```

### 2️⃣ Inicie o container

```bash
docker-compose up -d
```

### 3️⃣ Use! 🎉

```bash
# Fazer backup
docker exec bee-backup backup

# Ver backups
docker exec bee-backup list

# Restaurar
docker exec bee-backup restore
```

**Pronto! É só isso.** ✨

---

## 📋 Comandos Disponíveis

### 💾 Backup

```bash
# Fazer backup dos bancos definidos no .env
docker exec bee-backup backup

# Fazer backup de TODOS os bancos do servidor
docker exec bee-backup backup full

# Fazer backup E restaurar no servidor destino
docker exec bee-backup backup restore
```

### 🔄 Restore

```bash
# Restaurar bancos do .env (backup mais recente)
docker exec bee-backup restore

# Restaurar TODOS os backups disponíveis
docker exec bee-backup restore full

# Restaurar um backup específico
docker exec bee-backup restore /backups/backup_meudb_20251117.sql.gz
```

### 📊 Gerenciamento

```bash
# Listar todos os backups
docker exec bee-backup list

# Testar conexão com servidores
docker exec bee-backup test

# Limpar backups antigos
docker exec bee-backup clean
```

---

## ⚙️ Configuração Completa do `.env`

```env
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# OBRIGATÓRIO
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SOURCE_HOST=192.168.1.100          # Servidor origem
SOURCE_PORT=3306
DB_USERNAME=backup_user
DB_PASSWORD=sua_senha
DATABASES=banco1,banco2,banco3

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# OPCIONAL
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Servidor destino (para restauração automática)
DEST_HOST=192.168.1.200            # Deixe vazio para apenas backup
DEST_PORT=3306

# Configurações de backup
RETENTION_DAYS=7                   # Quantos dias manter backups
BACKUP_COMPRESSION=true            # Comprimir backups (recomendado)
BACKUP_PREFIX=backup               # Prefixo dos arquivos

# Agendamento (cron)
BACKUP_TIME=0 2 * * *             # Todo dia às 2h da manhã
RUN_ON_START=false                # Fazer backup ao iniciar container

# Timezone
TZ=America/Sao_Paulo

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AVANÇADO (raramente necessário)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Para bancos grandes (> 50GB)
MYSQLDUMP_TIMEOUT=21600           # 6 horas
ENABLE_AUTO_CHUNKING=true         # Divide tabelas grandes
CHUNK_SIZE=50000                  # Registros por chunk

# Notificações (opcional)
ENABLE_EMAIL_NOTIFICATIONS=false
WEBHOOK_URL=                      # Slack/Discord/Teams
```

---

## 📖 Exemplos de Uso Completos

### Cenário 1: Backup Simples Diário

```bash
# 1. Configure apenas o necessário no .env
SOURCE_HOST=meu_servidor.com
DB_USERNAME=root
DB_PASSWORD=senha123
DATABASES=loja_online,estoque
BACKUP_TIME=0 3 * * *  # Todo dia às 3h

# 2. Inicie
docker-compose up -d

# 3. Pronto! Backups automáticos às 3h da manhã
```

### Cenário 2: Backup + Restauração Automática

```bash
# 1. Configure origem E destino no .env
SOURCE_HOST=servidor_producao.com
DEST_HOST=servidor_homologacao.com
DATABASES=app_production

# 2. Execute
docker exec bee-backup backup restore

# Resultado: Backup feito E restaurado no servidor de homologação!
```

### Cenário 3: Backup de Todos os Bancos

```bash
# Não precisa listar os bancos no DATABASES
# Apenas execute:
docker exec bee-backup backup full

# Resultado: Todos os bancos (exceto sistema) são salvos!
```

### Cenário 4: Restaurar Backup Específico

```bash
# 1. Liste os backups
docker exec bee-backup list

# 2. Escolha e restaure
docker exec bee-backup restore /backups/backup_loja_20251117_140530.sql.gz
```

---

## 🔧 Permissões do MySQL

### No Servidor de Origem (backup)

```sql
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'sua_senha';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER 
ON *.* TO 'backup_user'@'%';
FLUSH PRIVILEGES;
```

### No Servidor de Destino (restore)

```sql
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'sua_senha';
GRANT ALL PRIVILEGES ON *.* TO 'backup_user'@'%';
FLUSH PRIVILEGES;
```

---

## 📊 Monitoramento

### Ver logs em tempo real

```bash
docker logs -f bee-backup
```

### Ver logs específicos

```bash
# Logs de backup
docker exec bee-backup tail -f /logs/backup.log

# Logs de restore
docker exec bee-backup tail -f /logs/restore.log
```

### Verificar espaço em disco

```bash
docker exec bee-backup df -h
docker exec bee-backup du -sh /backups
```

---

## 🏗️ Estrutura dos Backups

Os backups são salvos no formato:

```
/backups/
├── backup_banco1_20251117_140530.sql.gz
├── backup_banco2_20251117_140530.sql.gz
└── backup_banco3_20251117_140530.sql.gz
```

**Formato:** `backup_<nome_banco>_<YYYYMMDD>_<HHMMSS>.sql.gz`

---

## 🔥 Casos de Uso Especiais

### Backup de Banco Muito Grande (200GB+)

Configure no `.env`:

```env
ENABLE_AUTO_CHUNKING=true
CHUNK_SIZE=50000
MYSQLDUMP_TIMEOUT=21600
MYSQLDUMP_OPTIONS=--single-transaction --quick --hex-blob
```

### Backup para Arquivo Local (sem Docker)

```bash
# Copie o backup para seu computador
docker cp bee-backup:/backups/backup_meudb.sql.gz ./
```

### Restaurar em Servidor Diferente

```bash
# Use IP customizado
docker exec bee-backup bash -c \
  "/scripts/restore_backup.sh /backups/backup.sql.gz meudb 10.0.1.50:3307"
```

---

## 🆘 Troubleshooting

### ❌ Erro: "Access denied"

**Solução:** Verifique as permissões do usuário MySQL (veja seção "Permissões")

### ❌ Erro: "Can't connect to MySQL server"

**Solução:**
```bash
# Teste a conexão
docker exec bee-backup test

# Verifique se o servidor está acessível
docker exec bee-backup ping -c 3 SEU_SERVIDOR
```

### ❌ Backup muito lento

**Solução:** Para bancos grandes, use chunking:
```env
ENABLE_AUTO_CHUNKING=true
```

### ❌ Espaço em disco cheio

**Solução:**
```bash
# Limpar backups antigos
docker exec bee-backup clean

# Ou manualmente
docker exec bee-backup find /backups -mtime +7 -delete
```

---

## 🐳 Docker Compose

O `docker-compose.yml` já está configurado. Apenas ajuste volumes se necessário:

```yaml
version: '3.8'

services:
  bee-backup:
    build: .
    container_name: bee-backup
    env_file: .env
    volumes:
      - ./backups:/backups
      - ./logs:/logs
    restart: unless-stopped
```

---

## 📅 Exemplos de Agendamento (Cron)

```env
# Todo dia às 2h da manhã
BACKUP_TIME=0 2 * * *

# A cada 6 horas
BACKUP_TIME=0 */6 * * *

# Segunda a sexta às 3h30
BACKUP_TIME=30 3 * * 1-5

# Todo domingo à meia-noite
BACKUP_TIME=0 0 * * 0
```

---

## 🎯 Resumo dos Comandos

| Comando | O que faz |
|---------|-----------|
| `backup` | Backup dos bancos do .env |
| `backup full` | Backup de TODOS os bancos |
| `backup restore` | Backup + restaura no destino |
| `restore` | Restaura bancos do .env |
| `restore full` | Restaura todos os backups |
| `list` | Lista backups disponíveis |
| `test` | Testa conexão com servidores |
| `clean` | Remove backups antigos |

---

## 📞 Suporte

- 📧 Email: contato@beecoffee.com.br
- 🐛 Issues: [GitHub Issues](https://github.com/seu-repo/bee-backup-mysql)
- 📖 Docs: Este README é a documentação completa!

---

## 📜 Licença

MIT License - Use à vontade! 🐝

---

<p align="center">
  <strong>🐝 Bee Backup - Backup nunca foi tão simples! 🍯</strong>
</p>
