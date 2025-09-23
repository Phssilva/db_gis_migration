#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando testes de desempenho..."

# Criar diretório para resultados dos testes
PERF_DIR="${LOG_DIR}/performance_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$PERF_DIR"
log_message "Resultados dos testes serão salvos em $PERF_DIR"

# Função para executar uma consulta e medir o tempo
run_query() {
    local db_host=$1
    local db_port=$2
    local db_user=$3
    local db_password=$4
    local db_name=$5
    local query=$6
    local description=$7
    local output_file=$8
    
    log_message "Executando consulta: $description"
    
    # Executar a consulta 3 vezes para obter uma média
    for i in {1..3}; do
        START_TIME=$(date +%s.%N)
        
        PGPASSWORD=$db_password psql -h $db_host -p $db_port -U $db_user -d $db_name -c "$query" > /dev/null 2>&1
        
        END_TIME=$(date +%s.%N)
        DURATION=$(echo "$END_TIME - $START_TIME" | bc)
        
        echo "Execução $i: $DURATION segundos" >> "$output_file"
    done
    
    # Calcular média
    AVERAGE=$(awk '{ sum += $2; } END { print sum/NR; }' "$output_file")
    echo "Média: $AVERAGE segundos" >> "$output_file"
    
    log_message "Consulta concluída. Tempo médio: $AVERAGE segundos"
    
    # Retornar o tempo médio
    echo $AVERAGE
}

# Verificar conexão com os servidores
log_message "Verificando conexão com o servidor de origem..."
if ! PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "ERRO: Não foi possível conectar à base de dados de origem $SOURCE_DB"
    log_message "Os testes serão executados apenas no servidor de destino"
    SOURCE_AVAILABLE=false
else
    SOURCE_AVAILABLE=true
fi

log_message "Verificando conexão com o servidor de destino..."
if ! PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "ERRO: Não foi possível conectar à base de dados de destino $TARGET_DB"
    exit 1
fi

# Obter informações sobre as tabelas espaciais no servidor de destino
log_message "Obtendo informações sobre tabelas espaciais no servidor de destino..."
PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -c "
    SELECT f_table_schema, f_table_name, f_geometry_column, srid, type
    FROM geometry_columns
    ORDER BY f_table_schema, f_table_name;" > "${PERF_DIR}/spatial_tables.txt"

# Criar arquivo para armazenar os resultados dos testes
RESULTS_FILE="${PERF_DIR}/performance_results.csv"
echo "Teste,Descrição,Tempo Origem (s),Tempo Destino (s),Melhoria (%)" > "$RESULTS_FILE"

# Teste 1: Contagem de registros em uma tabela grande
log_message "Teste 1: Contagem de registros em uma tabela grande"

# Obter a maior tabela no servidor de destino
LARGEST_TABLE=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT schemaname || '.' || tablename
    FROM pg_tables
    JOIN pg_class ON pg_tables.tablename = pg_class.relname
    JOIN pg_namespace ON pg_tables.schemaname = pg_namespace.nspname AND pg_class.relnamespace = pg_namespace.oid
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY pg_relation_size(schemaname || '.' || tablename) DESC
    LIMIT 1;" | tr -d ' ')

