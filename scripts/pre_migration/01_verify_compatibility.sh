#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando verificação de compatibilidade..."

# Verificar se a biblioteca ST_Geometry existe
if [ ! -f "$ST_GEOMETRY_PATH" ]; then
    log_message "ERRO: Biblioteca ST_Geometry não encontrada em $ST_GEOMETRY_PATH"
    log_message "Por favor, baixe a biblioteca ST_Geometry compatível com PostgreSQL 15 do portal My Esri"
    log_message "e atualize o caminho em config/migration_config.sh"
    exit 1
else
    log_message "Biblioteca ST_Geometry encontrada em $ST_GEOMETRY_PATH"
fi

# Verificar conexão com o servidor de origem
log_message "Verificando conexão com o servidor de origem..."
if PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "SELECT version();" > /dev/null 2>&1; then
    log_message "Conexão com o servidor de origem estabelecida com sucesso"
    
    # Obter a versão exata do PostgreSQL
    PG_VERSION=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT version();" | grep -oP 'PostgreSQL \K[0-9]+\.[0-9]+')
    log_message "Versão do PostgreSQL de origem: $PG_VERSION"
    
    # Verificar se o PostGIS está instalado
    if PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT PostGIS_Full_Version();" > /dev/null 2>&1; then
        POSTGIS_VERSION=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT PostGIS_Full_Version();" | head -1)
        log_message "Versão do PostGIS de origem: $POSTGIS_VERSION"
    else
        log_message "AVISO: PostGIS não parece estar instalado na base de dados de origem"
    fi
    
    # Verificar se o tipo ST_Geometry está disponível
    if PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT count(*) FROM pg_type WHERE typname = 'st_geometry';" | grep -q "1"; then
        log_message "Tipo ST_Geometry encontrado na base de dados de origem"
    else
        log_message "AVISO: Tipo ST_Geometry não encontrado na base de dados de origem. Verifique se esta é realmente uma geodatabase ArcGIS."
    fi
else
    log_message "ERRO: Não foi possível conectar ao servidor de origem"
    exit 1
fi

# Verificar se o PostgreSQL 15 está instalado no servidor de destino
if command -v /usr/lib/postgresql/15/bin/psql > /dev/null 2>&1; then
    log_message "PostgreSQL 15 encontrado no servidor de destino"
    
    # Verificar se o serviço está em execução
    if systemctl is-active --quiet postgresql@15-main; then
        log_message "Serviço PostgreSQL 15 está em execução"
    else
        log_message "AVISO: Serviço PostgreSQL 15 não está em execução"
    fi
else
    log_message "ERRO: PostgreSQL 15 não encontrado no servidor de destino"
    log_message "Por favor, instale o PostgreSQL 15 seguindo as instruções na documentação"
    exit 1
fi

# Verificar se o PostGIS está instalado no PostgreSQL 15
if sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "CREATE DATABASE postgis_check;" > /dev/null 2>&1; then
    if sudo -u postgres /usr/lib/postgresql/15/bin/psql -d postgis_check -t -c "CREATE EXTENSION postgis;" > /dev/null 2>&1; then
        POSTGIS_VERSION=$(sudo -u postgres /usr/lib/postgresql/15/bin/psql -d postgis_check -t -c "SELECT PostGIS_Full_Version();" | head -1)
        log_message "PostGIS instalado no PostgreSQL 15: $POSTGIS_VERSION"
        sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "DROP DATABASE postgis_check;" > /dev/null 2>&1
    else
        log_message "ERRO: PostGIS não está instalado no PostgreSQL 15"
        sudo -u postgres /usr/lib/postgresql/15/bin/psql -t -c "DROP DATABASE postgis_check;" > /dev/null 2>&1
        log_message "Por favor, instale o PostGIS 3.x para PostgreSQL 15"
        exit 1
    fi
else
    log_message "ERRO: Não foi possível criar banco de dados de teste no PostgreSQL 15"
    exit 1
fi

# Verificar espaço em disco disponível para backup
BACKUP_DISK=$(df -h $BACKUP_DIR | awk 'NR==2 {print $4}')
log_message "Espaço em disco disponível para backup: $BACKUP_DISK"

# Obter o tamanho da base de dados de origem
DB_SIZE=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SELECT pg_size_pretty(pg_database_size('$SOURCE_DB'));" | tr -d ' ')
log_message "Tamanho da base de dados de origem: $DB_SIZE"

log_message "Verificação de compatibilidade concluída com sucesso"
exit 0
