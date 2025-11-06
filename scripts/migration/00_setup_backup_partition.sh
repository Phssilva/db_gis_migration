#!/bin/bash

# Script para configurar e verificar a partição de backup no servidor de destino

# Carrega a configuração
source ../../config/migration_config.sh

log_message "Iniciando configuração da partição de backup..."

# Verificar se o script está sendo executado como root
if [ "$(id -u)" -ne 0 ]; then
    log_message "ERRO: Este script deve ser executado como root"
    log_message "Por favor, execute com sudo: sudo $0"
    exit 1
fi

log_message "======================================================"
log_message "CONFIGURAÇÃO DA PARTIÇÃO DE BACKUP"
log_message "======================================================"
log_message ""

# Listar todas as partições disponíveis
log_message "Partições disponíveis no sistema:"
log_message ""
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
log_message ""

# Mostrar uso de disco atual
log_message "Uso de disco atual:"
log_message ""
df -h | grep -E "Filesystem|/dev/"
log_message ""

# Verificar se o diretório de backup configurado existe
log_message "Diretório de backup configurado: $BACKUP_DIR"

if [ -d "$BACKUP_DIR" ]; then
    log_message "O diretório $BACKUP_DIR já existe"
    
    # Verificar se é um ponto de montagem
    if mountpoint -q "$BACKUP_DIR"; then
        log_message "✓ $BACKUP_DIR é um ponto de montagem"
        
        # Obter informações sobre a partição montada
        DEVICE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $1}')
        SIZE=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $2}')
        USED=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $3}')
        AVAILABLE=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $4}')
        USE_PERCENT=$(df -h "$BACKUP_DIR" | awk 'NR==2 {print $5}')
        
        log_message ""
        log_message "Informações da partição:"
        log_message "  Dispositivo: $DEVICE"
        log_message "  Tamanho total: $SIZE"
        log_message "  Usado: $USED"
        log_message "  Disponível: $AVAILABLE"
        log_message "  Uso: $USE_PERCENT"
    else
        log_message "⚠ AVISO: $BACKUP_DIR existe mas NÃO é um ponto de montagem"
        log_message "Isso significa que o backup será armazenado na mesma partição do sistema"
        log_message "Recomenda-se usar uma partição dedicada para o backup"
    fi
    
    # Verificar permissões
    log_message ""
    log_message "Verificando permissões..."
    OWNER=$(stat -c '%U:%G' "$BACKUP_DIR")
    PERMS=$(stat -c '%a' "$BACKUP_DIR")
    log_message "  Proprietário: $OWNER"
    log_message "  Permissões: $PERMS"
    
    # Testar escrita
    TEST_FILE="$BACKUP_DIR/.write_test_$$"
    if touch "$TEST_FILE" 2>/dev/null; then
        log_message "  ✓ Teste de escrita: OK"
        rm -f "$TEST_FILE"
    else
        log_message "  ✗ ERRO: Sem permissão de escrita em $BACKUP_DIR"
        log_message ""
        log_message "Para corrigir, execute:"
        log_message "  sudo chown -R postgres:postgres $BACKUP_DIR"
        log_message "  sudo chmod 755 $BACKUP_DIR"
    fi
else
    log_message "✗ O diretório $BACKUP_DIR NÃO existe"
    log_message ""
    log_message "Opções para configurar:"
    log_message ""
    log_message "1. Se você tem uma partição dedicada (RECOMENDADO):"
    log_message "   # Criar o ponto de montagem"
    log_message "   sudo mkdir -p $BACKUP_DIR"
    log_message ""
    log_message "   # Montar a partição (substitua /dev/sdXN pelo dispositivo correto)"
    log_message "   sudo mount /dev/sdXN $BACKUP_DIR"
    log_message ""
    log_message "   # Para montar automaticamente no boot, adicione ao /etc/fstab:"
    log_message "   /dev/sdXN $BACKUP_DIR ext4 defaults 0 2"
    log_message ""
    log_message "2. Se você quer usar um diretório normal:"
    log_message "   sudo mkdir -p $BACKUP_DIR"
    log_message "   sudo chown postgres:postgres $BACKUP_DIR"
    log_message "   sudo chmod 755 $BACKUP_DIR"
    log_message ""
    
    read -p "Deseja criar o diretório agora? (s/n): " CREATE_DIR
    if [ "$CREATE_DIR" = "s" ] || [ "$CREATE_DIR" = "S" ]; then
        log_message "Criando diretório $BACKUP_DIR..."
        if mkdir -p "$BACKUP_DIR"; then
            chown postgres:postgres "$BACKUP_DIR"
            chmod 755 "$BACKUP_DIR"
            log_message "✓ Diretório criado com sucesso"
        else
            log_message "✗ ERRO ao criar diretório"
            exit 1
        fi
    fi
fi

log_message ""
log_message "======================================================"
log_message "RECOMENDAÇÕES"
log_message "======================================================"
log_message ""
log_message "1. Use uma partição dedicada para o backup (recomendado)"
log_message "   ✓ Evita problemas de espaço na partição do sistema"
log_message "   ✓ Melhora o desempenho de I/O"
log_message "   ✓ Facilita a gestão de espaço"
log_message ""
log_message "2. Certifique-se de que a partição tem espaço suficiente"
log_message "   ✓ Tamanho recomendado: pelo menos 1.5x o tamanho da base de dados"
log_message "   ✓ Para uma base de 500GB, recomenda-se 750GB ou mais"
log_message ""
log_message "3. Configure a partição para montar automaticamente no boot"
log_message "   ✓ Adicione uma entrada no /etc/fstab"
log_message "   ✓ Exemplo: /dev/sdb1 $BACKUP_DIR ext4 defaults 0 2"
log_message ""
log_message "4. Verifique as permissões do diretório"
log_message "   ✓ O usuário postgres deve ter permissão de escrita"
log_message "   ✓ Permissões recomendadas: 755 (drwxr-xr-x)"
log_message ""
log_message "5. Monitore o espaço em disco durante a migração"
log_message "   ✓ Use: watch -n 5 df -h $BACKUP_DIR"
log_message ""

log_message "Configuração da partição de backup concluída"
exit 0