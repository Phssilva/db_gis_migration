#!/bin/bash

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando congelamento do sistema de origem..."

# Criar diretório para backup temporário do pg_hba.conf
TEMP_DIR="${LOG_DIR}/temp_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$TEMP_DIR"

# Obter o pg_hba.conf atual
log_message "Obtendo configuração atual de pg_hba.conf..."
PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "SHOW hba_file;" > "${TEMP_DIR}/hba_file_path.txt"

if [ -s "${TEMP_DIR}/hba_file_path.txt" ]; then
    HBA_FILE=$(cat "${TEMP_DIR}/hba_file_path.txt" | tr -d ' ')
    log_message "Arquivo pg_hba.conf localizado em: $HBA_FILE"
    
    # Verificar se podemos acessar o arquivo diretamente (caso estejamos no mesmo servidor)
    if [ -f "$HBA_FILE" ]; then
        log_message "Fazendo backup do pg_hba.conf original..."
        cp "$HBA_FILE" "${TEMP_DIR}/pg_hba.conf.bak"
        
        log_message "Modificando pg_hba.conf para permitir apenas conexões do servidor de migração..."
        # Obter o IP do servidor atual
        MIGRATION_SERVER_IP=$(hostname -I | awk '{print $1}')
        
        # Criar novo pg_hba.conf que permite apenas conexões do servidor de migração
        cat > "${TEMP_DIR}/pg_hba.conf.new" << EOF
# Arquivo pg_hba.conf temporário para migração
# Gerado automaticamente pelo script de migração

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Conexões locais para administração
local   all             postgres                                peer
local   all             all                                     peer

# Conexões IPv4 locais
host    all             all             127.0.0.1/32            md5

# Conexões do servidor de migração
host    all             all             $MIGRATION_SERVER_IP/32 md5

# Conexões do servidor de origem (caso seja diferente)
host    all             all             $SOURCE_HOST/32         md5
EOF

        # Aplicar o novo pg_hba.conf
        log_message "Aplicando novo pg_hba.conf..."
        sudo cp "${TEMP_DIR}/pg_hba.conf.new" "$HBA_FILE"
        sudo chown postgres:postgres "$HBA_FILE"
        sudo chmod 600 "$HBA_FILE"
        
        # Recarregar a configuração do PostgreSQL
        log_message "Recarregando configuração do PostgreSQL..."
        if [ -f "${SOURCE_POSTGRES_HOME}/bin/pg_ctl" ]; then
            sudo -u postgres ${SOURCE_POSTGRES_HOME}/bin/pg_ctl reload -D $(dirname $HBA_FILE)
        else
            log_message "AVISO: Não foi possível encontrar pg_ctl. Tentando recarregar via SQL..."
            PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "SELECT pg_reload_conf();"
        fi
        
        log_message "Configuração do PostgreSQL recarregada"
    else
        log_message "AVISO: Não foi possível acessar o arquivo pg_hba.conf diretamente."
        log_message "Você precisará modificar manualmente o pg_hba.conf no servidor de origem para permitir apenas conexões do servidor de migração."
        log_message "Após a modificação, execute 'SELECT pg_reload_conf();' no PostgreSQL."
        
        # Aguardar confirmação do usuário
        read -p "Pressione Enter após modificar o pg_hba.conf e recarregar a configuração..."
    fi
else
    log_message "AVISO: Não foi possível determinar o caminho do pg_hba.conf."
    log_message "Você precisará modificar manualmente o pg_hba.conf no servidor de origem para permitir apenas conexões do servidor de migração."
    
    # Aguardar confirmação do usuário
    read -p "Pressione Enter após modificar o pg_hba.conf e recarregar a configuração..."
fi

