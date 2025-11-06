# Guia de Migração de Geodatabase ArcGIS - PostgreSQL 13 para 15

## Visão Geral

Este guia detalha o processo de migração de uma geodatabase ArcGIS do PostgreSQL 13.18 para o PostgreSQL 15.12 em ambiente Ubuntu. O processo foi projetado para minimizar o tempo de inatividade e garantir a integridade dos dados durante a migração.

**Importante**: Este guia assume que o PostgreSQL 15.12 **já está instalado e configurado** no servidor de destino. O foco principal é a exportação do dump da base de dados de origem, restauração no servidor de destino e configuração da biblioteca ST_Geometry.

## Pré-requisitos

Antes de iniciar o processo de migração, verifique se os seguintes pré-requisitos foram atendidos:

1. **Acesso aos servidores**:
   - Acesso de administrador ao servidor de origem (PostgreSQL 13.18)
   - Acesso de administrador ao servidor de destino (com PostgreSQL 15.12 já instalado)

2. **Biblioteca ST_Geometry**:
   - Baixe a biblioteca ST_Geometry compatível com PostgreSQL 15 do portal My Esri
   - Atualize o caminho da biblioteca no arquivo `config/migration_config.sh`

3. **Espaço em disco**:
   - Verifique se há espaço suficiente no diretório de backup para armazenar uma cópia completa da base de dados
   - Verifique se há espaço suficiente no servidor de destino para a nova base de dados

4. **Janela de manutenção**:
   - Agende uma janela de manutenção com tempo suficiente para a migração
   - Notifique todos os usuários e partes interessadas sobre o período de inatividade

5. **Backup de segurança**:
   - Realize um backup completo da base de dados antes de iniciar a migração
   - Verifique se o backup pode ser restaurado em caso de falha

## Estrutura do Projeto

O projeto de migração está organizado da seguinte forma:

```
.
├── backups/            # Diretório para armazenar backups
├── config/             # Arquivos de configuração
│   └── migration_config.sh  # Configurações da migração
├── docs/               # Documentação
│   ├── migration_guide.md   # Este guia
│   └── rollback_procedure.md  # Procedimento de rollback
├── logs/               # Logs gerados durante a migração
├── migrate.sh          # Script principal de migração
└── scripts/            # Scripts para o processo de migração
    ├── pre_migration/  # Scripts para preparação e análise
    │   ├── 01_verify_compatibility.sh
    │   ├── 02_audit_source.sh
    │   └── 03_prepare_target.sh
    ├── migration/      # Scripts para exportação e importação
    │   ├── 01_freeze_source.sh
    │   ├── 02_export_database.sh
    │   └── 03_import_database.sh
    ├── post_migration/ # Scripts para otimização pós-migração
    │   └── 01_optimize_database.sh
    ├── validation/     # Scripts para validação e testes
    │   ├── 01_validate_arcgis_integration.sh
    │   └── 02_performance_test.sh
    └── rollback/       # Scripts para procedimentos de rollback
        └── 01_restore_source.sh
```

## Configuração

Antes de iniciar a migração, é necessário configurar os parâmetros no arquivo `config/migration_config.sh`:

1. **Ambiente de Origem**:
   - `SOURCE_HOST`: Endereço IP ou nome do servidor de origem
   - `SOURCE_PORT`: Porta do PostgreSQL de origem (geralmente 5432)
   - `SOURCE_DB`: Nome da base de dados a ser migrada
   - `SOURCE_USER`: Usuário com permissões para leitura da base de dados
   - `SOURCE_PASSWORD`: Senha do usuário (considere usar variáveis de ambiente)

2. **Ambiente de Destino**:
   - `TARGET_HOST`: Endereço IP ou nome do servidor de destino
   - `TARGET_PORT`: Porta do PostgreSQL de destino (geralmente 5432)
   - `TARGET_DB`: Nome da base de dados no destino (geralmente o mesmo)
   - `TARGET_USER`: Usuário com permissões de administrador
   - `TARGET_PASSWORD`: Senha do usuário (considere usar variáveis de ambiente)
   - `TARGET_DATA_DIR`: Diretório para os dados do PostgreSQL 15

3. **Configuração de Backup**:
   - `BACKUP_DIR`: Diretório para armazenar os backups
   - `BACKUP_JOBS`: Número de jobs paralelos para pg_dump/pg_restore

4. **Biblioteca ST_Geometry**:
   - `ST_GEOMETRY_PATH`: Caminho para a biblioteca ST_Geometry baixada do portal My Esri

5. **Configuração do PostgreSQL**:
   - Parâmetros de memória, WAL, paralelismo, etc.

## Processo de Migração

O processo de migração é dividido em três fases principais:

### Fase 1: Pré-migração

1. **Verificar compatibilidade**:
   - Verifica se todos os componentes necessários estão disponíveis
   - Verifica a compatibilidade entre as versões do PostgreSQL, PostGIS e ArcGIS

2. **Auditar ambiente de origem**:
   - Coleta informações sobre o ambiente de origem
   - Identifica tabelas, índices, extensões, configurações, etc.

3. **Preparar ambiente de destino**:
   - Verifica se o PostgreSQL 15.12 e o PostGIS estão instalados no servidor de destino
   - Configura o locale do sistema
   - Ajusta os parâmetros de configuração do PostgreSQL (postgresql.conf, pg_hba.conf)
   - Instala a biblioteca ST_Geometry