if [ -n "$LARGEST_TABLE" ]; then
    log_message "Maior tabela encontrada: $LARGEST_TABLE"
    
    QUERY="SELECT count(*) FROM $LARGEST_TABLE;"
    DESCRIPTION="Contagem de registros em $LARGEST_TABLE"
    
    # Executar no servidor de origem se disponível
    if [ "$SOURCE_AVAILABLE" = true ]; then
        SOURCE_TIME=$(run_query "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DB" "$QUERY" "$DESCRIPTION (origem)" "${PERF_DIR}/test1_source.txt")
    else
        SOURCE_TIME="N/A"
    fi
    
    # Executar no servidor de destino
    TARGET_TIME=$(run_query "$TARGET_HOST" "$TARGET_PORT" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DB" "$QUERY" "$DESCRIPTION (destino)" "${PERF_DIR}/test1_target.txt")
    
    # Calcular melhoria se ambos os tempos estiverem disponíveis
    if [ "$SOURCE_TIME" != "N/A" ]; then
        IMPROVEMENT=$(echo "scale=2; 100 - ($TARGET_TIME * 100 / $SOURCE_TIME)" | bc)
        echo "Teste1,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,$IMPROVEMENT" >> "$RESULTS_FILE"
    else
        echo "Teste1,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,N/A" >> "$RESULTS_FILE"
    fi
else
    log_message "AVISO: Não foi possível encontrar uma tabela para o teste 1"
fi

# Teste 2: Consulta espacial simples
log_message "Teste 2: Consulta espacial simples"

# Obter uma tabela espacial no servidor de destino
SPATIAL_TABLE_INFO=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT f_table_schema, f_table_name, f_geometry_column
    FROM geometry_columns
    LIMIT 1;")

if [ -n "$SPATIAL_TABLE_INFO" ]; then
    # Extrair informações da tabela espacial
    SCHEMA=$(echo $SPATIAL_TABLE_INFO | awk '{print $1}')
    TABLE=$(echo $SPATIAL_TABLE_INFO | awk '{print $2}')
    GEOM_COL=$(echo $SPATIAL_TABLE_INFO | awk '{print $3}')
    
    FULL_TABLE="$SCHEMA.$TABLE"
    log_message "Tabela espacial encontrada: $FULL_TABLE, coluna de geometria: $GEOM_COL"
    
    # Consulta para obter a extensão (envelope) dos dados
    QUERY="SELECT ST_AsText(ST_Extent($GEOM_COL)) FROM $FULL_TABLE;"
    DESCRIPTION="Cálculo de extensão espacial em $FULL_TABLE"
    
    # Executar no servidor de origem se disponível
    if [ "$SOURCE_AVAILABLE" = true ]; then
        SOURCE_TIME=$(run_query "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DB" "$QUERY" "$DESCRIPTION (origem)" "${PERF_DIR}/test2_source.txt")
    else
        SOURCE_TIME="N/A"
    fi
    
    # Executar no servidor de destino
    TARGET_TIME=$(run_query "$TARGET_HOST" "$TARGET_PORT" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DB" "$QUERY" "$DESCRIPTION (destino)" "${PERF_DIR}/test2_target.txt")
    
    # Calcular melhoria se ambos os tempos estiverem disponíveis
    if [ "$SOURCE_TIME" != "N/A" ]; then
        IMPROVEMENT=$(echo "scale=2; 100 - ($TARGET_TIME * 100 / $SOURCE_TIME)" | bc)
        echo "Teste2,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,$IMPROVEMENT" >> "$RESULTS_FILE"
    else
        echo "Teste2,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,N/A" >> "$RESULTS_FILE"
    fi
else
    log_message "AVISO: Não foi possível encontrar uma tabela espacial para o teste 2"
fi

# Teste 3: Junção de tabelas
log_message "Teste 3: Junção de tabelas"

# Obter duas tabelas para junção
TABLES=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
    SELECT schemaname || '.' || tablename
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY pg_relation_size(schemaname || '.' || tablename) DESC
    LIMIT 2;" | tr '\n' ' ')

if [ -n "$TABLES" ]; then
    # Extrair as duas tabelas
    TABLE1=$(echo $TABLES | awk '{print $1}')
    TABLE2=$(echo $TABLES | awk '{print $2}')
    
    if [ -n "$TABLE1" ] && [ -n "$TABLE2" ]; then
        log_message "Tabelas para junção: $TABLE1 e $TABLE2"
        
        # Obter uma coluna comum para junção (por exemplo, um ID)
        COMMON_COLUMN=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
            SELECT a.attname
            FROM pg_attribute a
            JOIN pg_class t1 ON a.attrelid = t1.oid
            JOIN pg_class t2 ON t2.relname = (SELECT tablename FROM pg_tables WHERE schemaname || '.' || tablename = '$TABLE2')
            JOIN pg_namespace n1 ON t1.relnamespace = n1.oid
            JOIN pg_namespace n2 ON t2.relnamespace = n2.oid
            WHERE n1.nspname || '.' || t1.relname = '$TABLE1'
            AND a.attnum > 0
            AND NOT a.attisdropped
            AND a.attname IN (
                SELECT a2.attname
                FROM pg_attribute a2
                WHERE a2.attrelid = t2.oid
                AND a2.attnum > 0
                AND NOT a2.attisdropped
            )
            LIMIT 1;" | tr -d ' ')
        
        if [ -n "$COMMON_COLUMN" ]; then
            log_message "Coluna comum encontrada: $COMMON_COLUMN"
            
            QUERY="SELECT count(*) FROM $TABLE1 t1 JOIN $TABLE2 t2 ON t1.$COMMON_COLUMN = t2.$COMMON_COLUMN;"
            DESCRIPTION="Junção entre $TABLE1 e $TABLE2 usando $COMMON_COLUMN"
            
            # Executar no servidor de origem se disponível
            if [ "$SOURCE_AVAILABLE" = true ]; then
                SOURCE_TIME=$(run_query "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DB" "$QUERY" "$DESCRIPTION (origem)" "${PERF_DIR}/test3_source.txt")
            else
                SOURCE_TIME="N/A"
            fi
            
            # Executar no servidor de destino
            TARGET_TIME=$(run_query "$TARGET_HOST" "$TARGET_PORT" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DB" "$QUERY" "$DESCRIPTION (destino)" "${PERF_DIR}/test3_target.txt")
            
            # Calcular melhoria se ambos os tempos estiverem disponíveis
            if [ "$SOURCE_TIME" != "N/A" ]; then
                IMPROVEMENT=$(echo "scale=2; 100 - ($TARGET_TIME * 100 / $SOURCE_TIME)" | bc)
                echo "Teste3,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,$IMPROVEMENT" >> "$RESULTS_FILE"
            else
                echo "Teste3,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,N/A" >> "$RESULTS_FILE"
            fi
        else
            log_message "AVISO: Não foi possível encontrar uma coluna comum para junção"
        fi
    else
        log_message "AVISO: Não foi possível encontrar duas tabelas para o teste 3"
    fi
else
    log_message "AVISO: Não foi possível encontrar tabelas para o teste 3"
fi

# Teste 4: Consulta espacial com buffer
log_message "Teste 4: Consulta espacial com buffer"

if [ -n "$SPATIAL_TABLE_INFO" ]; then
    # Usar a mesma tabela espacial do teste 2
    SCHEMA=$(echo $SPATIAL_TABLE_INFO | awk '{print $1}')
    TABLE=$(echo $SPATIAL_TABLE_INFO | awk '{print $2}')
    GEOM_COL=$(echo $SPATIAL_TABLE_INFO | awk '{print $3}')
    
    FULL_TABLE="$SCHEMA.$TABLE"
    log_message "Tabela espacial para teste de buffer: $FULL_TABLE, coluna de geometria: $GEOM_COL"
    
    # Consulta para criar um buffer e calcular a área
    QUERY="SELECT count(*) FROM (SELECT ST_Buffer($GEOM_COL, 100) FROM $FULL_TABLE LIMIT 100) AS t;"
    DESCRIPTION="Criação de buffer em $FULL_TABLE"
    
    # Executar no servidor de origem se disponível
    if [ "$SOURCE_AVAILABLE" = true ]; then
        SOURCE_TIME=$(run_query "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DB" "$QUERY" "$DESCRIPTION (origem)" "${PERF_DIR}/test4_source.txt")
    else
        SOURCE_TIME="N/A"
    fi
    
    # Executar no servidor de destino
    TARGET_TIME=$(run_query "$TARGET_HOST" "$TARGET_PORT" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DB" "$QUERY" "$DESCRIPTION (destino)" "${PERF_DIR}/test4_target.txt")
    
    # Calcular melhoria se ambos os tempos estiverem disponíveis
    if [ "$SOURCE_TIME" != "N/A" ]; then
        IMPROVEMENT=$(echo "scale=2; 100 - ($TARGET_TIME * 100 / $SOURCE_TIME)" | bc)
        echo "Teste4,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,$IMPROVEMENT" >> "$RESULTS_FILE"
    else
        echo "Teste4,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,N/A" >> "$RESULTS_FILE"
    fi
else
    log_message "AVISO: Não foi possível encontrar uma tabela espacial para o teste 4"
fi

# Teste 5: Consulta com ordenação
log_message "Teste 5: Consulta com ordenação"

if [ -n "$LARGEST_TABLE" ]; then
    # Obter uma coluna para ordenação
    SORT_COLUMN=$(PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d $TARGET_DB -t -c "
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema || '.' || table_name = '$LARGEST_TABLE'
        AND data_type IN ('integer', 'bigint', 'numeric', 'timestamp', 'date')
        LIMIT 1;" | tr -d ' ')
    
    if [ -n "$SORT_COLUMN" ]; then
        log_message "Coluna para ordenação: $SORT_COLUMN"
        
        QUERY="SELECT * FROM $LARGEST_TABLE ORDER BY $SORT_COLUMN LIMIT 1000;"
        DESCRIPTION="Ordenação por $SORT_COLUMN em $LARGEST_TABLE"
        
        # Executar no servidor de origem se disponível
        if [ "$SOURCE_AVAILABLE" = true ]; then
            SOURCE_TIME=$(run_query "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_USER" "$SOURCE_PASSWORD" "$SOURCE_DB" "$QUERY" "$DESCRIPTION (origem)" "${PERF_DIR}/test5_source.txt")
        else
            SOURCE_TIME="N/A"
        fi
        
        # Executar no servidor de destino
        TARGET_TIME=$(run_query "$TARGET_HOST" "$TARGET_PORT" "$TARGET_USER" "$TARGET_PASSWORD" "$TARGET_DB" "$QUERY" "$DESCRIPTION (destino)" "${PERF_DIR}/test5_target.txt")
        
        # Calcular melhoria se ambos os tempos estiverem disponíveis
        if [ "$SOURCE_TIME" != "N/A" ]; then
            IMPROVEMENT=$(echo "scale=2; 100 - ($TARGET_TIME * 100 / $SOURCE_TIME)" | bc)
            echo "Teste5,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,$IMPROVEMENT" >> "$RESULTS_FILE"
        else
            echo "Teste5,$DESCRIPTION,$SOURCE_TIME,$TARGET_TIME,N/A" >> "$RESULTS_FILE"
        fi
    else
        log_message "AVISO: Não foi possível encontrar uma coluna para ordenação"
    fi
else
    log_message "AVISO: Não foi possível encontrar uma tabela para o teste 5"
fi

# Criar relatório de desempenho
PERF_REPORT="${PERF_DIR}/performance_report.txt"
{
    echo "=== Relatório de Desempenho ==="
    echo "Data: $(date)"
    echo "Servidor de origem: $SOURCE_HOST"
    echo "Base de dados de origem: $SOURCE_DB"
    echo "Servidor de destino: $TARGET_HOST"
    echo "Base de dados de destino: $TARGET_DB"
    echo ""
    
    echo "=== Resultados dos Testes ==="
    if [ "$SOURCE_AVAILABLE" = true ]; then
        echo "| Teste | Descrição | Tempo Origem (s) | Tempo Destino (s) | Melhoria (%) |"
        echo "|-------|-----------|-----------------|------------------|-------------|"
        
        # Ler os resultados do arquivo CSV (pular o cabeçalho)
        tail -n +2 "$RESULTS_FILE" | while IFS=',' read -r test desc source_time target_time improvement; do
            printf "| %s | %s | %s | %s | %s |\n" "$test" "$desc" "$source_time" "$target_time" "$improvement"
        done
    else
        echo "Servidor de origem não disponível para comparação."
        echo "| Teste | Descrição | Tempo Destino (s) |"
        echo "|-------|-----------|------------------|"
        
        # Ler os resultados do arquivo CSV (pular o cabeçalho)
        tail -n +2 "$RESULTS_FILE" | while IFS=',' read -r test desc source_time target_time improvement; do
            printf "| %s | %s | %s |\n" "$test" "$desc" "$target_time"
        done
    fi
    
    echo ""
    echo "=== Conclusão ==="
    if [ "$SOURCE_AVAILABLE" = true ]; then
        # Calcular a média de melhoria
        AVERAGE_IMPROVEMENT=$(awk -F',' 'NR>1 && $5!="N/A" {sum+=$5; count++} END {if(count>0) print sum/count; else print "N/A"}' "$RESULTS_FILE")
        
        if [ "$AVERAGE_IMPROVEMENT" != "N/A" ]; then
            if (( $(echo "$AVERAGE_IMPROVEMENT > 0" | bc -l) )); then
                echo "Melhoria média de desempenho: $AVERAGE_IMPROVEMENT%"
                echo "O PostgreSQL 15 apresentou melhor desempenho em comparação com o PostgreSQL 13."
            elif (( $(echo "$AVERAGE_IMPROVEMENT < 0" | bc -l) )); then
                echo "Redução média de desempenho: $(echo "$AVERAGE_IMPROVEMENT * -1" | bc)%"
                echo "O PostgreSQL 15 apresentou pior desempenho em comparação com o PostgreSQL 13."
                echo "Recomenda-se investigar as causas e otimizar a configuração."
            else
                echo "Não houve diferença significativa de desempenho entre o PostgreSQL 13 e o PostgreSQL 15."
            fi
        else
            echo "Não foi possível calcular a média de melhoria."
        fi
    else
        echo "Não foi possível comparar o desempenho com o servidor de origem, pois ele não estava disponível."
    fi
    
    echo ""
    echo "=== Recomendações ==="
    echo "1. Analise os resultados dos testes para identificar áreas que podem ser otimizadas."
    echo "2. Ajuste os parâmetros de configuração do PostgreSQL 15 conforme necessário."
    echo "3. Considere reindexar tabelas específicas que apresentaram desempenho inferior."
    echo "4. Verifique se os índices espaciais estão sendo utilizados corretamente nas consultas."
} > "$PERF_REPORT"

log_message "Relatório de desempenho salvo em $PERF_REPORT"
log_message "Testes de desempenho concluídos"

exit 0
