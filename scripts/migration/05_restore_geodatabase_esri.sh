#!/bin/bash

# Determinar o diretório base do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Carrega a configuração
source "$BASE_DIR/config/migration_config.sh"

log_message "====================================================="
log_message "RESTAURAÇÃO DE GEODATABASE ARCGIS - MÉTODO ESRI"
log_message "====================================================="
log_message "Este script segue a documentação oficial da Esri"
log_message "IMPORTANTE: Restauração em 3 etapas:"
log_message "1. Restaurar objetos globais"
log_message "2. Restaurar schemas PUBLIC e SDE PRIMEIRO"
log_message "3. Restaurar os demais schemas"
log_message "====================================================="

read -p "Deseja continuar? (s/n): " CONFIRM
if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    log_message "Operação cancelada"
    exit 1
fi

# ETAPA 1: PREPARAR AMBIENTE
log_message ""
log_message "=== ETAPA 1: PREPARAR O AMBIENTE ==="

log_message "Dropando base $TARGET_DB se existir..."
psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -c "DROP DATABASE IF EXISTS $TARGET_DB;"

log_message "Criando base $TARGET_DB..."
psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER << EOF
CREATE DATABASE $TARGET_DB WITH ENCODING='UTF8' OWNER=$TARGET_USER;
EOF

log_message "Criando schema SDE..."
psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB << EOF
CREATE SCHEMA IF NOT EXISTS sde AUTHORIZATION $TARGET_USER;
GRANT USAGE ON SCHEMA sde TO PUBLIC;
ALTER DATABASE $TARGET_DB SET SEARCH_PATH="\$user",public,sde;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
EOF

# ETAPA 2: RESTAURAR OBJETOS GLOBAIS
log_message ""
log_message "=== ETAPA 2: RESTAURAR OBJETOS GLOBAIS ==="

if [ -f "$GLOBALS_BACKUP" ]; then
    psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -f "$GLOBALS_BACKUP" 2>&1 | tee "${LOG_DIR}/restore_globals.log"
fi

# ETAPA 3: RESTAURAR PUBLIC E SDE PRIMEIRO!
log_message ""
log_message "=== ETAPA 3: RESTAURAR SCHEMAS PUBLIC E SDE (PRIMEIRO!) ==="

START_TIME=$(date +%s)

log_message "Restaurando schema PUBLIC..."
${TARGET_POSTGRES_HOME}/bin/pg_restore --verbose \
    --host=$TARGET_HOST \
    --port=$TARGET_PORT \
    --username=$TARGET_USER \
    --dbname=$TARGET_DB \
    --schema=public \
    $DB_BACKUP_DIR 2>&1 | tee "${LOG_DIR}/restore_public.log"

log_message "Restaurando schema SDE..."
${TARGET_POSTGRES_HOME}/bin/pg_restore --verbose \
    --host=$TARGET_HOST \
    --port=$TARGET_PORT \
    --username=$TARGET_USER \
    --dbname=$TARGET_DB \
    --schema=sde \
    $DB_BACKUP_DIR 2>&1 | tee "${LOG_DIR}/restore_sde.log"

# Verificar spatial_references
log_message "Verificando sde.spatial_references..."
psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "SELECT count(*) FROM sde.spatial_references WHERE srid = 4674;"

# ETAPA 4: RESTAURAR DEMAIS SCHEMAS
log_message ""
log_message "=== ETAPA 4: RESTAURAR OS DEMAIS SCHEMAS ===" 

log_message "Restaurando schemas restantes com $BACKUP_JOBS jobs..."
${TARGET_POSTGRES_HOME}/bin/pg_restore --verbose \
    --host=$TARGET_HOST \
    --port=$TARGET_PORT \
    --username=$TARGET_USER \
    --dbname=$TARGET_DB \
    --jobs=$BACKUP_JOBS \
    --exclude-schema=public \
    --exclude-schema=sde \
    $DB_BACKUP_DIR 2>&1 | tee "${LOG_DIR}/restore_remaining.log"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
HOURS=$((DURATION / 3600))
MINUTES=$(( (DURATION % 3600) / 60 ))
SECONDS=$((DURATION % 60))

# VERIFICAÇÃO FINAL
log_message ""
log_message "=== VERIFICAÇÃO FINAL ==="

TABLE_COUNT=$(psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" | tr -d ' ')
SDE_COUNT=$(psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "SELECT count(*) FROM pg_tables WHERE schemaname = 'sde';" | tr -d ' ')
DB_SIZE=$(psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "SELECT pg_size_pretty(pg_database_size('$TARGET_DB'));" | tr -d ' ')

log_message "====================================================="
log_message "RESTAURAÇÃO CONCLUÍDA!"
log_message "Tempo: ${HOURS}h ${MINUTES}m ${SECONDS}s"
log_message "Total de tabelas: $TABLE_COUNT"
log_message "Tabelas SDE: $SDE_COUNT"
log_message "Tamanho: $DB_SIZE"
log_message "====================================================="
