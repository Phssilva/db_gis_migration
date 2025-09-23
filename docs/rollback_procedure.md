# Procedimento de Rollback - Migração PostgreSQL 13 para 15

## Visão Geral

Este documento detalha o procedimento de rollback para restaurar o sistema de origem ao seu estado original em caso de falha durante o processo de migração da geodatabase ArcGIS do PostgreSQL 13.18 para o PostgreSQL 15.12.

O procedimento de rollback é projetado para ser executado em qualquer ponto do processo de migração, garantindo que o sistema de origem possa ser restaurado ao seu estado operacional anterior à migração.

## Pré-requisitos para Rollback

Antes de iniciar o procedimento de rollback, verifique se os seguintes pré-requisitos foram atendidos:

1. **Acesso aos servidores**:
   - Acesso de administrador ao servidor de origem (PostgreSQL 13.18)
   - Acesso de administrador ao servidor de destino (PostgreSQL 15.12)

2. **Arquivos de backup**:
   - Verifique se o arquivo de informações de restauração foi criado durante a fase de congelamento do sistema de origem
   - O caminho para este arquivo é armazenado em `logs/restore_info_path.txt`

3. **Serviços ArcGIS**:
   - Tenha acesso para reiniciar os serviços ArcGIS que foram parados antes da migração

## Cenários de Rollback

O procedimento de rollback pode ser necessário em diferentes cenários:

### Cenário 1: Falha durante a fase de pré-migração

Se ocorrer uma falha durante a fase de pré-migração (verificação de compatibilidade, auditoria do ambiente de origem, preparação do ambiente de destino), o rollback geralmente não é necessário, pois o sistema de origem não foi modificado.

**Ações necessárias**:
- Corrija os problemas identificados
- Reinicie o processo de migração

### Cenário 2: Falha durante a exportação da base de dados

Se ocorrer uma falha durante a exportação da base de dados, o sistema de origem pode estar com acesso limitado devido às alterações no arquivo `pg_hba.conf`.

**Ações necessárias**:
- Execute o procedimento de rollback para restaurar o `pg_hba.conf` original
- Reinicie os serviços ArcGIS que foram parados

### Cenário 3: Falha durante a importação da base de dados

Se ocorrer uma falha durante a importação da base de dados, o sistema de origem ainda está com acesso limitado, mas o sistema de destino pode ter uma base de dados parcialmente restaurada.

**Ações necessárias**:
- Execute o procedimento de rollback para restaurar o `pg_hba.conf` original
- Reinicie os serviços ArcGIS que foram parados
- Opcionalmente, limpe a base de dados parcialmente restaurada no servidor de destino

### Cenário 4: Falha durante a fase de pós-migração

Se ocorrer uma falha durante a fase de pós-migração (otimização, validação, testes de desempenho), o sistema de origem ainda está com acesso limitado, mas o sistema de destino já tem a base de dados restaurada.

**Ações necessárias**:
- Execute o procedimento de rollback para restaurar o `pg_hba.conf` original
- Reinicie os serviços ArcGIS que foram parados
- Decida se deseja manter o sistema de destino para continuar a migração posteriormente

### Cenário 5: Problemas após a conclusão da migração

Se surgirem problemas após a conclusão da migração (por exemplo, problemas de integração com ArcGIS, desempenho insatisfatório), pode ser necessário reverter para o sistema original.

**Ações necessárias**:
- Execute o procedimento de rollback para restaurar o `pg_hba.conf` original
- Reinicie os serviços ArcGIS e reconfigure-os para apontar para o servidor de origem
- Opcionalmente, mantenha o sistema de destino para investigação e correção dos problemas

## Procedimento de Rollback Passo a Passo

### Passo 1: Iniciar o procedimento de rollback

Execute o script de rollback através do menu principal de migração:

```bash
./migrate.sh
```

Selecione a opção "R" para executar o procedimento de rollback.

Alternativamente, execute o script de rollback diretamente:

```bash
./scripts/rollback/01_restore_source.sh
```

### Passo 2: Confirmar a execução do rollback

O script solicitará confirmação antes de prosseguir com o rollback. Confirme digitando "s" quando solicitado.

```
ATENÇÃO: O procedimento de rollback irá restaurar o sistema de origem ao seu estado original.
Isso pode interromper qualquer trabalho em andamento no novo sistema.
Tem certeza de que deseja continuar? (s/n): s
```

### Passo 3: Restauração do pg_hba.conf original

O script restaurará o arquivo `pg_hba.conf` original no servidor de origem, permitindo que todas as conexões normais sejam restabelecidas.

### Passo 4: Verificação do servidor PostgreSQL de origem

O script verificará se o servidor PostgreSQL de origem está em execução e se é possível estabelecer conexão com a base de dados.

### Passo 5: Verificação de conexões ativas

O script verificará se há conexões ativas no servidor de origem e exibirá o número de conexões.

### Passo 6: Gerenciamento do servidor PostgreSQL de destino

O script verificará se o servidor PostgreSQL de destino está em execução e perguntará se você deseja pará-lo.

```
Deseja parar o servidor PostgreSQL de destino? (s/n): s
```

### Passo 7: Reiniciar os serviços ArcGIS

Após a conclusão do script de rollback, você precisará reiniciar manualmente os serviços ArcGIS que foram parados antes da migração:

