#!/bin/bash
# Wrapper para redirecionar comandos para bee-backup.sh

# Obter o nome do comando (basename do script)
CMD_NAME=$(basename "$0")

# Mapear comandos
case "$CMD_NAME" in
    "backup")
        exec /bee-backup.sh backup "$@"
        ;;
    "restore")
        exec /bee-backup.sh restore "$@"
        ;;
    "list")
        exec /bee-backup.sh list
        ;;
    "test-connection")
        exec /bee-backup.sh test
        ;;
    "clean")
        exec /bee-backup.sh clean
        ;;
    "wrapper.sh")
        # Chamado diretamente
        exec /bee-backup.sh "$@"
        ;;
    *)
        exec /bee-backup.sh "$@"
        ;;
esac

