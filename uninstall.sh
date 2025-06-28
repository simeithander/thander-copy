#!/bin/bash

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="thander-copy"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo "🚫 Este desinstalador precisa ser executado como root (use: sudo ./uninstall.sh)"
    exit 1
fi

# Verifica se o script está instalado
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ O script '$SCRIPT_NAME' não está instalado em $INSTALL_DIR"
    echo "ℹ️ Nada para desinstalar."
    exit 0
fi

# Confirma a desinstalação
echo "⚠️  Você está prestes a desinstalar o $SCRIPT_NAME"
echo "📁 Arquivo: $SCRIPT_PATH"
echo ""
read -p "🤔 Tem certeza que deseja continuar? (s/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Desinstalação cancelada pelo usuário."
    exit 0
fi

# Remove o script
echo "🗑️  Removendo $SCRIPT_NAME..."
rm -f "$SCRIPT_PATH"

# Verifica se a remoção foi bem-sucedida
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "✅ $SCRIPT_NAME foi desinstalado com sucesso!"
    echo "ℹ️ O comando 'thander-copy' não estará mais disponível."
else
    echo "❌ Erro ao remover $SCRIPT_NAME"
    exit 1
fi 