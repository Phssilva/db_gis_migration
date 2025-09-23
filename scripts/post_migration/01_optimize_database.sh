#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando otimização da base de dados após migração..."

# Verificar conexão com o servidor de destino
log_message "Verificando conexão com o servidor de destino..."
if ! PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "ERRO: Não foi possível conectar à base de dados $TARGET_DB"
    exit 1
fi

# Atualizar estatísticas do otimizador
log_message "Atualizando estatísticas do otimizador (ANALYZE VERBOSE)..."
START_TIME=$(date +%s)

PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB << EOF
\timing on
ANALYZE VERBOSE;
EOF

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_message "Estatísticas atualizadas em $DURATION segundos"

# Reindexar a base de dados
log_message "Reindexando a base de dados (REINDEX DATABASE)..."
START_TIME=$(date +%s)

PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB << EOF
\timing on
REINDEX DATABASE $TARGET_DB;
EOF

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log_message "Base de dados reindexada em $DURATION segundos"

# Executar VACUUM FULL nas tabelas principais
log_message "Executando VACUUM FULL nas tabelas principais..."

# Obter lista de tabelas ordenadas por tamanho (excluindo tabelas do sistema)
TABLES_FILE="${LOG_DIR}/tables_by_size.txt"
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT schemaname || '.' || tablename
    FROM pg_tables
    JOIN pg_class ON pg_tables.tablename = pg_class.relname
    JOIN pg_namespace ON pg_tables.schemaname = pg_namespace.nspname AND pg_class.relnamespace = pg_namespace.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY pg_relation_size(schemaname || '.' || tablename) DESC
    LIMIT 20;" > "$TABLES_FILE"

# Executar VACUUM FULL em cada tabela
while read -r TABLE; do
    TABLE=$(echo "$TABLE" | tr -d ' ')
    if [ -n "$TABLE" ]; then
        log_message "Executando VACUUM FULL em $TABLE..."
        START_TIME=$(date +%s)
        
        PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB << EOF
\timing on
VACUUM FULL $TABLE;
EOF
        
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        log_message "VACUUM FULL em $TABLE concluído em $DURATION segundos"
    fi
done < "$TABLES_FILE"

# Configurar parâmetros de autovacuum específicos para tabelas grandes
log_message "Configurando parâmetros de autovacuum para tabelas grandes..."

# Obter as 10 maiores tabelas
LARGE_TABLES_FILE="${LOG_DIR}/large_tables.txt"
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT schemaname || '.' || tablename
    FROM pg_tables
    JOIN pg_class ON pg_tables.tablename = pg_class.relname
    JOIN pg_namespace ON pg_tables.schemaname = pg_namespace.nspname AND pg_class.relnamespace = pg_namespace.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY pg_relation_size(schemaname || '.' || tablename) DESC
    LIMIT 10;" > "$LARGE_TABLES_FILE"

# Configurar autovacuum para cada tabela grande
while read -r TABLE; do
    TABLE=$(echo "$TABLE" | tr -d ' ')
    if [ -n "$TABLE" ]; then
        log_message "Configurando autovacuum para $TABLE..."
        
        PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
            ALTER TABLE $TABLE SET (
                autovacuum_vacuum_scale_factor = 0.05,
                autovacuum_analyze_scale_factor = 0.02,
                autovacuum_vacuum_cost_limit = 2000,
                autovacuum_vacuum_cost_delay = 10
            );"
        
        if [ $? -eq 0 ]; then
            log_message "Parâmetros de autovacuum configurados para $TABLE"
        else
            log_message "ERRO ao configurar parâmetros de autovacuum para $TABLE"
        fi
    fi
done < "$LARGE_TABLES_FILE"

# Configurar parâmetros de autovacuum específicos para tabelas espaciais
log_message "Configurando parâmetros de autovacuum para tabelas espaciais..."

# Obter lista de tabelas espaciais
SPATIAL_TABLES_FILE="${LOG_DIR}/spatial_tables.txt"
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT f_table_schema || '.' || f_table_name
    FROM geometry_columns
    ORDER BY f_table_schema, f_table_name;" > "$SPATIAL_TABLES_FILE"

