#!/bin/bash

# Configuração do Servidor de Origem (PostgreSQL 13)
# ATENÇÃO: Configure estas informações antes de executar o dump
SOURCE_HOST="10.0.0.94"              # IP do servidor de origem
SOURCE_PORT="5432"                   # Porta do PostgreSQL (padrão: 5432)
SOURCE_DB="gisdb"                    # Nome da base de dados a migrar
SOURCE_USER="gisadmin"               # Usuário com permissão de leitura
SOURCE_PASSWORD="gisadmin"                   # IMPORTANTE: Atualize com a senha real
SOURCE_POSTGRES_VERSION="13"
SOURCE_POSTGRES_HOME="/usr/lib/postgresql/13"

# Configuração do Ambiente de Destino
TARGET_HOST="localhost"
TARGET_PORT="5432"
TARGET_DB="gisdb"
TARGET_USER="postgres"
TARGET_PASSWORD=""  # Deixe vazio se usar autenticação peer/trust local
TARGET_POSTGRES_VERSION="15"
TARGET_POSTGRES_HOME="/usr/lib/postgresql/15"
TARGET_DATA_DIR="/mnt/banco/pg15"

# Configuração de Backup
# IMPORTANTE: O dump será gerado diretamente no servidor de destino
# Partição dedicada ao backup (984GB)
BACKUP_DIR="/mnt/backuprestore"
GLOBALS_BACKUP="${BACKUP_DIR}/globals.sql"
DB_BACKUP_DIR="${BACKUP_DIR}/gisdb_dump_dir"
BACKUP_JOBS="10"  # Número de jobs paralelos para pg_dump/pg_restore

# Configuração de Backup Remoto (se necessário fazer backup local no servidor de origem)
# Deixe vazio se quiser gerar o dump diretamente no servidor de destino
LOCAL_BACKUP_DIR=""  # Exemplo: "/tmp/backup_local" para backup temporário no servidor de origem

# Configuração do ST_Geometry
ST_GEOMETRY_PATH="/caminho/para/st_geometry.so"  # Atualize com o caminho real após o download

# Configuração de Locale
LOCALE="pt_BR.UTF-8"

# Configuração do PostgreSQL (postgresql.conf)
PG_SHARED_BUFFERS="10GB"
PG_EFFECTIVE_CACHE_SIZE="30GB"
PG_MAINTENANCE_WORK_MEM="2GB"
PG_WORK_MEM="64MB"
PG_WAL_BUFFERS="16MB"
PG_MIN_WAL_SIZE="2GB"
PG_MAX_WAL_SIZE="8GB"
PG_CHECKPOINT_COMPLETION_TARGET="0.9"
PG_RANDOM_PAGE_COST="1.0"
PG_EFFECTIVE_IO_CONCURRENCY="200"
PG_MAX_PARALLEL_WORKERS=$(nproc)  # Usa o número de núcleos de CPU disponíveis
PG_MAX_PARALLEL_WORKERS_PER_GATHER="4"
PG_MAX_PARALLEL_MAINTENANCE_WORKERS="2"

# Configuração de Logs
LOG_DIR="$(pwd)/logs"
MIGRATION_LOG="${LOG_DIR}/migration_$(date +%Y%m%d_%H%M%S).log"

# Função para logging
log_message() {
  local message="$1"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] $message" | tee -a "$MIGRATION_LOG"
}

# Verificar se o diretório de logs existe, se não, criá-lo
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR"
fi

# Exportar todas as variáveis para uso em outros scripts
export SOURCE_HOST SOURCE_PORT SOURCE_DB SOURCE_USER SOURCE_PASSWORD SOURCE_POSTGRES_VERSION SOURCE_POSTGRES_HOME
export TARGET_HOST TARGET_PORT TARGET_DB TARGET_USER TARGET_PASSWORD TARGET_POSTGRES_VERSION TARGET_POSTGRES_HOME TARGET_DATA_DIR
export BACKUP_DIR GLOBALS_BACKUP DB_BACKUP_DIR BACKUP_JOBS
export ST_GEOMETRY_PATH
export LOCALE
export PG_SHARED_BUFFERS PG_EFFECTIVE_CACHE_SIZE PG_MAINTENANCE_WORK_MEM PG_WORK_MEM PG_WAL_BUFFERS
export PG_MIN_WAL_SIZE PG_MAX_WAL_SIZE PG_CHECKPOINT_COMPLETION_TARGET PG_RANDOM_PAGE_COST PG_EFFECTIVE_IO_CONCURRENCY
export PG_MAX_PARALLEL_WORKERS PG_MAX_PARALLEL_WORKERS_PER_GATHER PG_MAX_PARALLEL_MAINTENANCE_WORKERS
export LOG_DIR MIGRATION_LOG

# Exibir mensagem de configuração carregada
log_message "Configuração de migração carregada com sucesso."