# Verificar conexões ativas
log_message "Verificando conexões ativas na base de dados $SOURCE_DB..."
ACTIVE_CONNECTIONS=$(PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -t -c "
    SELECT count(*) 
    FROM pg_stat_activity 
    WHERE datname = '$SOURCE_DB' 
    AND pid <> pg_backend_pid() 
    AND state = 'active';")

ACTIVE_CONNECTIONS=$(echo $ACTIVE_CONNECTIONS | tr -d ' ')

if [ "$ACTIVE_CONNECTIONS" -gt 0 ]; then
    log_message "AVISO: Existem $ACTIVE_CONNECTIONS conexões ativas na base de dados."
    log_message "Detalhes das conexões ativas:"
    
    PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "
        SELECT pid, usename, application_name, client_addr, state, query_start, query
        FROM pg_stat_activity 
        WHERE datname = '$SOURCE_DB' 
        AND pid <> pg_backend_pid() 
        AND state = 'active';"
    
    log_message "Você deve encerrar todas as conexões ativas antes de prosseguir."
    log_message "Isso inclui parar todos os serviços ArcGIS que estejam conectados à base de dados."
    
    # Perguntar se o usuário deseja encerrar as conexões
    read -p "Deseja encerrar todas as conexões ativas? (s/n): " TERMINATE_CONNECTIONS
    
    if [ "$TERMINATE_CONNECTIONS" = "s" ] || [ "$TERMINATE_CONNECTIONS" = "S" ]; then
        log_message "Encerrando todas as conexões ativas..."
        
        PGPASSWORD=$SOURCE_PASSWORD psql -h $SOURCE_HOST -p $SOURCE_PORT -U $SOURCE_USER -d $SOURCE_DB -c "
            SELECT pg_terminate_backend(pid) 
            FROM pg_stat_activity 
            WHERE datname = '$SOURCE_DB' 
            AND pid <> pg_backend_pid();"
        
        log_message "Conexões encerradas"
    else
        log_message "Por favor, encerre manualmente todas as conexões ativas."
        read -p "Pressione Enter após encerrar todas as conexões ativas..."
    fi
else
    log_message "Não há conexões ativas na base de dados além da nossa própria conexão."
fi

# Criar arquivo com informações para restauração posterior
cat > "${TEMP_DIR}/restore_info.sh" << EOF
#!/bin/bash

# Informações para restauração do pg_hba.conf original
SOURCE_HOST="$SOURCE_HOST"
SOURCE_PORT="$SOURCE_PORT"
SOURCE_USER="$SOURCE_USER"
SOURCE_PASSWORD="$SOURCE_PASSWORD"
HBA_FILE="$HBA_FILE"
HBA_BACKUP="${TEMP_DIR}/pg_hba.conf.bak"

# Função para restaurar o pg_hba.conf original
restore_pg_hba() {
    echo "Restaurando pg_hba.conf original..."
    
    if [ -f "\$HBA_BACKUP" ]; then
        sudo cp "\$HBA_BACKUP" "\$HBA_FILE"
        sudo chown postgres:postgres "\$HBA_FILE"
        sudo chmod 600 "\$HBA_FILE"
        
        # Recarregar a configuração do PostgreSQL
        echo "Recarregando configuração do PostgreSQL..."
        PGPASSWORD=\$SOURCE_PASSWORD psql -h \$SOURCE_HOST -p \$SOURCE_PORT -U \$SOURCE_USER -d postgres -c "SELECT pg_reload_conf();"
        
        echo "Configuração original restaurada"
    else
        echo "AVISO: Backup do pg_hba.conf não encontrado em \$HBA_BACKUP"
        echo "Você precisará restaurar manualmente o pg_hba.conf original."
    fi
}
EOF

chmod +x "${TEMP_DIR}/restore_info.sh"

log_message "Informações para restauração salvas em ${TEMP_DIR}/restore_info.sh"
log_message "Congelamento do sistema de origem concluído com sucesso"

# Salvar o caminho do arquivo de restauração para uso posterior
echo "${TEMP_DIR}/restore_info.sh" > "${LOG_DIR}/restore_info_path.txt"

exit 0