# Configurar autovacuum para cada tabela espacial
while read -r TABLE; do
    TABLE=$(echo "$TABLE" | tr -d ' ')
    if [ -n "$TABLE" ]; then
        log_message "Configurando autovacuum para tabela espacial $TABLE..."
        
        PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
            ALTER TABLE $TABLE SET (
                autovacuum_vacuum_scale_factor = 0.05,
                autovacuum_analyze_scale_factor = 0.02
            );"
        
        if [ $? -eq 0 ]; then
            log_message "Parâmetros de autovacuum configurados para $TABLE"
        else
            log_message "ERRO ao configurar parâmetros de autovacuum para $TABLE"
        fi
    fi
done < "$SPATIAL_TABLES_FILE"

# Verificar e corrigir problemas de sequência
log_message "Verificando e corrigindo problemas de sequência..."

# Criar script SQL para corrigir sequências
cat > "${LOG_DIR}/fix_sequences.sql" << EOF
DO \$\$
DECLARE
    seq_record RECORD;
    max_value BIGINT;
    seq_name TEXT;
    table_name TEXT;
    column_name TEXT;
BEGIN
    FOR seq_record IN
        SELECT
            n.nspname AS schema_name,
            s.relname AS sequence_name,
            t.relname AS table_name,
            a.attname AS column_name
        FROM pg_class s
        JOIN pg_namespace n ON n.oid = s.relnamespace
        JOIN pg_depend d ON d.objid = s.oid
        JOIN pg_class t ON d.refobjid = t.oid
        JOIN pg_attribute a ON (d.refobjid, d.refobjsubid) = (a.attrelid, a.attnum)
        WHERE s.relkind = 'S'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
    LOOP
        seq_name := seq_record.schema_name || '.' || seq_record.sequence_name;
        table_name := seq_record.schema_name || '.' || seq_record.table_name;
        column_name := seq_record.column_name;
        
        EXECUTE format('SELECT coalesce(max(%I), 0) FROM %s', column_name, table_name) INTO max_value;
        
        IF max_value > 0 THEN
            RAISE NOTICE 'Ajustando sequência % para tabela %.% (valor máximo: %)', 
                seq_name, table_name, column_name, max_value;
                
            EXECUTE format('SELECT setval(''%s'', %s)', seq_name, max_value + 1);
        END IF;
    END LOOP;
END \$\$;
EOF

# Executar o script para corrigir sequências
log_message "Executando script para corrigir sequências..."
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -f "${LOG_DIR}/fix_sequences.sql"

# Verificar índices espaciais
log_message "Verificando índices espaciais..."
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
    SELECT schemaname, tablename, indexname, indexdef
    FROM pg_indexes
    WHERE indexdef LIKE '%gist%'
    ORDER BY schemaname, tablename;" > "${LOG_DIR}/spatial_indexes.txt"

log_message "Lista de índices espaciais salva em ${LOG_DIR}/spatial_indexes.txt"

# Criar relatório de otimização
REPORT_FILE="${LOG_DIR}/optimization_report.txt"
{
    echo "=== Relatório de Otimização ==="
    echo "Data: $(date)"
    echo "Servidor: $TARGET_HOST"
    echo "Base de dados: $TARGET_DB"
    echo ""
    
    echo "=== Estatísticas da Base de Dados ==="
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
        SELECT 'Número de tabelas: ' || count(*) 
        FROM pg_tables 
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema');"
    
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
        SELECT 'Número de índices: ' || count(*) 
        FROM pg_indexes 
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema');"
    
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
        SELECT 'Tamanho total da base de dados: ' || pg_size_pretty(pg_database_size('$TARGET_DB'));"
    
    echo ""
    echo "=== Tabelas Maiores ==="
    PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
        SELECT schemaname || '.' || tablename || ': ' || pg_size_pretty(pg_total_relation_size(schemaname || '.' || tablename))
        FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY pg_total_relation_size(schemaname || '.' || tablename) DESC
        LIMIT 10;"
} > "$REPORT_FILE"

log_message "Relatório de otimização salvo em $REPORT_FILE"
log_message "Otimização da base de dados concluída com sucesso"

exit 0
