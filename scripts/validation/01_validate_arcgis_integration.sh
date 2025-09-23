#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando validação da integração com ArcGIS..."

# Criar diretório para resultados da validação
VALIDATION_DIR="${LOG_DIR}/validation_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$VALIDATION_DIR"
log_message "Resultados da validação serão salvos em $VALIDATION_DIR"

# Verificar conexão com o servidor de destino
log_message "Verificando conexão com o servidor de destino..."
if ! PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "ERRO: Não foi possível conectar à base de dados $TARGET_DB"
    exit 1
fi

# Verificar se o tipo ST_Geometry está disponível
log_message "Verificando se o tipo ST_Geometry está disponível..."
ST_GEOMETRY_CHECK=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT count(*) 
    FROM pg_type 
    WHERE typname = 'st_geometry';" | tr -d ' ')

if [ "$ST_GEOMETRY_CHECK" -eq "1" ]; then
    log_message "Tipo ST_Geometry está disponível"
else
    log_message "ERRO: Tipo ST_Geometry não está disponível"
    log_message "Verifique se a biblioteca ST_Geometry foi corretamente instalada"
    exit 1
fi

# Verificar se o PostGIS está instalado e funcionando
log_message "Verificando se o PostGIS está instalado e funcionando..."
POSTGIS_VERSION=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT PostGIS_Full_Version();" | head -1)

if [ -n "$POSTGIS_VERSION" ]; then
    log_message "PostGIS está instalado e funcionando: $POSTGIS_VERSION"
else
    log_message "ERRO: PostGIS não está instalado ou não está funcionando corretamente"
    exit 1
fi

# Verificar se as tabelas do sistema da geodatabase estão presentes
log_message "Verificando se as tabelas do sistema da geodatabase estão presentes..."
SDE_TABLES=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT string_agg(tablename, ', ')
    FROM pg_tables
    WHERE schemaname = 'sde'
    ORDER BY tablename;")

if [ -n "$SDE_TABLES" ]; then
    log_message "Tabelas do sistema da geodatabase encontradas: $SDE_TABLES"
    echo "$SDE_TABLES" > "${VALIDATION_DIR}/sde_tables.txt"
else
    log_message "AVISO: Nenhuma tabela do sistema da geodatabase foi encontrada"
    log_message "Verifique se esta é realmente uma geodatabase ArcGIS"
fi

# Verificar tabelas registradas na geodatabase
log_message "Verificando tabelas registradas na geodatabase..."
REGISTERED_TABLES=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT count(*)
    FROM sde.sde_table_registry;" 2>/dev/null | tr -d ' ')

if [ -n "$REGISTERED_TABLES" ] && [ "$REGISTERED_TABLES" -gt 0 ]; then
    log_message "Número de tabelas registradas na geodatabase: $REGISTERED_TABLES"
    
    # Obter detalhes das tabelas registradas
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
        SELECT owner, registration_id, table_name
        FROM sde.sde_table_registry
        ORDER BY owner, table_name;" > "${VALIDATION_DIR}/registered_tables.txt"
else
    log_message "AVISO: Nenhuma tabela registrada na geodatabase foi encontrada"
fi

# Verificar tabelas espaciais
log_message "Verificando tabelas espaciais..."
SPATIAL_TABLES=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT count(*)
    FROM geometry_columns;" | tr -d ' ')

if [ -n "$SPATIAL_TABLES" ] && [ "$SPATIAL_TABLES" -gt 0 ]; then
    log_message "Número de tabelas espaciais: $SPATIAL_TABLES"
    
    # Obter detalhes das tabelas espaciais
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
        SELECT f_table_schema, f_table_name, f_geometry_column, srid, type
        FROM geometry_columns
        ORDER BY f_table_schema, f_table_name;" > "${VALIDATION_DIR}/spatial_tables.txt"
else
    log_message "AVISO: Nenhuma tabela espacial foi encontrada"
fi

# Verificar índices espaciais
log_message "Verificando índices espaciais..."
SPATIAL_INDEXES=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT count(*)
    FROM pg_indexes
    WHERE indexdef LIKE '%gist%';" | tr -d ' ')

if [ -n "$SPATIAL_INDEXES" ] && [ "$SPATIAL_INDEXES" -gt 0 ]; then
    log_message "Número de índices espaciais: $SPATIAL_INDEXES"
    
    # Obter detalhes dos índices espaciais
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
        SELECT schemaname, tablename, indexname, indexdef
        FROM pg_indexes
        WHERE indexdef LIKE '%gist%'
        ORDER BY schemaname, tablename;" > "${VALIDATION_DIR}/spatial_indexes.txt"
else
    log_message "AVISO: Nenhum índice espacial foi encontrado"
fi

# Verificar versões da geodatabase
log_message "Verificando versões da geodatabase..."
VERSIONS_CHECK=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT count(*)
    FROM sde.sde_versions;" 2>/dev/null | tr -d ' ')

