# Dockerfile para sistema de backup MariaDB/MySQL
FROM alpine:3.18

# Metadados
LABEL maintainer="Backup System"
LABEL description="Sistema completo de backup MariaDB/MySQL com agendamento"
LABEL version="1.0"

# Instalar dependências necessárias
RUN apk add --no-cache \
    mariadb-client \
    mysql-client \
    bash \
    curl \
    dcron \
    tzdata \
    ssmtp \
    gzip \
    coreutils \
    findutils

# Configurar timezone
ENV TZ=America/Sao_Paulo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Criar usuário não-root
RUN addgroup -g 1000 backup && \
    adduser -u 1000 -G backup -h /home/backup -s /bin/bash -D backup && \
    echo "backup:backup" | chpasswd

# Criar diretórios necessários
RUN mkdir -p /app /backups /logs /config /scripts && \
    chown -R backup:backup /app /backups /logs /config /scripts && \
    chmod 644 /usr/bin/crontab && \
    chmod 4755 /usr/bin/crontab

# Copiar scripts
COPY scripts/ /scripts/
COPY entrypoint.sh /app/entrypoint.sh
COPY bee-backup.sh /bee-backup.sh

# Dar permissões de execução
RUN chmod +x /app/entrypoint.sh /scripts/*.sh /bee-backup.sh && \
    chown -R backup:backup /scripts/ /app/ /bee-backup.sh

# Configurar volumes
VOLUME ["/backups", "/logs", "/config"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD /scripts/healthcheck.sh

# Diretório de trabalho
WORKDIR /app

# Entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["cron"]
