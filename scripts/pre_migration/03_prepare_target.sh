#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando preparação do ambiente de destino..."

# Verificar se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERRO: Este script deve ser executado como root"
    log_message "Por favor, execute com sudo: sudo $0"
    exit 1
fi

# Verificar se o PostgreSQL 15 está instalado
if ! command -v /usr/lib/postgresql/15/bin/psql &> /dev/null; then
    log_message "ERRO: PostgreSQL 15 não está instalado no servidor de destino"
    log_message "Por favor, instale o PostgreSQL 15 antes de continuar"
    exit 1
else
    log_message "PostgreSQL 15 encontrado no servidor de destino"
    
    # Verificar a versão exata
    PG_VERSION=$(sudo -u postgres /usr/lib/postgresql/15/bin/psql --version | grep -oP 'PostgreSQL \K[0-9]+\.[0-9]+')
    log_message "Versão do PostgreSQL instalada: $PG_VERSION"
fi

# Verificar se o PostGIS está instalado
log_message "Verificando se o PostGIS está instalado..."
if sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "CREATE DATABASE postgis_check_temp;" > /dev/null 2>&1; then
    if sudo -u postgres /usr/lib/postgresql/15/bin/psql -d postgis_check_temp -t -c "CREATE EXTENSION postgis;" > /dev/null 2>&1; then
        POSTGIS_VERSION=$(sudo -u postgres /usr/lib/postgresql/15/bin/psql -d postgis_check_temp -t -c "SELECT PostGIS_Full_Version();" | head -1)
        log_message "PostGIS instalado: $POSTGIS_VERSION"
        sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "DROP DATABASE postgis_check_temp;" > /dev/null 2>&1
    else
        log_message "AVISO: PostGIS não está instalado no PostgreSQL 15"
        log_message "Se a geodatabase usar PostGIS, instale-o com: apt-get install postgresql-15-postgis-3"
        sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "DROP DATABASE postgis_check_temp;" > /dev/null 2>&1
    fi
else
    log_message "AVISO: Não foi possível criar banco de dados de teste no PostgreSQL 15"
fi

# Configurar o locale
log_message "Configurando locale para $LOCALE..."
if ! locale -a | grep -q "$LOCALE"; then
    localedef -i pt_BR -f UTF-8 pt_BR.UTF-8
    log_message "Locale $LOCALE criado"
else
    log_message "Locale $LOCALE já está disponível"
fi

# Verificar se o serviço PostgreSQL está em execução
log_message "Verificando status do serviço PostgreSQL..."
if systemctl is-active --quiet postgresql; then
    log_message "Serviço PostgreSQL está em execução"
    
    # Perguntar se deseja parar o serviço para ajustes de configuração
    read -p "Deseja parar o serviço PostgreSQL para ajustes de configuração? (s/n): " STOP_SERVICE
    if [ "$STOP_SERVICE" = "s" ] || [ "$STOP_SERVICE" = "S" ]; then
        log_message "Parando o serviço PostgreSQL..."
        systemctl stop postgresql
        log_message "Serviço PostgreSQL parado"
        SERVICE_WAS_STOPPED=true
    else
        SERVICE_WAS_STOPPED=false
    fi
else
    log_message "Serviço PostgreSQL não está em execução"
    SERVICE_WAS_STOPPED=false
fi

# Verificar o diretório de dados atual
log_message "Verificando diretório de dados do PostgreSQL..."
CURRENT_DATA_DIR=$(sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "SHOW data_directory;" 2>/dev/null | tr -d ' ')
if [ -n "$CURRENT_DATA_DIR" ]; then
    log_message "Diretório de dados atual: $CURRENT_DATA_DIR"
    
    if [ "$CURRENT_DATA_DIR" != "$TARGET_DATA_DIR" ]; then
        log_message "AVISO: O diretório de dados atual ($CURRENT_DATA_DIR) é diferente do configurado ($TARGET_DATA_DIR)"
        log_message "Se desejar mudar o diretório de dados, faça isso manualmente antes de continuar"
    fi
else
    log_message "Não foi possível determinar o diretório de dados atual"
fi

# Atualizar o arquivo postgresql.conf
log_message "Atualizando postgresql.conf..."
PG_CONF_FILE="/etc/postgresql/15/main/postgresql.conf"

# Criar backup do arquivo de configuração original
cp "$PG_CONF_FILE" "${PG_CONF_FILE}.bak"

# Atualizar configurações
cat > "$PG_CONF_FILE" << EOF
# Arquivo de configuração do PostgreSQL 15
# Gerado automaticamente pelo script de migração

# Configurações de conexão
listen_addresses = '*'
port = 5432
max_connections = 100

# Diretório de dados
data_directory = '$TARGET_DATA_DIR'

