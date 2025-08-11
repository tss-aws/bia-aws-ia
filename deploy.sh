#!/bin/bash

# Script wrapper para deploy ECS - Projeto BIA
# Este script facilita o uso do deploy-ecs.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/scripts/deploy-ecs.sh"

# Verificar se o script principal existe
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo "❌ Script de deploy não encontrado: $DEPLOY_SCRIPT"
    exit 1
fi

# Carregar configurações se existirem
CONFIG_FILE="$SCRIPT_DIR/scripts/deploy-config"
if [ -f "$CONFIG_FILE" ]; then
    echo "📋 Carregando configurações de: $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# Executar o script principal com todos os argumentos
exec "$DEPLOY_SCRIPT" "$@"
