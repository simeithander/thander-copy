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

# Função para calcular o tamanho total dos arquivos
calculate_total_size() {
    local source="$1"
    local total_size=0
    
    if [ -f "$source" ]; then
        # Se for um arquivo, pega o tamanho diretamente
        total_size=$(stat -c%s "$source" 2>/dev/null || stat -f%z "$source" 2>/dev/null || echo "0")
    else
        # Se for um diretório, calcula o tamanho total recursivamente
        total_size=$(find "$source" -type f -exec stat -c%s {} \; 2>/dev/null | awk '{sum += $1} END {print sum}')
        if [ -z "$total_size" ]; then
            total_size=$(find "$source" -type f -exec stat -f%z {} \; 2>/dev/null | awk '{sum += $1} END {print sum}')
        fi
        if [ -z "$total_size" ]; then
            total_size=0
        fi
    fi
    
    echo "$total_size"
}

# Função para formatar tamanho em bytes para formato legível
format_size() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    
    while (( bytes >= 1024 )) && (( unit_index < ${#units[@]} - 1 )); do
        bytes=$((bytes / 1024))
        ((unit_index++))
    done
    
    echo "${bytes}${units[$unit_index]}"
}

# Função para formatar tempo em segundos para formato legível
format_time() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Loop principal do script
while true; do
    # Limpa o terminal para uma exibição mais limpa
    clear

    cat << "EOF"
⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡
⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡ THANDER COPY ⚡⚡⚡⚡⚡⚡⚡⚡⚡
⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡⚡

EOF
    echo "🚀 Uma ferramenta poderosa para copiar arquivos e pastas com verificação de integridade."
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

    echo "💬 Lendo arquivos... (isso pode levar algum tempo dependendo do tamanho dos arquivos)"

    # Captura o tempo de início da cópia
    START_TIME=$(date +%s)
    
    # Calcula o tamanho total que será copiado
    TOTAL_SIZE_TO_COPY=$(calculate_total_size "$SOURCE")
    

    # --- Comando de Cópia ---
    # Utiliza o rsync para a cópia. Veja a explicação dos parâmetros abaixo:
    #
    # -a, --archive:     Modo de arquivamento, equivale a -rlptgoD. Copia recursivamente
    #                    e preserva permissões, dono, timestamps, etc.
    # -h, --human-readable: Mostra os números em formato legível para humanos (ex: KB, MB, GB).
    # --progress:        Mostra o progresso detalhado de cada arquivo sendo copiado.
    # --info=progress2:  Mostra o progresso total da transferência, não apenas por arquivo.
    #                    Isso nos dá o percentual geral, tamanho total, velocidade e tempo restante.
    # --checksum:        Força a verificação de checksum em todos os arquivos. Após a cópia,
    #                    o rsync relê o arquivo na origem e no destino para garantir que
    #                    são idênticos. Esta é a verificação de integridade.
    # "$SOURCE":         A origem (entre aspas para tratar nomes com espaços).
    # "$DESTINATION":    O destino (entre aspas).

    # Executa o rsync com feedback visual em tempo real
    rsync -ah --progress --info=progress2 --checksum "$SOURCE" "$DESTINATION"
    
    # Captura o código de saída do rsync. 0 significa sucesso.
    EXIT_CODE=$?
    
    # Captura o tempo de fim da cópia
    END_TIME=$(date +%s)
    
    # Calcula o tempo decorrido
    ELAPSED_TIME=$((END_TIME - START_TIME))
    

    # --- Verificação Final ---

    echo "----------------------------------------------------"

    # Verifica o código de saída para determinar se tudo correu bem
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ Cópia concluída e dados verificados com sucesso!"
        echo "Os dados copiados de '$SOURCE' e '$DESTINATION' foram verificados com sucesso e estão idênticos."
        echo ""
        echo "📊 Estatísticas da cópia:"
        echo "   ⏱️  Tempo decorrido: $(format_time $ELAPSED_TIME)"
        echo "   📦 Tamanho copiado: $(format_size $TOTAL_SIZE_TO_COPY)"
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
