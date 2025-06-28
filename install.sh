#!/bin/bash

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="thander-copy"
SCRIPT_PATH="$INSTALL_DIR/$SCRIPT_NAME"

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo "🚫 Este instalador precisa ser executado como root (use: sudo ./install-thander-copy.sh)"
    exit 1
fi

# Verifica dependências mínimas
for cmd in bash rsync awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ Dependência ausente: $cmd"
        exit 1
    fi
done

# Verifica se o script existe no diretório atual
if [ ! -f "thander-copy.sh" ]; then
    echo "❌ Arquivo 'thander-copy.sh' não encontrado no diretório atual."
    exit 1
fi

# Copia o script para o diretório de execução e garante permissão
cp "thander-copy.sh" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

echo "✅ Script instalado ou atualizado com sucesso!"
echo "🔧 Agora você pode executá-lo a partir de qualquer lugar com o comando:"
echo "    thander-copy"
