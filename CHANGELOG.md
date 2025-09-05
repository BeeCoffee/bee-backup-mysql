# 📋 CHANGELOG - Backup Bee MySQL

Todas as mudanças importantes deste projeto serão documentadas neste arquivo.

O formato é baseado em [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-09-05

### 🔧 Fixed
- Corrigido erro crítico `ERROR 2026 (HY000): TLS/SSL error: SSL is required, but the server does not support it`
- Resolvido problema de conectividade com servidores MariaDB/MySQL que não suportam SSL
- Corrigida inconsistência nas configurações entre scripts de backup
- Eliminados arquivos de configuração temporários desnecessários

### ⚡ Changed  
- Implementado `MYSQL_CLIENT_OPTIONS=--ssl=0` em todos os scripts para consistência
- Simplificada função `database_exists` para usar configurações padronizadas
- Removidas configurações não suportadas pelo MariaDB client (`net-read-timeout`, `net-write-timeout`)
- Otimizado processo de testes de conectividade no `entrypoint.sh`

### 🚀 Improved
- Performance aprimorada com redução de overhead de configuração
- Logs mais limpos sem avisos de configurações não suportadas  
- Compatibilidade total com MariaDB Server e MySQL Server
- Estabilidade aumentada nos testes de conectividade

### 📦 Technical Details
- **Scripts modificados**: `entrypoint.sh`, `backup.sh`, `healthcheck.sh`, `manual_backup.sh`, `optimize_large_db.sh`
- **Linhas de código reduzidas**: 70 linhas removidas, 27 adicionadas
- **Arquivos de configuração**: Simplificação e padronização

---

## [1.1.0] - 2025-09-04

### 🆕 Added
- Suporte completo para databases grandes (>200GB)
- Sistema de retry automático para falhas de conexão
- Configurações otimizadas para diferentes tamanhos de database
- Scripts de otimização e análise (`optimize_large_db.sh`)
- Monitoramento avançado com `monitor_backup.sh`

### 🔧 Fixed
- Corrigidos erros 'unknown variable' do mysqldump em produção
- Melhorada compatibilidade com diferentes versões MySQL/MariaDB
- Corrigidas configurações de timeout para databases grandes

### ⚡ Changed
- Otimizações significativas para backup de databases volumosos
- Configurações de timeout ajustáveis por tamanho de database
- Sistema de logging em 5 etapas mais detalhado

---

## [1.0.0] - 2025-08-30

### 🎉 Initial Release
- Sistema completo de backup automatizado MariaDB/MySQL
- Agendamento via cron configurável
- Modo dual: "Somente Backup" e "Backup + Restauração"
- Compressão gzip opcional
- Sistema de notificações (Email/Webhook)
- Healthcheck integrado
- Scripts utilitários completos
- Documentação detalhada

### ✨ Features
- **Backup Automático**: Agendamento flexível via expressões cron
- **Restauração Automática**: Sincronização entre servidores
- **Notificações**: Suporte a SMTP e webhooks (Slack/Discord/Teams)  
- **Monitoramento**: Healthcheck e logs estruturados
- **Segurança**: Execução com usuário não-root
- **Flexibilidade**: Configuração via variáveis de ambiente

---

## Tipos de Mudanças

- `🆕 Added` para novas funcionalidades
- `⚡ Changed` para mudanças em funcionalidades existentes  
- `🔧 Fixed` para correções de bugs
- `🚀 Improved` para melhorias de performance
- `🗑️ Removed` para funcionalidades removidas
- `🔒 Security` para correções de segurança
- `📦 Technical` para mudanças técnicas internas

---

## Como Contribuir

1. Fork o projeto
2. Crie sua feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## Versionamento

- **MAJOR**: Mudanças incompatíveis na API
- **MINOR**: Adição de funcionalidade de forma compatível
- **PATCH**: Correções de bug compatíveis

---

**🐝 Backup Bee - Sistema de Backup MySQL/MariaDB**
