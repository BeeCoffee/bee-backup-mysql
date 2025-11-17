# 🚀 Início Rápido - Bee Backup

## ⚡ 3 Passos para Começar

### 1️⃣ Configure o `.env`

```bash
cp .env.example .env
nano .env
```

Edite apenas estas linhas:

```env
SOURCE_HOST=192.168.1.100    # Servidor com os bancos
DB_USERNAME=root
DB_PASSWORD=sua_senha
DATABASES=banco1,banco2      # Bancos para backup
```

### 2️⃣ Inicie o Container

```bash
docker-compose up -d
```

### 3️⃣ Use!

```bash
# Fazer backup
docker exec bee-backup backup

# Ver backups
docker exec bee-backup list

# Restaurar
docker exec bee-backup restore
```

---

## 📋 Comandos Mais Usados

```bash
# BACKUP
docker exec bee-backup backup              # Backup dos bancos do .env
docker exec bee-backup backup full         # Backup de TODOS os bancos
docker exec bee-backup backup restore      # Backup + restaura no destino

# RESTORE
docker exec bee-backup restore             # Restaura bancos do .env
docker exec bee-backup restore full        # Restaura todos os backups
docker exec bee-backup restore <arquivo>   # Restaura backup específico

# GERENCIAMENTO
docker exec bee-backup list                # Lista backups
docker exec bee-backup test                # Testa conexão
docker exec bee-backup clean               # Remove backups antigos
```

---

## ❓ Perguntas Frequentes

### Como fazer backup de todos os bancos?

```bash
docker exec bee-backup backup full
```

### Como restaurar um backup específico?

```bash
# 1. Listar backups
docker exec bee-backup list

# 2. Restaurar
docker exec bee-backup restore /backups/backup_meudb_20251117.sql.gz
```

### Como restaurar em servidor diferente?

Configure `DEST_HOST` no `.env` ou use IP customizado:

```bash
docker exec bee-backup bash -c \
  "/scripts/restore_backup.sh /backups/backup.sql.gz meudb 10.0.1.50:3307"
```

### Como fazer backup e restaurar automaticamente?

```bash
# Configure DEST_HOST no .env
DEST_HOST=192.168.1.200

# Execute
docker exec bee-backup backup restore
```

### Como ver os logs?

```bash
docker logs -f bee-backup
```

---

## 🔧 Permissões MySQL

### Servidor de Origem (backup)

```sql
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'senha';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup_user'@'%';
FLUSH PRIVILEGES;
```

### Servidor de Destino (restore)

```sql
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'senha';
GRANT ALL PRIVILEGES ON *.* TO 'backup_user'@'%';
FLUSH PRIVILEGES;
```

---

## 📖 Documentação Completa

Veja o [README.md](README.md) para documentação completa.

---

**🐝 É só isso! Simples assim.**