if [ -n "$VERSIONS_CHECK" ] && [ "$VERSIONS_CHECK" -gt 0 ]; then
    log_message "Número de versões da geodatabase: $VERSIONS_CHECK"
    
    # Obter detalhes das versões
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
        SELECT owner, name, parent_name, description
        FROM sde.sde_versions
        ORDER BY owner, name;" > "${VALIDATION_DIR}/versions.txt"
else
    log_message "AVISO: Nenhuma versão da geodatabase foi encontrada ou a geodatabase não é versionada"
fi

# Criar lista de verificações para integração com ArcGIS
cat > "${VALIDATION_DIR}/arcgis_integration_checklist.txt" << EOF
=== Lista de Verificações para Integração com ArcGIS ===

1. Conexão com ArcGIS Pro:
   [ ] Criar uma nova conexão de banco de dados no ArcGIS Pro
   [ ] Verificar se todas as tabelas e feature classes são visíveis
   [ ] Verificar se é possível visualizar os dados espaciais no mapa
   [ ] Verificar se é possível editar os dados (se aplicável)

2. Conexão com ArcGIS Server:
   [ ] Registrar a conexão de banco de dados no ArcGIS Server Manager
   [ ] Verificar se o ArcGIS Server consegue acessar os dados
   [ ] Publicar um serviço de mapa de teste
   [ ] Publicar um serviço de feições de teste (se aplicável)
   [ ] Verificar se os serviços estão funcionando corretamente

3. Funcionalidades da Geodatabase:
   [ ] Verificar se as relações entre tabelas estão funcionando
   [ ] Verificar se os domínios estão funcionando
   [ ] Verificar se as regras de topologia estão funcionando (se aplicável)
   [ ] Verificar se o versionamento está funcionando (se aplicável)

4. Desempenho:
   [ ] Verificar o tempo de carregamento de mapas
   [ ] Verificar o tempo de resposta de consultas espaciais
   [ ] Comparar o desempenho com o sistema anterior
EOF

log_message "Lista de verificações para integração com ArcGIS criada em ${VALIDATION_DIR}/arcgis_integration_checklist.txt"

# Criar script para testar uma consulta espacial simples
cat > "${VALIDATION_DIR}/test_spatial_query.sql" << EOF
-- Script para testar uma consulta espacial simples
-- Execute este script para verificar se as consultas espaciais estão funcionando corretamente

-- Selecionar uma tabela espacial para teste
SELECT f_table_schema, f_table_name, f_geometry_column
FROM geometry_columns
LIMIT 1;

-- Substitua 'schema_name', 'table_name' e 'geom_column' pelos valores retornados acima
-- SELECT count(*) FROM schema_name.table_name;
-- SELECT ST_AsText(geom_column) FROM schema_name.table_name LIMIT 5;
-- SELECT ST_GeometryType(geom_column) FROM schema_name.table_name LIMIT 1;
EOF

log_message "Script para testar consulta espacial criado em ${VALIDATION_DIR}/test_spatial_query.sql"

# Criar relatório de validação
VALIDATION_REPORT="${VALIDATION_DIR}/validation_report.txt"
{
    echo "=== Relatório de Validação de Integração com ArcGIS ==="
    echo "Data: $(date)"
    echo "Servidor: $TARGET_HOST"
    echo "Base de dados: $TARGET_DB"
    echo ""
    
    echo "=== Resultados da Validação ==="
    echo "Tipo ST_Geometry disponível: $([ "$ST_GEOMETRY_CHECK" -eq "1" ] && echo "Sim" || echo "Não")"
    echo "PostGIS instalado: $([ -n "$POSTGIS_VERSION" ] && echo "Sim" || echo "Não")"
    echo "Versão do PostGIS: $POSTGIS_VERSION"
    echo "Tabelas do sistema da geodatabase: $([ -n "$SDE_TABLES" ] && echo "Encontradas" || echo "Não encontradas")"
    echo "Número de tabelas registradas: $REGISTERED_TABLES"
    echo "Número de tabelas espaciais: $SPATIAL_TABLES"
    echo "Número de índices espaciais: $SPATIAL_INDEXES"
    echo "Número de versões da geodatabase: $VERSIONS_CHECK"
    
    echo ""
    echo "=== Próximos Passos ==="
    echo "1. Siga a lista de verificações em ${VALIDATION_DIR}/arcgis_integration_checklist.txt"
    echo "2. Execute consultas de teste usando o script ${VALIDATION_DIR}/test_spatial_query.sql"
    echo "3. Verifique se todos os serviços ArcGIS estão funcionando corretamente"
    echo "4. Compare o desempenho com o sistema anterior"
} > "$VALIDATION_REPORT"

log_message "Relatório de validação salvo em $VALIDATION_REPORT"
log_message "Validação da integração com ArcGIS concluída"

exit 0
