# PostgreSQL ArcGIS Geodatabase Migration Project

## Visão Geral
Este projeto contém scripts e documentação para migrar uma geodatabase ArcGIS do PostgreSQL 13.18 para o PostgreSQL 15.12 em um ambiente Ubuntu, atualizando de Ubuntu 20.04 para 22.04.

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
- Ubuntu 22.04 LTS (servidor de destino)
- PostgreSQL 15.12
- PostGIS 3.5.x
- Biblioteca ST_Geometry da Esri compatível com PostgreSQL 15
- Acesso ao servidor de origem PostgreSQL 13.18
- Permissões de administrador em ambos os servidores
- Acesso ao portal My Esri para download da biblioteca ST_Geometry

## Fases da Migração

### 1. Análise Pré-Atualização
- Verificação da matriz de compatibilidade ArcGIS-PostgreSQL
- Auditoria do ambiente de origem
- Preparação do ambiente de destino

### 2. Provisionamento do Ambiente de Destino
- Instalação do PostgreSQL 15.12 e PostGIS
- Configuração do sistema operacional e locale
- Configuração do PostgreSQL (postgresql.conf, pg_hba.conf)

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
1. Execute `./create_project_structure.sh` para criar a estrutura de diretórios
2. Configure os parâmetros em `config/migration_config.sh`
3. Siga as instruções em `docs/migration_guide.md`

## Procedimento de Rollback
Em caso de falha, consulte `docs/rollback_procedure.md` para instruções detalhadas sobre como reverter a migração.

## Autores
- [Seu Nome/Equipe]

## Licença
[Informações de licença, se aplicável]
