# PostgreSQL ArcGIS Geodatabase Migration Project

## Visão Geral
Este projeto contém scripts e documentação para migrar uma geodatabase ArcGIS do PostgreSQL 13.18 para o PostgreSQL 15.12 em um ambiente Ubuntu.

**Nota**: Este projeto assume que o PostgreSQL 15.12 já está instalado no servidor de destino. O foco está na exportação do dump da base de dados de origem, restauração no servidor de destino e configuração da biblioteca ST_Geometry.

## Estrutura do Projeto
```
.
├── backups/            # Diretório para armazenar backups
├── config/             # Arquivos de configuração
├── docs/               # Documentação detalhada
├── logs/               # Logs gerados durante a migração
└── scripts/            # Scripts para o processo de migração
    ├── pre_migration/  # Scripts para preparação e análise
    ├── migration/      # Scripts para exportação e importação
    ├── post_migration/ # Scripts para otimização pós-migração
    ├── validation/     # Scripts para validação e testes
    └── rollback/       # Scripts para procedimentos de rollback
```

## Pré-requisitos

### Servidor de Origem
- PostgreSQL 13.18 em execução
- Acesso com permissões de leitura à base de dados
- Espaço em disco suficiente para o backup

### Servidor de Destino
- Ubuntu 22.04 LTS (ou superior)
- **PostgreSQL 15.12 já instalado e configurado**
- PostGIS 3.5.x (se a geodatabase usar geometrias PostGIS)
- Biblioteca ST_Geometry da Esri compatível com PostgreSQL 15
- **Partição dedicada para backup** (recomendado: 1TB ou mais)
  - Uma partição onde o PostgreSQL está instalado
  - Outra partição para armazenar o dump antes da restauração
- Espaço em disco suficiente para a base de dados restaurada
- Permissões de administrador

### Outros
- Acesso ao portal My Esri para download da biblioteca ST_Geometry
- Conectividade de rede entre os servidores de origem e destino

## Fases da Migração

### 1. Análise Pré-Atualização
- Verificação da matriz de compatibilidade ArcGIS-PostgreSQL
- Auditoria do ambiente de origem
- Preparação do ambiente de destino

### 2. Verificação e Configuração do Ambiente de Destino
- Verificação da instalação do PostgreSQL 15.12 e PostGIS
- Configuração do locale do sistema
- Ajustes de configuração do PostgreSQL (postgresql.conf, pg_hba.conf)
- Instalação da biblioteca ST_Geometry

### 3. Execução da Migração
- Congelamento do sistema de origem
- Exportação de objetos globais e da base de dados
- Restauração no servidor de destino
- Operações pós-restauração

### 4. Otimização Pós-Migração
- Ajuste fino da configuração do PostgreSQL 15
- Otimização do autovacuum
- Atualização de estatísticas

### 5. Integração com ArcGIS e Validação
- Verificação da conectividade ArcGIS
- Atualização da geodatabase
- Validação dos serviços ArcGIS
- Transição final

## Instruções de Uso

### 1. Preparar o Ambiente
```bash
# Criar a estrutura de diretórios
./create_project_structure.sh

# Montar a partição de backup (se ainda não estiver montada)
# Exemplo: sudo mount /dev/sdb1 /mnt/backup_partition
```

### 2. Configurar o Projeto
Edite o arquivo `config/migration_config.sh` e configure:
- **BACKUP_DIR**: Caminho para a partição de backup no servidor de destino
  - Exemplo: `/mnt/backup_partition` ou `/backup`
- **SOURCE_HOST**: IP do servidor de origem
- **SOURCE_DB**: Nome da base de dados
- **ST_GEOMETRY_PATH**: Caminho para a biblioteca ST_Geometry baixada

### 3. Executar a Migração
```bash
# Executar o script principal
./migrate.sh

# Ou seguir o guia detalhado
cat docs/migration_guide.md
```

## Procedimento de Rollback
Em caso de falha, consulte `docs/rollback_procedure.md` para instruções detalhadas sobre como reverter a migração.

## Autores
- Pedro Silva

## Licença
MIT
