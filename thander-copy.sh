#!/bin/bash

# Função para limpar caminhos removendo aspas simples e duplas
clean_path() {
    local path="$1"
    
    # Remove aspas simples do início e fim
    while [[ "${path:0:1}" == "'" && "${path: -1}" == "'" ]]; do
        path="${path:1:-1}"
    done
    
    # Remove aspas duplas do início e fim
    while [[ "${path:0:1}" == '"' && "${path: -1}" == '"' ]]; do
        path="${path:1:-1}"
    done
    
    # Remove espaços em branco no início e fim
    path=$(echo "$path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "$path"
}

# Loop principal do script
while true; do
    # Limpa o terminal para uma exibição mais limpa
    clear

    cat << "EOF"
⚡⚡⚡⚡⚡⚡⚡⚡⚡
⚡ THANDER COPY ⚡
⚡⚡⚡⚡⚡⚡⚡⚡⚡

EOF
    echo "Uma ferramenta poderosa para copiar arquivos e pastas com verificação de integridade."
    echo "💡 Para sair do script, pressione Ctrl + C"
    echo

    # Solicita ao usuário o arquivo ou pasta de origem
    # O `read -e` permite o uso do autocompletar com a tecla TAB
    echo "Arraste ou digite o caminho do arquivo/pasta de ORIGEM e pressione Enter:"
    read -e SOURCE
    echo

    # Solicita ao usuário a pasta de destino
    echo "Arraste ou digite o caminho da pasta de DESTINO e pressione Enter:"
    read -e DESTINATION
    echo

    # Limpa os caminhos de origem e destino
    SOURCE=$(clean_path "$SOURCE")
    DESTINATION=$(clean_path "$DESTINATION")

    # --- Validações Iniciais ---

    # Verifica se a origem realmente existe
    if [ ! -e "$SOURCE" ]; then
        echo
        echo "❌ ERRO: O caminho de origem '$SOURCE' não foi encontrado."
        echo "Pressione Enter para tentar novamente..."
        read
        continue
    fi

    # Verifica se o destino é um diretório válido
    if [ ! -d "$DESTINATION" ]; then
        echo
        echo "❌ ERRO: O diretório de destino '$DESTINATION' não existe ou não é válido."
        echo "Pressione Enter para tentar novamente..."
        read
        continue
    fi

    echo
    echo "Origem:  $SOURCE"
    echo "Destino: $DESTINATION"
    echo
    echo "Copiando os arquivos..."
    echo "----------------------------------------------------"

    # --- Comando de Cópia ---
    # Utiliza o rsync para a cópia. Veja a explicação dos parâmetros abaixo:
    #
    # -a, --archive:     Modo de arquivamento, equivale a -rlptgoD. Copia recursivamente
    #                    e preserva permissões, dono, timestamps, etc.
    # -h, --human-readable: Mostra os números em formato legível para humanos (ex: KB, MB, GB).
    # --info=progress2:  Mostra o progresso total da transferência, não apenas por arquivo.
    #                    Isso nos dá o percentual geral, tamanho total, velocidade e tempo restante.
    # --checksum:        Força a verificação de checksum em todos os arquivos. Após a cópia,
    #                    o rsync relê o arquivo na origem e no destino para garantir que
    #                    são idênticos. Esta é a verificação de integridade.
    # "$SOURCE":         A origem (entre aspas para tratar nomes com espaços).
    # "$DESTINATION":    O destino (entre aspas).

    rsync -ah --info=progress2 --checksum "$SOURCE" "$DESTINATION"

    # Captura o código de saída do rsync. 0 significa sucesso.
    EXIT_CODE=$?

    # --- Verificação Final ---

    echo "----------------------------------------------------"

    # Verifica o código de saída para determinar se tudo correu bem
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ Cópia concluída e dados verificados com sucesso!"
        echo "Os arquivos em '$SOURCE' e '$DESTINATION' são idênticos."
    else
        echo "❌ ATENÇÃO: Ocorreu um erro durante a cópia ou a verificação."
        echo "O processo retornou o código de erro: $EXIT_CODE"
    fi

    echo "----------------------------------------------------"
    echo
    echo "🔄 Preparando para próxima cópia..."
    echo "Pressione Enter para continuar ou Ctrl + C para sair..."
    read
done
