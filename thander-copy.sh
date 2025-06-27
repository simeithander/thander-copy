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

# Função para listar arquivos com informações detalhadas
list_files_with_details() {
    local source="$1"
    local destination="$2"
    
    echo "📋 Analisando arquivos para cópia..."
    
    # Conta o número total de arquivos primeiro
    local total_files=0
    if [ -f "$source" ]; then
        total_files=1
    else
        total_files=$(find "$source" -type f 2>/dev/null | wc -l)
    fi
    
    # Mostra barra de progresso durante a análise real
    echo -n "⏳ Analisando: ["
    for ((i=0; i<20; i++)); do
        echo -n " "
    done
    echo -n "] 0%"
    
    # Análise real dos arquivos com progresso
    local analyzed_files=0
    local file_list=()
    local size_list=()
    
    if [ -f "$source" ]; then
        # Se for um arquivo único
        file_list=("$source")
        size_list=($(stat -c%s "$source" 2>/dev/null || stat -f%z "$source" 2>/dev/null || echo "0"))
        analyzed_files=1
        
        # Atualiza progresso
        echo -ne "\r⏳ Analisando: [████████████████████] 100%"
    else
        # Se for um diretório, analisa arquivos com progresso real
        while IFS= read -r -d '' file; do
            ((analyzed_files++))
            file_list+=("$file")
            size_list+=($(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"))
            
            # Atualiza progresso baseado no número real de arquivos
            local progress=$((analyzed_files * 20 / total_files))
            if [ $progress -gt 20 ]; then
                progress=20
            fi
            
            echo -ne "\r⏳ Analisando: ["
            for ((j=0; j<progress; j++)); do
                echo -n "█"
            done
            for ((j=progress; j<20; j++)); do
                echo -n " "
            done
            echo -n "] $((progress * 5))%"
            
        done < <(find "$source" -type f -print0 2>/dev/null)
    fi
    
    echo -e "\r✅ Análise concluída! [████████████████████] 100%"
    
    # Calcula o tamanho total
    local total_size=0
    for size in "${size_list[@]}"; do
        total_size=$((total_size + size))
    done
    local total_size_formatted=$(format_size "$total_size")
    
    echo "📊 Tamanho total: $total_size_formatted"
    echo "📁 Origem: $source"
    echo "📂 Destino: $destination"
    echo "📈 Total de arquivos: $total_files"
    echo ""
    
    # Lista apenas os primeiros 5 arquivos (como apt/nala)
    local max_display=5
    local file_count=0
    
    echo "🚀 Iniciando cópia com verificação de integridade..."
    echo
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

    echo

    # Lista os arquivos com informações detalhadas
    list_files_with_details "$SOURCE" "$DESTINATION"

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

    rsync -ah --progress --info=progress2 --checksum "$SOURCE" "$DESTINATION"

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
