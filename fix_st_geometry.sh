#!/bin/bash

echo "=== CORREÇÃO ST_GEOMETRY ==="

# 1. Dropar e recriar base gisdb
echo "1. Recriando base gisdb..."
psql -h localhost -U postgres << 'EOSQL'
DROP DATABASE IF EXISTS gisdb;
CREATE DATABASE gisdb;
\c gisdb
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
SELECT PostGIS_version();
EOSQL

# 2. Restaurar apenas schema sde primeiro
echo ""
echo "2. Restaurando schema SDE..."
pg_restore --verbose \
    --host=localhost \
    --port=5432 \
    --username=postgres \
    --dbname=gisdb \
    --schema=sde \
    /mnt/backuprestore/gisdb_dump_dir 2>&1 | tee ~/sde_restore.log

# 3. Verificar se spatial_references foi criada
echo ""
echo "3. Verificando tabela spatial_references..."
psql -h localhost -U postgres -d gisdb -c "\dt sde.spatial_references"
psql -h localhost -U postgres -d gisdb -c "SELECT count(*) FROM sde.spatial_references;"

# 4. Verificar SRID 4674
echo ""
echo "4. Verificando SRID 4674..."
psql -h localhost -U postgres -d gisdb -c "SELECT srid, srtext FROM sde.spatial_references WHERE srid = 4674;"

echo ""
echo "=== VERIFICAÇÃO CONCLUÍDA ==="