# Memória
shared_buffers = $PG_SHARED_BUFFERS
effective_cache_size = $PG_EFFECTIVE_CACHE_SIZE
maintenance_work_mem = $PG_MAINTENANCE_WORK_MEM
work_mem = $PG_WORK_MEM
wal_buffers = $PG_WAL_BUFFERS

# WAL (Write-Ahead Log)
min_wal_size = $PG_MIN_WAL_SIZE
max_wal_size = $PG_MAX_WAL_SIZE
checkpoint_completion_target = $PG_CHECKPOINT_COMPLETION_TARGET

# Planejador de consultas
random_page_cost = $PG_RANDOM_PAGE_COST
effective_io_concurrency = $PG_EFFECTIVE_IO_CONCURRENCY

# Paralelismo
max_worker_processes = $PG_MAX_PARALLEL_WORKERS
max_parallel_workers = $PG_MAX_PARALLEL_WORKERS
max_parallel_workers_per_gather = $PG_MAX_PARALLEL_WORKERS_PER_GATHER
max_parallel_maintenance_workers = $PG_MAX_PARALLEL_MAINTENANCE_WORKERS

# Autovacuum
autovacuum = on
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.02

# Locale
lc_messages = '$LOCALE'
lc_monetary = '$LOCALE'
lc_numeric = '$LOCALE'
lc_time = '$LOCALE'

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_truncate_on_rotation = off
log_rotation_age = 1d
log_rotation_size = 100MB
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'America/Sao_Paulo'

# Outras configurações
timezone = 'America/Sao_Paulo'
huge_pages = try
EOF

log_message "postgresql.conf atualizado com sucesso"

# Atualizar o arquivo pg_hba.conf
log_message "Atualizando pg_hba.conf..."
PG_HBA_FILE="/etc/postgresql/15/main/pg_hba.conf"

# Criar backup do arquivo de configuração original
cp "$PG_HBA_FILE" "${PG_HBA_FILE}.bak"

# Atualizar configurações
cat > "$PG_HBA_FILE" << EOF
# Arquivo pg_hba.conf do PostgreSQL 15
# Gerado automaticamente pelo script de migração

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Conexões locais para administração
local   all             postgres                                peer
local   all             all                                     peer

# Conexões IPv4 locais
host    all             all             127.0.0.1/32            scram-sha-256

# Conexões IPv6 locais
host    all             all             ::1/128                 scram-sha-256

# Permitir conexões de qualquer endereço (altere para sua sub-rede específica em produção)
host    all             all             0.0.0.0/0               scram-sha-256
EOF

log_message "pg_hba.conf atualizado com sucesso"

# Copiar a biblioteca ST_Geometry para o diretório de bibliotecas do PostgreSQL
log_message "Copiando biblioteca ST_Geometry..."
if [ -f "$ST_GEOMETRY_PATH" ]; then
    PG_LIB_DIR=$(/usr/lib/postgresql/15/bin/pg_config --pkglibdir)
    cp "$ST_GEOMETRY_PATH" "$PG_LIB_DIR/"
    chown postgres:postgres "$PG_LIB_DIR/$(basename $ST_GEOMETRY_PATH)"
    log_message "Biblioteca ST_Geometry copiada para $PG_LIB_DIR/"
else
    log_message "ERRO: Biblioteca ST_Geometry não encontrada em $ST_GEOMETRY_PATH"
    log_message "Por favor, baixe a biblioteca ST_Geometry compatível com PostgreSQL 15 do portal My Esri"
    log_message "e atualize o caminho em config/migration_config.sh"
fi

# Reiniciar o serviço PostgreSQL se foi parado
if [ "$SERVICE_WAS_STOPPED" = true ]; then
    log_message "Reiniciando o serviço PostgreSQL..."
    systemctl start postgresql
    log_message "Serviço PostgreSQL reiniciado"
fi

# Garantir que o serviço está habilitado para iniciar automaticamente
log_message "Habilitando serviço PostgreSQL para iniciar automaticamente..."
systemctl enable postgresql

# Verificar se o serviço está em execução
if systemctl is-active --quiet postgresql; then
    log_message "Serviço PostgreSQL está em execução"
else
    log_message "ERRO: Não foi possível iniciar o serviço PostgreSQL"
    log_message "Verifique os logs do sistema: journalctl -xe"
    exit 1
fi

# Verificar conexão com o servidor de destino
log_message "Verificando conexão com o servidor de destino..."
if sudo -u postgres psql -c "SELECT version();" > /dev/null 2>&1; then
    log_message "Conexão com o servidor de destino estabelecida com sucesso"
    
    # Obter a versão exata do PostgreSQL
    PG_VERSION=$(sudo -u postgres psql -t -c "SELECT version();" | grep -oP 'PostgreSQL \K[0-9]+\.[0-9]+')
    log_message "Versão do PostgreSQL de destino: $PG_VERSION"
else
    log_message "ERRO: Não foi possível conectar ao servidor de destino"
    exit 1
fi

log_message "Preparação do ambiente de destino concluída com sucesso"
exit 0