### Fase 2: Migração

4. **Congelar sistema de origem**:
   - Para os serviços ArcGIS que acessam a base de dados
   - Limita as conexões à base de dados para evitar modificações durante a exportação

5. **Exportar base de dados**:
   - Exporta os objetos globais (roles, tablespaces)
   - Exporta a base de dados principal usando pg_dump

6. **Importar base de dados**:
   - Restaura os objetos globais no servidor de destino
   - Importa a base de dados usando pg_restore

### Fase 3: Pós-migração

7. **Otimizar base de dados**:
   - Atualiza estatísticas do otimizador
   - Reindexação e vacuum
   - Configura parâmetros de autovacuum para tabelas grandes e espaciais

8. **Validar integração com ArcGIS**:
   - Verifica se o tipo ST_Geometry está disponível
   - Verifica as tabelas do sistema da geodatabase
   - Cria uma lista de verificações para integração com ArcGIS

9. **Executar testes de desempenho**:
   - Compara o desempenho entre o PostgreSQL 13 e o PostgreSQL 15
   - Gera um relatório com os resultados dos testes

## Execução da Migração

Para iniciar o processo de migração, execute o script principal:

```bash
./migrate.sh
```

O script apresentará um menu interativo com as seguintes opções:

1. **Execução passo a passo**:
   - Selecione cada opção do menu sequencialmente para executar o processo passo a passo
   - Cada passo solicitará confirmação antes de prosseguir

2. **Execução automática**:
   - Selecione a opção "A" para executar todo o processo automaticamente
   - O processo será executado sem intervenção manual, exceto em caso de erro

3. **Rollback**:
   - Em caso de falha, selecione a opção "R" para executar o procedimento de rollback
   - O sistema de origem será restaurado ao seu estado original

## Monitoramento e Logs

Durante a migração, todos os eventos são registrados em arquivos de log no diretório `logs/`:

- `migration_YYYYMMDD_HHMMSS.log`: Log principal da migração
- `audit_YYYYMMDD_HHMMSS/`: Resultados da auditoria do ambiente de origem
- `validation_YYYYMMDD_HHMMSS/`: Resultados da validação da integração com ArcGIS
- `performance_YYYYMMDD_HHMMSS/`: Resultados dos testes de desempenho

## Procedimento de Rollback

Em caso de falha durante a migração, siga o procedimento de rollback detalhado em `docs/rollback_procedure.md`. O procedimento restaurará o sistema de origem ao seu estado original.

## Verificações Pós-Migração

Após a conclusão bem-sucedida da migração, realize as seguintes verificações:

1. **Conexão com ArcGIS Pro**:
   - Crie uma nova conexão de banco de dados no ArcGIS Pro
   - Verifique se todas as tabelas e feature classes são visíveis
   - Verifique se é possível visualizar os dados espaciais no mapa
   - Verifique se é possível editar os dados

2. **Conexão com ArcGIS Server**:
   - Registre a conexão de banco de dados no ArcGIS Server Manager
   - Verifique se o ArcGIS Server consegue acessar os dados
   - Publique um serviço de mapa de teste
   - Publique um serviço de feições de teste

3. **Funcionalidades da Geodatabase**:
   - Verifique se as relações entre tabelas estão funcionando
   - Verifique se os domínios estão funcionando
   - Verifique se as regras de topologia estão funcionando
   - Verifique se o versionamento está funcionando

4. **Desempenho**:
   - Verifique o tempo de carregamento de mapas
   - Verifique o tempo de resposta de consultas espaciais
   - Compare o desempenho com o sistema anterior

## Solução de Problemas

### Problemas Comuns e Soluções

1. **Erro ao restaurar objetos globais**:
   - Isso pode ocorrer se os roles já existirem no sistema de destino
   - Verifique os erros no log e determine se são aceitáveis
   - Continue com a restauração da base de dados

2. **Erro ao restaurar a base de dados**:
   - Verifique se a biblioteca ST_Geometry está instalada corretamente
   - Verifique se o PostGIS está instalado no servidor de destino
   - Verifique se há espaço suficiente no disco

3. **Problemas de conexão com ArcGIS**:
   - Verifique se o tipo ST_Geometry está disponível
   - Verifique se as tabelas do sistema da geodatabase foram criadas
   - Verifique se a versão do PostGIS é compatível com o ArcGIS

4. **Problemas de desempenho**:
   - Ajuste os parâmetros de configuração do PostgreSQL 15
   - Reindexe tabelas específicas que apresentaram desempenho inferior
   - Verifique se os índices espaciais estão sendo utilizados corretamente

### Contato para Suporte

Em caso de problemas durante a migração, entre em contato com:

- Equipe de Suporte: [email@suaempresa.com]
- Administrador do Banco de Dados: [dba@suaempresa.com]

## Referências

1. Documentação do PostgreSQL: [https://www.postgresql.org/docs/15/index.html](https://www.postgresql.org/docs/15/index.html)
2. Documentação do PostGIS: [https://postgis.net/documentation/](https://postgis.net/documentation/)
3. Matriz de Compatibilidade ArcGIS-PostgreSQL: [https://doc.arcgis.com/pt-br/system-requirements/latest/database/postgresql-requirements.htm](https://doc.arcgis.com/pt-br/system-requirements/latest/database/postgresql-requirements.htm)
4. Portal My Esri (para download da biblioteca ST_Geometry): [https://my.esri.com/](https://my.esri.com/)
