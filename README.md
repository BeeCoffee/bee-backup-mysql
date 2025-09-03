# 🐝 Backup Bee - Sistema Completo de Backup MariaDB/MySQL

![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-003545?style=for-the-badge&logo=mariadb&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Alpine Linux](https://img.shields.io/badge/Alpine%20Linux-0D597F?style=for-the-badge&logo=alpine-linux&logoColor=white)

Sistema automatizado de backup para MariaDB/MySQL usando Docker, com agendamento via cron, compressão, notificações e monitoramento integrado.

## 🎯 Características

### ✨ Funcionalidades Principais

- **🕐 Agendamento Flexível**: Configuração via cron com suporte a expressões customizadas
- **🗜️ Compressão Inteligente**: Compressão gzip opcional para economizar espaço
- **🔄 Backup Seletivo**: Backup apenas dos databases especificados
- **📧 Notificações**: Suporte a email (SMTP) e webhooks (Slack/Discord/Teams)
- **🏥 Healthcheck**: Monitoramento automático da saúde do sistema
- **🔒 Segurança**: Execução com usuário não-root e validações robustas
- **📊 Logs Estruturados**: Logs detalhados com timestamp e níveis
- **🧹 Limpeza Automática**: Remoção automática de backups antigos

### 🛠️ Funcionalidades Avançadas

- **💾 Backup de Segurança**: Backup automático antes de restaurações
- **🔍 Verificação de Integridade**: Validação automática dos backups criados
- **📈 Estatísticas Detalhadas**: Relatórios completos de backup
- **🎯 Restauração Flexível**: Suporte a arquivos .sql e .sql.gz
- **🖥️ Interface de Linha de Comando**: Scripts utilitários para gerenciamento
- **🌐 Multi-servidor**: Suporte a servidores de origem e destino diferentes

## 📁 Estrutura do Projeto

```
backup-bee/
├── 📄 Dockerfile                    # Imagem Docker baseada em Alpine
├── 📄 docker-compose.yml           # Orquestração do serviço
├── 📄 .env                         # Configurações de ambiente
├── 📄 entrypoint.sh                # Script de inicialização
├── 📄 README.md                    # Esta documentação
└── scripts/                       # Scripts utilitários
    ├── 📄 backup.sh                # Script principal de backup
    ├── 📄 healthcheck.sh           # Verificação de saúde
    ├── 📄 manual_backup.sh         # Backup manual seletivo
    ├── 📄 restore_backup.sh        # Restauração de backups
    ├── 📄 list_backups.sh          # Listagem de backups
    ├── 📄 send_email.sh            # Notificações por email
    └── 📄 send_webhook.sh          # Notificações via webhook
```

## 🚀 Guia de Configuração

### 1. Preparação do Ambiente

```bash
# Clonar ou criar o projeto
mkdir backup-bee && cd backup-bee

# Criar diretórios necessários
mkdir -p backups logs config scripts
```

### 2. Configuração do .env

Edite o arquivo `.env` com suas configurações:

```env
# Servidores de banco de dados
SOURCE_HOST=10.0.0.13              # Servidor de origem
SOURCE_PORT=3306
DEST_HOST=10.0.1.12                # Servidor de destino
DEST_PORT=3306

# Credenciais
DB_USERNAME=backup_user
DB_PASSWORD=sua_senha_aqui

# Databases para backup (separados por vírgula)
DATABASES=loja_online,sistema_vendas,controle_estoque,financeiro

# Agendamento (formato cron)
BACKUP_TIME=0 2 * * *              # Todo dia às 02:00

# Configurações de backup
RETENTION_DAYS=7                   # Manter por 7 dias
BACKUP_COMPRESSION=true            # Ativar compressão
BACKUP_PREFIX=backup               # Prefixo dos arquivos

# Timezone
TZ=America/Sao_Paulo

# Notificações (opcional)
ENABLE_EMAIL_NOTIFICATIONS=false
EMAIL_FROM=backup@empresa.com
EMAIL_TO=admin@empresa.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587

# Webhook (opcional)
WEBHOOK_URL=                       # URL do Slack/Discord/Teams
```

### 3. Configuração dos Usuários MySQL

Crie um usuário específico para backup nos servidores MySQL/MariaDB:

```sql
-- No servidor de origem
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'sua_senha_aqui';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup_user'@'%';

-- No servidor de destino
CREATE USER 'backup_user'@'%' IDENTIFIED BY 'sua_senha_aqui';
GRANT ALL PRIVILEGES ON *.* TO 'backup_user'@'%';
FLUSH PRIVILEGES;
```

### 4. Build e Execução

```bash
# Build da imagem
docker-compose build

# Testar conectividade
docker-compose run --rm mariadb-backup test

# Iniciar em modo agendado
docker-compose up -d
```

## 📖 Exemplos de Uso

### 🔄 Operações Básicas

```bash
# Iniciar sistema em modo agendado
docker-compose up -d

# Ver logs em tempo real
docker-compose logs -f

# Verificar status do container
docker-compose ps

# Parar o sistema
docker-compose down
```

### 💾 Backups Manuais

```bash
# Backup de databases específicos
docker exec mariadb_backup_scheduler /scripts/manual_backup.sh loja_online financeiro

# Backup de todos os databases configurados
docker exec mariadb_backup_scheduler /scripts/manual_backup.sh --all

# Listar databases disponíveis
docker exec mariadb_backup_scheduler /scripts/manual_backup.sh --list
```

### 📋 Gerenciamento de Backups

```bash
# Listar todos os backups
docker exec mariadb_backup_scheduler /scripts/list_backups.sh

# Backups recentes (24h)
docker exec mariadb_backup_scheduler /scripts/list_backups.sh --recent

# Filtrar por database
docker exec mariadb_backup_scheduler /scripts/list_backups.sh --database loja_online

# Resumo estatístico
docker exec mariadb_backup_scheduler /scripts/list_backups.sh --summary

# Saída em JSON
docker exec mariadb_backup_scheduler /scripts/list_backups.sh --json
```

### 🔄 Restauração de Backups

```bash
# Restaurar no servidor de destino (padrão)
docker exec mariadb_backup_scheduler /scripts/restore_backup.sh \
    /backups/backup_loja_20240903_140530.sql.gz loja_online

# Restaurar no servidor de origem
docker exec mariadb_backup_scheduler /scripts/restore_backup.sh \
    /backups/backup_loja_20240903_140530.sql.gz loja_online source

# Listar backups disponíveis para restauração
docker exec mariadb_backup_scheduler /scripts/restore_backup.sh --list
```

### 🏥 Monitoramento e Diagnóstico

```bash
# Verificar saúde do sistema
docker exec mariadb_backup_scheduler /scripts/healthcheck.sh

# Testar conectividade
docker-compose run --rm mariadb-backup test

# Acessar shell interativo
docker exec -it mariadb_backup_scheduler bash

# Ver logs específicos
docker exec mariadb_backup_scheduler tail -f /logs/backup.log
docker exec mariadb_backup_scheduler tail -f /logs/entrypoint.log
```

### 📧 Teste de Notificações

```bash
# Testar notificação por email
docker exec mariadb_backup_scheduler /scripts/send_email.sh test "Teste de email"

# Testar webhook
docker exec mariadb_backup_scheduler /scripts/send_webhook.sh test
```

## ⚙️ Configurações Avançadas

### 🕐 Expressões Cron Personalizadas

```env
# Exemplos de agendamento
BACKUP_TIME=0 2 * * *        # Todo dia às 02:00
BACKUP_TIME=0 */6 * * *      # A cada 6 horas
BACKUP_TIME=0 0 * * 0        # Todo domingo à meia-noite
BACKUP_TIME=30 3 * * 1-5     # Seg-Sex às 03:30
BACKUP_TIME=0 1,13 * * *     # Todo dia às 01:00 e 13:00
```

### 🗜️ Opções do mysqldump

```env
# Configuração completa para produção
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4 --hex-blob --complete-insert

# Para databases pequenos
MYSQLDUMP_OPTIONS=--complete-insert --extended-insert

# Para databases grandes
MYSQLDUMP_OPTIONS=--single-transaction --quick --hex-blob
```

### 📧 Configuração de Email Avançada

```env
# Gmail/Google Workspace
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USE_TLS=true
SMTP_USERNAME=backup@empresa.com
SMTP_PASSWORD=senha_app_especifica

# Outlook/Office 365
SMTP_SERVER=smtp-mail.outlook.com
SMTP_PORT=587
SMTP_USE_TLS=true

# Servidor SMTP customizado
SMTP_SERVER=mail.empresa.com
SMTP_PORT=25
SMTP_USE_TLS=false
```

### 🌐 Configuração de Webhooks

```bash
# Slack
WEBHOOK_URL=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX

# Discord
WEBHOOK_URL=https://discord.com/api/webhooks/000000000000000000/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Microsoft Teams
WEBHOOK_URL=https://empresa.webhook.office.com/webhookb2/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx@xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/IncomingWebhook/yyyyyyyyyyyyyyyyyyyyyyyyyyyyyy/zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz
```

## 🔧 Comandos Úteis

### 📊 Monitoramento

```bash
# Status dos containers
docker-compose ps

# Recursos utilizados
docker stats mariadb_backup_scheduler

# Logs com timestamp
docker-compose logs -t

# Logs das últimas 100 linhas
docker-compose logs --tail=100

# Seguir logs de um script específico
docker exec mariadb_backup_scheduler tail -f /logs/backup.log
```

### 🗄️ Gerenciamento de Dados

```bash
# Tamanho dos diretórios
docker exec mariadb_backup_scheduler du -sh /backups /logs

# Espaço livre
docker exec mariadb_backup_scheduler df -h

# Limpar logs antigos manualmente
docker exec mariadb_backup_scheduler find /logs -name "*.log" -mtime +30 -delete

# Verificar permissões
docker exec mariadb_backup_scheduler ls -la /backups /logs
```

### 🔄 Backup e Restauração

```bash
# Backup dos dados do container (volumes)
docker run --rm -v backup-bee_backups:/data -v $(pwd):/backup alpine tar czf /backup/backups.tar.gz -C /data .

# Restaurar dados do container
docker run --rm -v backup-bee_backups:/data -v $(pwd):/backup alpine tar xzf /backup/backups.tar.gz -C /data

# Copiar arquivo específico do container
docker cp mariadb_backup_scheduler:/backups/backup_loja_20240903.sql.gz ./
```

## 🚨 Troubleshooting

### ❌ Problemas Comuns

#### Erro de Conectividade

```bash
# Verificar conectividade de rede
docker exec mariadb_backup_scheduler ping -c 3 10.0.0.13

# Testar conexão MySQL manualmente
docker exec mariadb_backup_scheduler mysql -h10.0.0.13 -P3306 -ubackup_user -p

# Verificar logs de erro
docker exec mariadb_backup_scheduler grep ERROR /logs/*.log
```

#### Problemas de Permissão

```bash
# Verificar usuário atual
docker exec mariadb_backup_scheduler whoami

# Verificar permissões dos diretórios
docker exec mariadb_backup_scheduler ls -la /backups /logs

# Corrigir permissões se necessário
docker exec --user root mariadb_backup_scheduler chown -R backup:backup /backups /logs
```

#### Espaço em Disco Insuficiente

```bash
# Verificar espaço disponível
docker exec mariadb_backup_scheduler df -h

# Listar arquivos grandes
docker exec mariadb_backup_scheduler find /backups -size +100M -exec ls -lh {} \\;

# Limpeza manual de backups antigos
docker exec mariadb_backup_scheduler find /backups -name "*.sql*" -mtime +7 -delete
```

#### Problemas de Cron

```bash
# Verificar se crond está rodando
docker exec mariadb_backup_scheduler pgrep crond

# Ver configuração do cron
docker exec mariadb_backup_scheduler crontab -l

# Logs do cron
docker exec mariadb_backup_scheduler grep CRON /var/log/messages
```

### 🔍 Logs de Debugging

```bash
# Ativar logs de debug no .env
ENABLE_DEBUG_LOGS=true
LOG_LEVEL=DEBUG

# Rebuild e restart
docker-compose down
docker-compose up --build -d

# Verificar logs detalhados
docker-compose logs -f
```

### 🆘 Recuperação de Emergência

```bash
# Backup manual urgente
docker exec mariadb_backup_scheduler /scripts/manual_backup.sh --all

# Parar agendamento temporariamente
docker exec mariadb_backup_scheduler killall crond

# Restaurar backup mais recente
LATEST=$(docker exec mariadb_backup_scheduler ls -t /backups/*.sql.gz | head -1)
docker exec mariadb_backup_scheduler /scripts/restore_backup.sh "$LATEST" nome_database

# Reset completo do sistema
docker-compose down -v
docker-compose up --build -d
```

## 📋 Integração com Proxmox CT

### Configuração de Container LXC

```bash
# Criar container LXC no Proxmox
pct create 200 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \\
  --memory 1024 --cores 2 --rootfs local-lvm:8 \\
  --net0 name=eth0,bridge=vmbr0,ip=10.0.1.100/24,gw=10.0.1.1 \\
  --hostname backup-mysql

# Iniciar container
pct start 200

# Entrar no container
pct enter 200

# Instalar Docker
apt update
apt install -y docker.io docker-compose git

# Clonar projeto
git clone <repositorio> /opt/backup-bee
cd /opt/backup-bee

# Configurar e iniciar
cp .env.example .env
# ... editar configurações ...
docker-compose up -d
```

### Script de Automação para Proxmox

```bash
#!/bin/bash
# Script: setup-backup-ct.sh
# Automação completa para Proxmox

CTID=200
TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
STORAGE="local-lvm"
MEMORY=1024
CORES=2
DISK_SIZE=20
NETWORK="name=eth0,bridge=vmbr0,ip=10.0.1.100/24,gw=10.0.1.1"

# Criar container
pct create $CTID $TEMPLATE \\
  --memory $MEMORY --cores $CORES \\
  --rootfs $STORAGE:$DISK_SIZE \\
  --net0 $NETWORK \\
  --hostname backup-mysql \\
  --unprivileged 1

# Configurar container
pct set $CTID --features nesting=1

# Iniciar
pct start $CTID

# Aguardar inicialização
sleep 30

# Setup automático
pct exec $CTID -- bash -c "
  apt update && apt install -y docker.io docker-compose git
  systemctl enable docker
  cd /opt
  git clone https://github.com/empresa/backup-bee.git
  cd backup-bee
  cp .env.example .env
  echo 'Container configurado! Edite /opt/backup-bee/.env e execute docker-compose up -d'
"

echo "Container $CTID criado e configurado com sucesso!"
echo "Acesse com: pct enter $CTID"
echo "Projeto em: /opt/backup-bee"
```

## 📈 Métricas e Monitoramento

### Integração com Prometheus

```yaml
# docker-compose.override.yml
version: '3.8'
services:
  mariadb-backup:
    labels:
      - "prometheus.io/scrape=true"
      - "prometheus.io/port=9090"
    ports:
      - "9090:9090"
```

### Alertas de Monitoramento

```bash
# Script para verificação externa
#!/bin/bash
# check-backup-health.sh

CONTAINER="mariadb_backup_scheduler"
WEBHOOK="https://hooks.slack.com/services/..."

# Verificar se container está rodando
if ! docker ps | grep -q $CONTAINER; then
    curl -X POST -H 'Content-type: application/json' \\
        --data '{"text":"🚨 Container de backup parado!"}' \\
        $WEBHOOK
    exit 1
fi

# Verificar healthcheck
if ! docker inspect $CONTAINER | grep -q '"Health":{"Status":"healthy"'; then
    curl -X POST -H 'Content-type: application/json' \\
        --data '{"text":"🚨 Healthcheck do backup falhando!"}' \\
        $WEBHOOK
    exit 1
fi

echo "✅ Sistema de backup funcionando normalmente"
```

## 🤝 Contribuição

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📜 Licença

Este projeto está licenciado sob a licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 🆘 Suporte

- 📧 Email: contato@beecoffee.com.br

---

<p align="center">
  <strong>🐝 Backup Bee - Seu sistema de backup nunca foi tão doce! 🍯</strong>
</p>
