#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando exportação da base de dados..."

# Verificar se o diretório de backup existe
if [ ! -d "$BACKUP_DIR" ]; then
    log_message "Criando diretório de backup $BACKUP_DIR..."
    mkdir -p "$BACKUP_DIR"
    log_message "Diretório de backup criado"
fi

# Verificar espaço em disco disponível
log_message "Verificando espaço em disco disponível..."
DISK_SPACE=$(df -h $BACKUP_DIR | awk 'NR==2 {print $4}')
log_message "Espaço em disco disponível: $DISK_SPACE"

# Obter tamanho da base de dados
log_message "Obtendo tamanho da base de dados $SOURCE_DB..."
DB_SIZE=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT pg_size_pretty(pg_database_size('$SOURCE_DB'));" | tr -d ' ')
log_message "Tamanho da base de dados: $DB_SIZE"

# Verificar se o diretório de backup já existe
if [ -d "$DB_BACKUP_DIR" ]; then
    log_message "AVISO: Diretório de backup $DB_BACKUP_DIR já existe"
    read -p "Deseja sobrescrever o backup existente? (s/n): " OVERWRITE
    if [ "$OVERWRITE" = "s" ] || [ "$OVERWRITE" = "S" ]; then
        log_message "Removendo backup existente..."
        rm -rf "$DB_BACKUP_DIR"
    else
        log_message "Operação cancelada pelo usuário"
        exit 1
    fi
fi

# Criar diretório para o backup se não existir
if [ ! -d "$DB_BACKUP_DIR" ]; then
    log_message "Criando diretório para o backup da base de dados..."
    mkdir -p "$DB_BACKUP_DIR"
fi

# Exportar objetos globais (roles, tablespaces)
log_message "Exportando objetos globais (roles, tablespaces)..."
log_message "Comando: ${TARGET_POSTGRES_HOME}/bin/pg_dumpall --globals-only --host=$SOURCE_HOST --port=$SOURCE_PORT --username=$SOURCE_USER -f $GLOBALS_BACKUP"

PGPASSWORD=$SOURCE_PASSWORD ${TARGET_POSTGRES_HOME}/bin/pg_dumpall --globals-only --host=$SOURCE_HOST --port=$SOURCE_PORT --username=$SOURCE_USER -f $GLOBALS_BACKUP

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao exportar objetos globais"
    exit 1
else
    log_message "Objetos globais exportados com sucesso para $GLOBALS_BACKUP"
fi

# Exportar a base de dados principal
log_message "Exportando base de dados $SOURCE_DB..."
log_message "Comando: ${TARGET_POSTGRES_HOME}/bin/pg_dump --verbose --host=$SOURCE_HOST --port=$SOURCE_PORT --username=$SOURCE_USER -j $BACKUP_JOBS --format=d --encoding=UTF-8 --create --file=$DB_BACKUP_DIR $SOURCE_DB"

START_TIME=$(date +%s)

PGPASSWORD=$SOURCE_PASSWORD ${TARGET_POSTGRES_HOME}/bin/pg_dump --verbose \
    --host=$SOURCE_HOST \
    --port=$SOURCE_PORT \
    --username=$SOURCE_USER \
    -j $BACKUP_JOBS \
    --format=d \
    --encoding=UTF-8 \
    --create \
    --file=$DB_BACKUP_DIR \
    $SOURCE_DB

RESULT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Formatar a duração em horas, minutos e segundos
HOURS=$((DURATION / 3600))
MINUTES=$(( (DURATION % 3600) / 60 ))
SECONDS=$((DURATION % 60))

if [ $RESULT -ne 0 ]; then
    log_message "ERRO: Falha ao exportar a base de dados $SOURCE_DB"
    exit 1
else
    log_message "Base de dados $SOURCE_DB exportada com sucesso para $DB_BACKUP_DIR"
    log_message "Tempo de exportação: ${HOURS}h ${MINUTES}m ${SECONDS}s"
fi

# Verificar o tamanho do backup
BACKUP_SIZE=$(du -sh $DB_BACKUP_DIR | awk '{print $1}')
log_message "Tamanho do backup: $BACKUP_SIZE"

# Verificar se todos os arquivos foram criados
log_message "Verificando integridade do backup..."
if [ ! -f "$GLOBALS_BACKUP" ]; then
    log_message "ERRO: Arquivo de backup de objetos globais não encontrado"
    exit 1
fi

if [ ! -f "$DB_BACKUP_DIR/toc.dat" ]; then
    log_message "ERRO: Arquivo toc.dat não encontrado no diretório de backup"
    exit 1
fi

# Criar arquivo de metadados do backup
METADATA_FILE="${BACKUP_DIR}/backup_metadata.txt"
{
    echo "=== Metadados do Backup ==="
    echo "Data: $(date)"
    echo "Servidor de origem: $SOURCE_HOST"
    echo "Base de dados: $SOURCE_DB"
    echo "Tamanho da base de dados: $DB_SIZE"
    echo "Tamanho do backup: $BACKUP_SIZE"
    echo "Tempo de exportação: ${HOURS}h ${MINUTES}m ${SECONDS}s"
    echo "Versão do PostgreSQL de origem: $(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT version();" | tr -d '\n')"
    echo "Versão do PostgreSQL de destino: $(${TARGET_POSTGRES_HOME}/bin/psql --version | head -1)"
    echo "Comando de exportação: pg_dump --verbose --host=$SOURCE_HOST --port=$SOURCE_PORT --username=<user> -j $BACKUP_JOBS --format=d --encoding=UTF-8 --create --file=$DB_BACKUP_DIR $SOURCE_DB"
    echo "Arquivos de backup:"
    echo "- Objetos globais: $GLOBALS_BACKUP"
    echo "- Base de dados: $DB_BACKUP_DIR"
} > "$METADATA_FILE"

log_message "Metadados do backup salvos em $METADATA_FILE"
log_message "Exportação da base de dados concluída com sucesso"

exit 0
