#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando auditoria do ambiente de origem..."

# Criar diretório para armazenar os resultados da auditoria
AUDIT_DIR="${LOG_DIR}/audit_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$AUDIT_DIR"
log_message "Resultados da auditoria serão salvos em $AUDIT_DIR"

# Função para executar comandos SQL no servidor de origem
run_sql() {
    local sql="$1"
    local output_file="$2"
    PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "$sql" > "$output_file"
    if [ $? -ne 0 ]; then
        log_message "ERRO ao executar consulta: $sql"
        return 1
    fi
    return 0
}

# Obter versão do PostgreSQL
log_message "Obtendo versão do PostgreSQL..."
run_sql "SELECT version();" "${AUDIT_DIR}/postgres_version.txt"

# Obter versão do PostGIS
log_message "Obtendo versão do PostGIS..."
run_sql "SELECT PostGIS_Full_Version();" "${AUDIT_DIR}/postgis_version.txt"

# Listar todas as bases de dados
log_message "Listando todas as bases de dados..."
PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -l > "${AUDIT_DIR}/databases.txt"

# Listar todos os esquemas na base de dados
log_message "Listando esquemas na base de dados $SOURCE_DB..."
run_sql "SELECT nspname FROM pg_namespace ORDER BY nspname;" "${AUDIT_DIR}/schemas.txt"

# Listar todas as tabelas e seus tamanhos
log_message "Listando tabelas e seus tamanhos..."
run_sql "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename)) AS size 
         FROM pg_tables 
         WHERE schemaname NOT IN ('pg_catalog', 'information_schema') 
         ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC;" "${AUDIT_DIR}/tables_by_size.txt"

# Listar todas as tabelas espaciais
log_message "Listando tabelas espaciais..."
run_sql "SELECT f_table_schema, f_table_name, f_geometry_column, srid, type 
         FROM geometry_columns 
         ORDER BY f_table_schema, f_table_name;" "${AUDIT_DIR}/spatial_tables.txt"

# Listar todos os usuários (roles)
log_message "Listando usuários (roles)..."
run_sql "SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin 
         FROM pg_roles 
         ORDER BY rolname;" "${AUDIT_DIR}/roles.txt"

# Listar todas as extensões instaladas
log_message "Listando extensões instaladas..."
run_sql "SELECT extname, extversion FROM pg_extension ORDER BY extname;" "${AUDIT_DIR}/extensions.txt"

# Capturar configuração do PostgreSQL
log_message "Capturando configuração do PostgreSQL..."
run_sql "SELECT name, setting, source, context 
         FROM pg_settings 
         ORDER BY name;" "${AUDIT_DIR}/pg_settings.txt"

# Tentar obter arquivos de configuração (se for possível)
log_message "Tentando obter arquivos de configuração..."
if [ -n "$SOURCE_POSTGRES_HOME" ]; then
    # Isso só funcionará se o script estiver sendo executado no servidor de origem ou se houver acesso SSH
    if [ -f "${SOURCE_POSTGRES_HOME}/data/postgresql.conf" ]; then
        cp "${SOURCE_POSTGRES_HOME}/data/postgresql.conf" "${AUDIT_DIR}/postgresql.conf"
        log_message "Arquivo postgresql.conf copiado"
    else
        log_message "AVISO: Não foi possível acessar postgresql.conf"
    fi
    
    if [ -f "${SOURCE_POSTGRES_HOME}/data/pg_hba.conf" ]; then
        cp "${SOURCE_POSTGRES_HOME}/data/pg_hba.conf" "${AUDIT_DIR}/pg_hba.conf"
        log_message "Arquivo pg_hba.conf copiado"
    else
        log_message "AVISO: Não foi possível acessar pg_hba.conf"
    fi
else
    log_message "AVISO: SOURCE_POSTGRES_HOME não definido, não é possível obter arquivos de configuração"
fi

# Verificar tabelas do sistema da geodatabase ArcGIS
log_message "Verificando tabelas do sistema da geodatabase ArcGIS..."
run_sql "SELECT tablename FROM pg_tables WHERE schemaname = 'sde' ORDER BY tablename;" "${AUDIT_DIR}/sde_tables.txt"

# Verificar se há tabelas registradas na geodatabase
log_message "Verificando tabelas registradas na geodatabase..."
run_sql "SELECT owner, registration_id, table_name FROM sde.sde_table_registry ORDER BY owner, table_name;" "${AUDIT_DIR}/registered_tables.txt" 2>/dev/null
if [ $? -ne 0 ]; then
    log_message "AVISO: Não foi possível consultar sde.sde_table_registry. Verifique se esta é uma geodatabase ArcGIS."
fi

# Verificar índices espaciais
log_message "Verificando índices espaciais..."
run_sql "SELECT schemaname, tablename, indexname, indexdef 
         FROM pg_indexes 
         WHERE indexdef LIKE '%gist%' 
         ORDER BY schemaname, tablename;" "${AUDIT_DIR}/spatial_indexes.txt"

# Verificar tablespaces
log_message "Verificando tablespaces..."
run_sql "SELECT spcname, pg_tablespace_location(oid) 
         FROM pg_tablespace 
         ORDER BY spcname;" "${AUDIT_DIR}/tablespaces.txt"

# Criar um arquivo de resumo
log_message "Criando resumo da auditoria..."
{
    echo "=== Resumo da Auditoria ==="
    echo "Data: $(date)"
    echo "Servidor: $SOURCE_HOST"
    echo "Base de dados: $SOURCE_DB"
    echo ""
    
    echo "=== Versões ==="
    echo "PostgreSQL: $(cat ${AUDIT_DIR}/postgres_version.txt | tr -d '\n')"
    echo "PostGIS: $(head -1 ${AUDIT_DIR}/postgis_version.txt)"
    echo ""
    
    echo "=== Estatísticas ==="
    echo "Número de esquemas: $(wc -l < ${AUDIT_DIR}/schemas.txt)"
    echo "Número de tabelas espaciais: $(wc -l < ${AUDIT_DIR}/spatial_tables.txt)"
    echo "Número de usuários: $(wc -l < ${AUDIT_DIR}/roles.txt)"
    echo "Número de extensões: $(wc -l < ${AUDIT_DIR}/extensions.txt)"
    
    if [ -f "${AUDIT_DIR}/sde_tables.txt" ]; then
        echo "Número de tabelas SDE: $(wc -l < ${AUDIT_DIR}/sde_tables.txt)"
    fi
    
    if [ -f "${AUDIT_DIR}/registered_tables.txt" ]; then
        echo "Número de tabelas registradas: $(wc -l < ${AUDIT_DIR}/registered_tables.txt)"
    fi
} > "${AUDIT_DIR}/resumo.txt"

log_message "Auditoria do ambiente de origem concluída com sucesso"
log_message "Resultados disponíveis em: $AUDIT_DIR"

exit 0
