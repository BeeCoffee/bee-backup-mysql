# 🐝 Backup Bee - Sistema Completo de Backup MariaDB/MySQL

![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-003545?style=for-the-badge&logo=mariadb&logoColor=white)
![MySQL](https://img.shields.i### 🗜️ Opções do mysqldump

```bash
# Configuração completa para produção
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4 --hex-blob --complete-insert

# Para databases pequenos (< 1GB)
MYSQLDUMP_OPTIONS=--complete-insert --extended-insert

# Para databases grandes (> 5GB) - RECOMENDADO
MYSQLDUMP_OPTIONS=--routines --triggers --single-transaction --add-drop-database --default-character-set=utf8mb4 --ssl=0

# Para databases muito grandes (> 20GB)
MYSQLDUMP_OPTIONS=--single-transaction --quick --hex-blob --ssl=0

# Opções adicionais do cliente MySQL (para conectividade)
MYSQL_CLIENT_OPTIONS=--ssl=0
```

### ⏱️ Configurações de Timeout para Databases Grandes

Para databases de grande porte (10GB+), ajuste os timeouts no arquivo `.env`:

```bash
# Timeout padrão (databases pequenos)
DB_TIMEOUT=30

# Para databases médios (1-10GB)
DB_TIMEOUT=300

# Para databases grandes (10-50GB)  
DB_TIMEOUT=900

# Para databases muito grandes (50GB+)
DB_TIMEOUT=1800
```

**Sinais de que você precisa ajustar timeouts:**
- Erro: "Lost connection to server during query (2013)"
- Timeouts durante backup de tabelas grandes
- Backups que param na Etapa 1 (Extração)L-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Alpine Linux](https://img.shields.io/badge/Alpine%20Linux-0D597F?style=for-the-badge&logo=alpine-linux&logoColor=white)

Sistema automatizado de backup para MariaDB/MySQL usando Docker, com agendamento via cron, compressão, notificações e monitoramento integrado.

## 🎯 Características

### 🚀 Modos de Operação

O Backup Bee oferece dois modos de operação que são detectados automaticamente:

#### 📦 Modo "Somente Backup"
- **Ativação**: Quando `DEST_HOST` não está configurado ou está vazio
- **Funcionalidade**: Realiza apenas backup dos dados do servidor origem
- **Uso**: Ideal para backups de segurança local ou arquivamento
- **Etapas**: Extração → Compressão → Verificação → Finalização

#### 🔄 Modo "Backup + Restauração"  
- **Ativação**: Quando `DEST_HOST` está configurado com servidor válido
- **Funcionalidade**: Backup completo + restauração automática no destino
- **Uso**: Perfeito para sincronização entre servidores ou migração de dados
- **Etapas**: Extração → Compressão → Verificação → **Restauração** → Finalização

### ✨ Funcionalidades Principais

- **🕐 Agendamento Flexível**: Configuração via cron com suporte a expressões customizadas
- **🗜️ Compressão Inteligente**: Compressão gzip opcional para economizar espaço
- **🔄 Backup Seletivo**: Backup apenas dos databases especificados
- **📧 Notificações**: Suporte a email (SMTP) e webhooks (Slack/Discord/Teams)
- **🏥 Healthcheck**: Monitoramento automático da saúde do sistema
- **🔒 Segurança**: Execução com usuário não-root e validações robustas
- **📊 Logs Estruturados**: Logs detalhados com timestamp e níveis em 5 etapas
- **🧹 Limpeza Automática**: Remoção automática de backups antigos
- **🎯 Modo Condicional**: Backup apenas ou Backup + Restauração automática

### 🛠️ Funcionalidades Avançadas

- **💾 Backup de Segurança**: Backup automático antes de restaurações
- **🔍 Verificação de Integridade**: Validação automática dos backups criados
- **📈 Estatísticas Detalhadas**: Relatórios completos de backup
- **🎯 Restauração Flexível**: Suporte a arquivos .sql e .sql.gz
- **🖥️ Interface de Linha de Comando**: Scripts utilitários para gerenciamento
- **🌐 Multi-servidor**: Suporte a servidores de origem e destino diferentes
- **⏱️ Timeouts Otimizados**: Configurações específicas para databases grandes (20GB+)
- **📋 Logs Detalhados**: Sistema de logging em 5 etapas com rastreamento completo
- **🧩 Chunking Automático**: Sistema inteligente para tabelas grandes (30GB-80GB)

## 🏢 Configuração para Bancos Grandes (200GB+)

Para databases com **200GB ou mais** e tabelas individuais de **30GB-80GB**, use nossa configuração otimizada:

### 🚀 Configuração Rápida
```bash
# Usar template específico para bancos grandes
cp .env.example.large .env

# OU usar script de configuração interativa
./configure_large_db.sh
```

### 📊 Performance Esperada
- **Tempo**: 8-12 horas para 200GB
- **Chunking**: ~400-500 chunks para tabela de 80GB
- **Compressão**: ~70% redução de espaço
- **Zero Locks**: Produção sem interrupção

### 📖 Documentação Detalhada
- **Guia Completo**: [`CONFIGURACAO_BANCOS_GRANDES.md`](CONFIGURACAO_BANCOS_GRANDES.md)
- **Template Otimizado**: [`.env.example.large`](.env.example.large)
- **Script Configuração**: [`configure_large_db.sh`](configure_large_db.sh)

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

## � Sistema de Logs Detalhados

O Backup Bee implementa um sistema de logging em **5 etapas** para total visibilidade do processo:

### 🔄 Etapas do Processo

1. **🚀 [ETAPA 1/5] Extração de Dados**
   - Conexão com servidor origem
   - Execução do mysqldump
   - Cálculo do tamanho do database
   - Log: `"Iniciando extração de dados (mysqldump)..."`

2. **📦 [ETAPA 2/5] Compressão** 
   - Compressão gzip do arquivo SQL
   - Cálculo de estatísticas de compressão
   - Log: `"Iniciando compressão do arquivo..."`

3. **🔍 [ETAPA 3/5] Verificação de Integridade**
   - Validação da integridade do backup
   - Verificação de checksums
   - Log: `"Iniciando verificação de integridade..."`

4. **🔄 [ETAPA 4/5] Restauração** *(apenas no modo Backup + Restauração)*
   - Conexão com servidor destino
   - Restauração dos dados no destino
   - Log: `"Iniciando restauração no servidor destino..."`

5. **✅ [ETAPA 5/5] Finalização**
   - Limpeza de arquivos temporários
   - Envio de notificações
   - Log: `"Backup finalizado com sucesso!"`

### 📋 Exemplo de Logs

```bash
[2025-09-03 20:47:44] [INFO] 🚀 [ETAPA 1/5] Iniciando extração de dados (mysqldump)...
[2025-09-03 20:47:47] [INFO]    Tamanho do database: 21293.3 MB
[2025-09-03 20:52:15] [INFO] 📦 [ETAPA 2/5] Iniciando compressão do arquivo...
[2025-09-03 20:53:02] [INFO] 🔍 [ETAPA 3/5] Iniciando verificação de integridade...
[2025-09-03 20:53:05] [INFO] 🔄 [ETAPA 4/5] Iniciando restauração no servidor destino...
[2025-09-03 20:58:30] [INFO] ✅ [ETAPA 5/5] Backup finalizado com sucesso!
```

## �🚀 Guia de Configuração

### 1. Preparação do Ambiente

```bash
# Clonar o projeto do GitHub
git clone https://github.com/BeeCoffee/bee-backup-mysql
cd bee-backup-mysql

# Criar diretórios necessários
mkdir -p backups logs config
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
- 💬 Slack: #backup-mysql
- 📖 Wiki: [Link para documentação completa]
- 🐛 Issues: [GitHub Issues]

---

<p align="center">
  <strong>🐝 Backup Bee - Seu sistema de backup nunca foi tão doce! 🍯</strong>
</p>
