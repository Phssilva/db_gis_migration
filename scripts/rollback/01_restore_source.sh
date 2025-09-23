#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando procedimento de rollback para restaurar o sistema de origem..."

# Verificar se o arquivo de informações de restauração existe
RESTORE_INFO_PATH_FILE="${LOG_DIR}/restore_info_path.txt"
if [ ! -f "$RESTORE_INFO_PATH_FILE" ]; then
    log_message "ERRO: Arquivo com caminho de informações de restauração não encontrado em $RESTORE_INFO_PATH_FILE"
    log_message "Não é possível realizar o rollback automaticamente"
    exit 1
fi

# Obter o caminho do arquivo de informações de restauração
RESTORE_INFO_PATH=$(cat "$RESTORE_INFO_PATH_FILE")
if [ ! -f "$RESTORE_INFO_PATH" ]; then
    log_message "ERRO: Arquivo de informações de restauração não encontrado em $RESTORE_INFO_PATH"
    log_message "Não é possível realizar o rollback automaticamente"
    exit 1
fi

log_message "Arquivo de informações de restauração encontrado em $RESTORE_INFO_PATH"

# Carregar as informações de restauração
source "$RESTORE_INFO_PATH"

# Verificar se a função restore_pg_hba existe
if ! type restore_pg_hba > /dev/null 2>&1; then
    log_message "ERRO: Função restore_pg_hba não encontrada no arquivo de informações de restauração"
    log_message "Não é possível restaurar o pg_hba.conf automaticamente"
    exit 1
fi

# Restaurar o pg_hba.conf original
log_message "Restaurando o pg_hba.conf original..."
restore_pg_hba

# Verificar se os serviços ArcGIS estavam em execução antes da migração
log_message "NOTA: Você deve reiniciar manualmente os serviços ArcGIS que foram parados antes da migração"
log_message "Verifique se os seguintes serviços estão em execução:"
log_message "- ArcGIS Server"
log_message "- Portal for ArcGIS"
log_message "- ArcGIS Data Store"

# Verificar se o servidor PostgreSQL de origem está em execução
log_message "Verificando se o servidor PostgreSQL de origem está em execução..."
if PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "Servidor PostgreSQL de origem está em execução"
else
    log_message "AVISO: Não foi possível conectar ao servidor PostgreSQL de origem"
    log_message "Verifique se o servidor está em execução e se as credenciais estão corretas"
fi

# Verificar conexões ativas no servidor de origem
log_message "Verificando conexões ativas no servidor de origem..."
ACTIVE_CONNECTIONS=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "
    SELECT count(*) 
    FROM pg_stat_activity 
    WHERE datname = '$SOURCE_DB' 
    AND pid <> pg_backend_pid();")

ACTIVE_CONNECTIONS=$(echo $ACTIVE_CONNECTIONS | tr -d ' ')
log_message "Número de conexões ativas no servidor de origem: $ACTIVE_CONNECTIONS"

# Verificar se o servidor de destino ainda está em execução
log_message "Verificando se o servidor PostgreSQL de destino está em execução..."
if PGPASSWORD=$TARGET_PASSWORD psql -h $TARGET_HOST -p $TARGET_PORT -U $TARGET_USER -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    log_message "Servidor PostgreSQL de destino está em execução"
    
    # Perguntar se o usuário deseja parar o servidor de destino
    read -p "Deseja parar o servidor PostgreSQL de destino? (s/n): " STOP_TARGET
    if [ "$STOP_TARGET" = "s" ] || [ "$STOP_TARGET" = "S" ]; then
        log_message "Parando o servidor PostgreSQL de destino..."
        sudo systemctl stop postgresql
        
        if [ $? -eq 0 ]; then
            log_message "Servidor PostgreSQL de destino parado com sucesso"
        else
            log_message "ERRO: Não foi possível parar o servidor PostgreSQL de destino"
        fi
    fi
else
    log_message "Servidor PostgreSQL de destino não está em execução"
fi

# Criar relatório de rollback
ROLLBACK_REPORT="${LOG_DIR}/rollback_report_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "=== Relatório de Rollback ==="
    echo "Data: $(date)"
    echo "Servidor de origem: $SOURCE_HOST"
    echo "Base de dados de origem: $SOURCE_DB"
    echo "Arquivo de informações de restauração: $RESTORE_INFO_PATH"
    echo ""
    echo "=== Ações Realizadas ==="
    echo "- Restauração do pg_hba.conf original"
    echo "- Verificação do servidor PostgreSQL de origem"
    echo "- Verificação de conexões ativas"
    
    if [ "$STOP_TARGET" = "s" ] || [ "$STOP_TARGET" = "S" ]; then
        echo "- Parada do servidor PostgreSQL de destino"
    fi
    
    echo ""
    echo "=== Próximos Passos ==="
    echo "1. Verifique se o servidor PostgreSQL de origem está funcionando corretamente"
    echo "2. Reinicie os serviços ArcGIS que foram parados antes da migração"
    echo "3. Verifique se os clientes ArcGIS conseguem conectar à base de dados de origem"
    echo "4. Verifique se os serviços de mapa e de feições estão funcionando corretamente"
} > "$ROLLBACK_REPORT"

log_message "Relatório de rollback salvo em $ROLLBACK_REPORT"
log_message "Procedimento de rollback concluído com sucesso"
log_message "IMPORTANTE: Verifique se o sistema de origem está funcionando corretamente"

exit 0
