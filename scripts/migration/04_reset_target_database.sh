#!/bin/bash

# Determinar o diretório base do projeto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Carrega a configuração
source "$BASE_DIR/config/migration_config.sh"

log_message "====================================================="
log_message "REINICIALIZAÇÃO DO CLUSTER POSTGRESQL 15"
log_message "====================================================="
log_message "ATENÇÃO: Este script vai APAGAR TODOS OS DADOS do PostgreSQL 15!"
log_message "Data directory: $TARGET_DATA_DIR"
log_message "====================================================="

read -p "Tem certeza que deseja continuar? (digite 'SIM' para confirmar): " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    log_message "Operação cancelada pelo usuário"
    exit 1
fi

log_message "Iniciando reinicialização do cluster..."

# 1. Parar o PostgreSQL
log_message "Parando o PostgreSQL..."
sudo pg_ctlcluster 15 main stop

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao parar o PostgreSQL"
    exit 1
fi

log_message "PostgreSQL parado com sucesso"

# 2. Fazer backup do postgresql.conf
log_message "Fazendo backup do postgresql.conf..."
sudo cp /etc/postgresql/15/main/postgresql.conf /tmp/postgresql.conf.backup 2>/dev/null

# 3. Verificar espaço antes
log_message "Espaço em disco ANTES da limpeza:"
df -h /mnt/banco

# 4. Remover o data directory
log_message "Removendo data directory: $TARGET_DATA_DIR"
sudo rm -rf "$TARGET_DATA_DIR"/*

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao remover data directory"
    exit 1
fi

log_message "Data directory removido com sucesso"

# 5. Verificar espaço depois
log_message "Espaço em disco APÓS a limpeza:"
df -h /mnt/banco

# 6. Remover e recriar o cluster
log_message "Removendo cluster PostgreSQL 15..."
sudo pg_dropcluster 15 main 2>/dev/null

log_message "Criando novo cluster PostgreSQL 15..."
sudo pg_createcluster 15 main -d "$TARGET_DATA_DIR"

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao criar cluster PostgreSQL"
    exit 1
fi

log_message "Cluster criado com sucesso"

# 7. Iniciar o PostgreSQL
log_message "Iniciando PostgreSQL..."
sudo pg_ctlcluster 15 main start

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao iniciar PostgreSQL"
    exit 1
fi

log_message "PostgreSQL iniciado com sucesso"

# 8. Aguardar o PostgreSQL inicializar completamente
log_message "Aguardando PostgreSQL inicializar..."
sleep 3

# 9. Redefinir senha do postgres
log_message "Redefinindo senha do usuário postgres..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$TARGET_PASSWORD';"

if [ $? -ne 0 ]; then
    log_message "ERRO: Falha ao redefinir senha do postgres"
    exit 1
fi

log_message "Senha do postgres redefinida com sucesso"

# 10. Criar diretórios para tablespaces
log_message "Criando diretórios para tablespaces..."
sudo mkdir -p /mnt/banco/tablespaces/{gis_data,sde,gis_data_idx,gis_delta,gis_delta_idx,sde_idx,log_idx}
sudo chown -R postgres:postgres /mnt/banco/tablespaces
sudo chmod 700 /mnt/banco/tablespaces/*

log_message "Diretórios de tablespaces criados"

# 11. Criar tablespaces no PostgreSQL
log_message "Criando tablespaces no PostgreSQL..."
sudo -u postgres psql << 'EOSQL'
CREATE TABLESPACE gis_data LOCATION '/mnt/banco/tablespaces/gis_data';
CREATE TABLESPACE sde LOCATION '/mnt/banco/tablespaces/sde';
CREATE TABLESPACE gis_data_idx LOCATION '/mnt/banco/tablespaces/gis_data_idx';
CREATE TABLESPACE gis_delta LOCATION '/mnt/banco/tablespaces/gis_delta';
CREATE TABLESPACE gis_delta_idx LOCATION '/mnt/banco/tablespaces/gis_delta_idx';
CREATE TABLESPACE sde_idx LOCATION '/mnt/banco/tablespaces/sde_idx';
CREATE TABLESPACE log_idx LOCATION '/mnt/banco/tablespaces/log_idx';
EOSQL

if [ $? -ne 0 ]; then
    log_message "AVISO: Alguns tablespaces podem não ter sido criados"
else
    log_message "Tablespaces criados com sucesso"
fi

# 12. Listar tablespaces criados
log_message "Tablespaces disponíveis:"
sudo -u postgres psql -c "\db"

# 13. Verificar status final
log_message "====================================================="
log_message "REINICIALIZAÇÃO CONCLUÍDA COM SUCESSO!"
log_message "====================================================="
log_message "Status do cluster:"
pg_lsclusters
log_message ""
log_message "Versão do PostgreSQL:"
sudo -u postgres psql -c "SELECT version();"
log_message ""
log_message "Espaço em disco final:"
df -h /mnt/banco
log_message "====================================================="
log_message "O cluster PostgreSQL 15 está pronto para receber a restauração!"
log_message "Execute: ./scripts/migration/03_import_database.sh"
log_message "====================================================="