```bash
# Exemplo de comando para reiniciar o ArcGIS Server (o comando exato pode variar)
sudo systemctl start arcgisserver

# Exemplo de comando para reiniciar o Portal for ArcGIS
sudo systemctl start portal

# Exemplo de comando para reiniciar o ArcGIS Data Store
sudo systemctl start datastore
```

### Passo 8: Verificar o sistema restaurado

Após a conclusão do rollback, verifique se o sistema de origem está funcionando corretamente:

1. **Verifique o servidor PostgreSQL**:
   - Verifique se o servidor PostgreSQL está em execução
   - Verifique se é possível conectar à base de dados

   ```bash
   psql -h <SOURCE_HOST> -p <SOURCE_PORT> -U <SOURCE_USER> -d <SOURCE_DB> -c "SELECT 1;"
   ```

2. **Verifique os serviços ArcGIS**:
   - Verifique se os serviços ArcGIS estão em execução
   - Verifique se os serviços ArcGIS conseguem conectar à base de dados

   ```bash
   sudo systemctl status arcgisserver
   sudo systemctl status portal
   sudo systemctl status datastore
   ```

3. **Verifique os clientes ArcGIS**:
   - Verifique se os clientes ArcGIS Pro conseguem conectar à base de dados
   - Verifique se os serviços de mapa e de feições estão funcionando corretamente

## Relatório de Rollback

Após a conclusão do procedimento de rollback, um relatório será gerado no diretório `logs/` com o nome `rollback_report_YYYYMMDD_HHMMSS.txt`. Este relatório contém informações sobre as ações realizadas durante o rollback e os próximos passos recomendados.

## Próximos Passos Após o Rollback

Após a conclusão bem-sucedida do rollback, considere os seguintes próximos passos:

1. **Investigar a causa da falha**:
   - Analise os logs de migração para identificar a causa da falha
   - Corrija os problemas identificados

2. **Planejar uma nova tentativa de migração**:
   - Agende uma nova janela de manutenção
   - Atualize o plano de migração com base nas lições aprendidas

3. **Comunicar o status aos usuários**:
   - Informe os usuários que o sistema foi restaurado ao seu estado original
   - Forneça informações sobre a próxima tentativa de migração

## Considerações Importantes

### Tempo de Inatividade

O procedimento de rollback é projetado para minimizar o tempo de inatividade, mas ainda requer que os serviços ArcGIS sejam reiniciados. Planeje o rollback de acordo com as necessidades de disponibilidade do sistema.

### Dados Modificados Durante a Migração

Se os usuários modificaram dados no sistema de origem após o início da migração (o que não deveria acontecer se o sistema foi congelado corretamente), essas modificações serão preservadas após o rollback.

### Limpeza do Servidor de Destino

Após o rollback, o servidor de destino pode ter uma base de dados parcialmente restaurada. Considere limpar essa base de dados se não planeja continuar a migração imediatamente:

```bash
# Conectar ao PostgreSQL no servidor de destino
psql -h <TARGET_HOST> -p <TARGET_PORT> -U <TARGET_USER> -d postgres

# Listar todas as bases de dados
\l

# Remover a base de dados parcialmente restaurada
DROP DATABASE <TARGET_DB>;
```

## Solução de Problemas Durante o Rollback

### Problema: Não é possível restaurar o pg_hba.conf original

**Sintoma**: O script de rollback não consegue restaurar o arquivo `pg_hba.conf` original.

**Solução**:
1. Verifique se o arquivo de backup do `pg_hba.conf` existe no diretório indicado pelo arquivo de informações de restauração
2. Restaure manualmente o arquivo `pg_hba.conf` original:
   ```bash
   sudo cp <caminho_do_backup_pg_hba.conf> <caminho_do_pg_hba.conf>
   sudo chown postgres:postgres <caminho_do_pg_hba.conf>
   sudo chmod 600 <caminho_do_pg_hba.conf>
   sudo systemctl reload postgresql
   ```

### Problema: Não é possível conectar ao servidor PostgreSQL de origem

**Sintoma**: O script de rollback não consegue conectar ao servidor PostgreSQL de origem.

**Solução**:
1. Verifique se o servidor PostgreSQL está em execução:
   ```bash
   sudo systemctl status postgresql
   ```
2. Se não estiver em execução, inicie o serviço:
   ```bash
   sudo systemctl start postgresql
   ```
3. Verifique se as credenciais estão corretas no arquivo `config/migration_config.sh`

### Problema: Os serviços ArcGIS não iniciam após o rollback

**Sintoma**: Os serviços ArcGIS não iniciam após o rollback.

**Solução**:
1. Verifique os logs dos serviços ArcGIS para identificar o problema:
   ```bash
   sudo journalctl -u arcgisserver
   sudo journalctl -u portal
   sudo journalctl -u datastore
   ```
2. Verifique se o servidor PostgreSQL de origem está acessível pelos serviços ArcGIS
3. Verifique se as conexões de banco de dados nos serviços ArcGIS estão configuradas corretamente

## Contato para Suporte

Em caso de problemas durante o procedimento de rollback, entre em contato com:

- Equipe de Suporte: [email@suaempresa.com]
- Administrador do Banco de Dados: [dba@suaempresa.com]
