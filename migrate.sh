#!/bin/bash

# Script principal para orquestrar o processo de migração do PostgreSQL 13 para o PostgreSQL 15

# Definir diretório base do projeto
BASE_DIR=$(dirname "$(readlink -f "$0")")
cd "$BASE_DIR" || exit 1

# Carregar configuração
source "$BASE_DIR/config/migration_config.sh"

# Função para exibir o menu
show_menu() {
    clear
    echo "====================================================="
    echo "  MIGRAÇÃO DE GEODATABASE ARCGIS - POSTGRESQL 13 → 15"
    echo "====================================================="
    echo ""
    echo "Selecione uma opção:"
    echo ""
    echo "--- FASE 1: PRÉ-MIGRAÇÃO ---"
    echo "1. Verificar compatibilidade"
    echo "2. Auditar ambiente de origem"
    echo "3. Preparar ambiente de destino"
    echo ""
    echo "--- FASE 2: MIGRAÇÃO ---"
    echo "4. Congelar sistema de origem"
    echo "5. Exportar base de dados"
    echo "6. Importar base de dados"
    echo ""
    echo "--- FASE 3: PÓS-MIGRAÇÃO ---"
    echo "7. Otimizar base de dados"
    echo "8. Validar integração com ArcGIS"
    echo "9. Executar testes de desempenho"
    echo ""
    echo "--- OUTRAS OPÇÕES ---"
    echo "R. Executar procedimento de rollback"
    echo "A. Executar todo o processo automaticamente"
    echo "Q. Sair"
    echo ""
    echo "====================================================="
    echo ""
}

# Função para verificar o resultado da execução de um script
check_result() {
    local script_name=$1
    local result=$2
    
    if [ $result -eq 0 ]; then
        log_message "Script $script_name executado com sucesso"
        return 0
    else
        log_message "ERRO: Script $script_name falhou com código de saída $result"
        
        echo ""
        echo "O script $script_name falhou com código de saída $result."
        echo "Deseja continuar com o próximo passo? (s/n)"
        read -r continue_choice
        
        if [ "$continue_choice" != "s" ] && [ "$continue_choice" != "S" ]; then
            log_message "Processo de migração interrompido pelo usuário após falha em $script_name"
            return 1
        else
            log_message "Continuando o processo de migração após falha em $script_name"
            return 0
        fi
    fi
}

# Função para executar um script com confirmação
run_script_with_confirmation() {
    local script_path=$1
    local script_name=$2
    local auto_mode=$3
    
    if [ "$auto_mode" != "true" ]; then
        echo ""
        echo "Deseja executar o script $script_name? (s/n)"
        read -r choice
        
        if [ "$choice" != "s" ] && [ "$choice" != "S" ]; then
            log_message "Script $script_name ignorado pelo usuário"
            return 0
        fi
    fi
    
    log_message "Iniciando execução do script $script_name"
    
    if [ -x "$script_path" ]; then
        "$script_path"
        check_result "$script_name" $?
        return $?
    else
        chmod +x "$script_path"
        if [ $? -eq 0 ]; then
            "$script_path"
            check_result "$script_name" $?
            return $?
        else
            log_message "ERRO: Não foi possível tornar o script $script_path executável"
            return 1
        fi
    fi
}

# Função para executar todo o processo automaticamente
run_automatic_process() {
    log_message "Iniciando processo de migração automático"
    
    # Fase 1: Pré-migração
    run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/01_verify_compatibility.sh" "Verificação de compatibilidade" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/02_audit_source.sh" "Auditoria do ambiente de origem" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/03_prepare_target.sh" "Preparação do ambiente de destino" "true" || return 1
    
    # Fase 2: Migração
    run_script_with_confirmation "$BASE_DIR/scripts/migration/01_freeze_source.sh" "Congelamento do sistema de origem" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/migration/02_export_database.sh" "Exportação da base de dados" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/migration/03_import_database.sh" "Importação da base de dados" "true" || return 1
    
    # Fase 3: Pós-migração
    run_script_with_confirmation "$BASE_DIR/scripts/post_migration/01_optimize_database.sh" "Otimização da base de dados" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/validation/01_validate_arcgis_integration.sh" "Validação da integração com ArcGIS" "true" || return 1
    run_script_with_confirmation "$BASE_DIR/scripts/validation/02_performance_test.sh" "Testes de desempenho" "true" || return 1
    
    log_message "Processo de migração automático concluído"
    return 0
}

# Função para executar o procedimento de rollback
run_rollback() {
    log_message "Iniciando procedimento de rollback"
    
    echo ""
    echo "ATENÇÃO: O procedimento de rollback irá restaurar o sistema de origem ao seu estado original."
    echo "Isso pode interromper qualquer trabalho em andamento no novo sistema."
    echo "Tem certeza de que deseja continuar? (s/n)"
    read -r rollback_choice
    
    if [ "$rollback_choice" != "s" ] && [ "$rollback_choice" != "S" ]; then
        log_message "Procedimento de rollback cancelado pelo usuário"
        return 0
    fi
    
    run_script_with_confirmation "$BASE_DIR/scripts/rollback/01_restore_source.sh" "Restauração do sistema de origem" "true"
    return $?
}

# Verificar se o diretório de logs existe
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
fi

# Loop principal do menu
while true; do
    show_menu
    read -r option
    
    case $option in
        1)
            run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/01_verify_compatibility.sh" "Verificação de compatibilidade" "false"
            ;;
        2)
            run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/02_audit_source.sh" "Auditoria do ambiente de origem" "false"
            ;;
        3)
            run_script_with_confirmation "$BASE_DIR/scripts/pre_migration/03_prepare_target.sh" "Preparação do ambiente de destino" "false"
            ;;
        4)
            run_script_with_confirmation "$BASE_DIR/scripts/migration/01_freeze_source.sh" "Congelamento do sistema de origem" "false"
            ;;
        5)
            run_script_with_confirmation "$BASE_DIR/scripts/migration/02_export_database.sh" "Exportação da base de dados" "false"
            ;;
        6)
            run_script_with_confirmation "$BASE_DIR/scripts/migration/03_import_database.sh" "Importação da base de dados" "false"
            ;;
        7)
            run_script_with_confirmation "$BASE_DIR/scripts/post_migration/01_optimize_database.sh" "Otimização da base de dados" "false"
            ;;
        8)
            run_script_with_confirmation "$BASE_DIR/scripts/validation/01_validate_arcgis_integration.sh" "Validação da integração com ArcGIS" "false"
            ;;
        9)
            run_script_with_confirmation "$BASE_DIR/scripts/validation/02_performance_test.sh" "Testes de desempenho" "false"
            ;;
        [Rr])
            run_rollback
            ;;
        [Aa])
            run_automatic_process
            ;;
        [Qq])
            log_message "Saindo do script de migração"
            exit 0
            ;;
        *)
            echo "Opção inválida. Pressione Enter para continuar..."
            read -r
            ;;
    esac
    
    # Pausa antes de mostrar o menu novamente
    echo ""
    echo "Pressione Enter para continuar..."
    read -r
done
