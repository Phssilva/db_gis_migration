#!/bin/bash

# Determinar o diretório base do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Carrega a configuração
source "$BASE_DIR/config/migration_config.sh"

log_message "Iniciando importação da base de dados para o PostgreSQL 15..."

# Verificar se os arquivos de backup existem
if [ ! -f "$GLOBALS_BACKUP" ]; then
    log_message "ERRO: Arquivo de backup de objetos globais não encontrado em $GLOBALS_BACKUP"
    exit 1
fi

if [ ! -d "$DB_BACKUP_DIR" ] || [ ! -f "$DB_BACKUP_DIR/toc.dat" ]; then
    log_message "ERRO: Diretório de backup da base de dados não encontrado ou inválido em $DB_BACKUP_DIR"
    exit 1
fi

# Verificar se a biblioteca ST_Geometry está no lugar correto
PG_LIB_DIR=$(/usr/lib/postgresql/15/bin/pg_config --pkglibdir)
ST_GEOMETRY_TARGET="${PG_LIB_DIR}/st_geometry.so"

if [ ! -f "$ST_GEOMETRY_TARGET" ]; then
    log_message "AVISO: Biblioteca ST_Geometry não encontrada em $ST_GEOMETRY_TARGET"
    
    if [ -f "$ST_GEOMETRY_PATH" ]; then
        log_message "Copiando biblioteca ST_Geometry para $PG_LIB_DIR..."
        sudo cp "$ST_GEOMETRY_PATH" "$ST_GEOMETRY_TARGET"
        sudo chown postgres:postgres "$ST_GEOMETRY_TARGET"
        log_message "Biblioteca ST_Geometry copiada com sucesso"
    else
        log_message "ERRO: Biblioteca ST_Geometry não encontrada em $ST_GEOMETRY_PATH"
        log_message "A restauração pode falhar se a base de dados contiver objetos que dependem do tipo ST_Geometry"
        read -p "Deseja continuar mesmo assim? (s/n): " CONTINUE
        if [ "$CONTINUE" != "s" ] && [ "$CONTINUE" != "S" ]; then
            log_message "Operação cancelada pelo usuário"
            exit 1
        fi
    fi
fi

# Restaurar objetos globais
log_message "Restaurando objetos globais (roles, tablespaces)..."
sudo -u postgres psql -f "$GLOBALS_BACKUP"

if [ $? -ne 0 ]; then
    log_message "AVISO: Ocorreram erros ao restaurar objetos globais"
    log_message "Isso pode ser normal se os roles já existirem no sistema de destino"
    log_message "Verifique os erros acima e determine se são aceitáveis"
    read -p "Deseja continuar com a restauração da base de dados? (s/n): " CONTINUE
    if [ "$CONTINUE" != "s" ] && [ "$CONTINUE" != "S" ]; then
        log_message "Operação cancelada pelo usuário"
        exit 1
    fi
else
    log_message "Objetos globais restaurados com sucesso"
fi

# Restaurar a base de dados
log_message "Restaurando base de dados $SOURCE_DB..."
log_message "Comando: ${TARGET_POSTGRES_HOME}/bin/pg_restore --verbose --host=$TARGET_HOST --port=$TARGET_PORT --username=$TARGET_USER --jobs=$BACKUP_JOBS --dbname=postgres $DB_BACKUP_DIR"

START_TIME=$(date +%s)

# Usar a opção --create para criar a base de dados automaticamente
PGPASSWORD=$TARGET_PASSWORD ${TARGET_POSTGRES_HOME}/bin/pg_restore --verbose \
    --host=$TARGET_HOST \
    --port=$TARGET_PORT \
    --username=$TARGET_USER \
    --jobs=$BACKUP_JOBS \
    --dbname=postgres \
    $DB_BACKUP_DIR > "${LOG_DIR}/restore_output.log" 2>&1

RESULT=$?
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Formatar a duração em horas, minutos e segundos
HOURS=$((DURATION / 3600))
MINUTES=$(( (DURATION % 3600) / 60 ))
SECONDS=$((DURATION % 60))

# Verificar se houve erros na restauração
if [ $RESULT -ne 0 ]; then
    log_message "AVISO: Ocorreram erros durante a restauração da base de dados"
    log_message "Verifique o arquivo de log ${LOG_DIR}/restore_output.log para mais detalhes"
    
    # Contar o número de erros no log
    ERROR_COUNT=$(grep -c "ERROR:" "${LOG_DIR}/restore_output.log")
    log_message "Número de erros encontrados: $ERROR_COUNT"
    
    # Mostrar os primeiros erros
    log_message "Primeiros erros encontrados:"
    grep "ERROR:" "${LOG_DIR}/restore_output.log" | head -5
    
    log_message "A restauração foi concluída com erros, mas a base de dados pode estar utilizável"
    log_message "Tempo de restauração: ${HOURS}h ${MINUTES}m ${SECONDS}s"
else
    log_message "Base de dados $SOURCE_DB restaurada com sucesso"
    log_message "Tempo de restauração: ${HOURS}h ${MINUTES}m ${SECONDS}s"
fi

# Verificar se a base de dados foi criada
log_message "Verificando se a base de dados $TARGET_DB foi criada..."
if PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -lqt | cut -d \| -f 1 | grep -qw $TARGET_DB; then
    log_message "Base de dados $TARGET_DB criada com sucesso"
else
    log_message "ERRO: Base de dados $TARGET_DB não foi criada"
    exit 1
fi

# Verificar se as tabelas foram criadas
log_message "Verificando se as tabelas foram criadas..."
TABLE_COUNT=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" | tr -d ' ')
log_message "Número de tabelas criadas: $TABLE_COUNT"

if [ "$TABLE_COUNT" -eq 0 ]; then
    log_message "ERRO: Nenhuma tabela foi criada na base de dados"
    exit 1
fi

# Verificar se as tabelas do sistema da geodatabase foram criadas
log_message "Verificando se as tabelas do sistema da geodatabase foram criadas..."
SDE_TABLE_COUNT=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'sde';" | tr -d ' ')
log_message "Número de tabelas SDE criadas: $SDE_TABLE_COUNT"

if [ "$SDE_TABLE_COUNT" -eq 0 ]; then
    log_message "AVISO: Nenhuma tabela SDE foi encontrada. Verifique se esta é realmente uma geodatabase ArcGIS."
fi

# Criar arquivo de metadados da restauração
METADATA_FILE="${LOG_DIR}/restore_metadata.txt"
{
    echo "=== Metadados da Restauração ==="
    echo "Data: $(date)"
    echo "Servidor de destino: $TARGET_HOST"
    echo "Base de dados: $TARGET_DB"
    echo "Tempo de restauração: ${HOURS}h ${MINUTES}m ${SECONDS}s"
    echo "Número de tabelas criadas: $TABLE_COUNT"
    echo "Número de tabelas SDE criadas: $SDE_TABLE_COUNT"
    echo "Comando de restauração: pg_restore --verbose --host=$TARGET_HOST --port=$TARGET_PORT --username=<user> --jobs=$BACKUP_JOBS --dbname=postgres $DB_BACKUP_DIR"
} > "$METADATA_FILE"

log_message "Metadados da restauração salvos em $METADATA_FILE"
log_message "Importação da base de dados concluída"

exit 0
