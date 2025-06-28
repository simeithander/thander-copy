#!/bin/bash

# Funções de cor para terminal
color_reset='\033[0m'
color_red='\033[1;31m'
color_green='\033[1;32m'
color_yellow='\033[1;33m'
color_blue='\033[1;34m'
color_cyan='\033[1;36m'
color_white='\033[1;37m'
color_magenta='\033[1;35m'
color_gray='\033[0;37m'

print_banner() {
    echo -e "${color_cyan}"
    echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    echo "┃   ⚡  THANDER COPY - Cópia poderosa com integridade e estilo!   ⚡   ┃"
    echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
    echo "Versão: 1.0.1"
    echo -e "${color_reset}"
}

print_separator() {
    echo -e "${color_gray}──────────────────────────────────────────────────────────────────────${color_reset}"
}

print_box() {
    local title="$1"
    shift
    local content=("$@")
    echo -e "${color_blue}┌─[ ${color_white}${title}${color_blue} ]${color_reset}"
    for line in "${content[@]}"; do
        echo -e "${color_blue}│${color_reset} $line"
    done
    echo -e "${color_blue}└${color_reset}"
}

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
        total_size=$(find "$source" -type f -exec stat -c%s {} \; 2>/dev/null | awk '{sum += $1} END {printf "%.0f", sum}')
        if [ -z "$total_size" ] || [ "$total_size" = "0" ]; then
            total_size=$(find "$source" -type f -exec stat -f%z {} \; 2>/dev/null | awk '{sum += $1} END {printf "%.0f", sum}')
        fi
        if [ -z "$total_size" ] || [ "$total_size" = "0" ]; then
            total_size=0
        fi
    fi
    
    # Garante que o resultado seja um número inteiro
    total_size=$(echo "$total_size" | awk '{printf "%.0f", $1}')
    
    echo "$total_size"
}

# Função para formatar tamanho em bytes para formato legível
format_size() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    
    # Converte para número inteiro se estiver em notação científica
    bytes=$(echo "$bytes" | awk '{printf "%.0f", $1}')
    
    # Usa awk para fazer a divisão e evitar problemas com números grandes
    while (( unit_index < ${#units[@]} - 1 )); do
        local result=$(echo "$bytes 1024" | awk '{printf "%.0f", $1 / $2}')
        if (( result < 1 )); then
            break
        fi
        bytes=$result
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

# Função para animação do Pacman com timer
pacman_animation() {
    local start_time=$(date +%s)
    local pacman_frames=("C" "c" "C" "c")
    local dot_frames=("●" "○" "●" "○")
    local frame_index=0
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        local progress=$(( (elapsed % 20) ))
        # Cria a barra de progresso com Pacman
        local bar=""
        for ((i=0; i<progress; i++)); do
            bar="${bar}█"
        done
        if [ $progress -lt 20 ]; then
            bar="${bar}${pacman_frames[$frame_index]}"
        fi
        for ((i=progress+1; i<20; i++)); do
            bar="${bar}${dot_frames[$frame_index]}"
        done
        frame_index=$((frame_index + 1))
        if [ $frame_index -ge ${#pacman_frames[@]} ]; then
            frame_index=0
        fi
        echo -ne "\r⏳ [$bar] $(format_time $elapsed)"
        sleep 0.2
    done
}

# Loop principal do script
while true; do
    clear
    print_banner
    echo -e "${color_white}🚀 Uma ferramenta poderosa para copiar arquivos e pastas com verificação de integridade.${color_reset}"
    echo -e "${color_yellow}💡 Para sair do script, pressione Ctrl + C${color_reset}"
    print_separator
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

    echo "💬 Lendo arquivos..."
    # Inicia a animação de spinner em background
    (
        read_frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
        frame_index=0
        while true; do
            echo -ne "\r${read_frames[$frame_index]} Lendo arquivos..."
            frame_index=$((frame_index + 1))
            if [ $frame_index -ge ${#read_frames[@]} ]; then
                frame_index=0
            fi
            sleep 0.1
        done
    ) &
    READ_ANIMATION_PID=$!
    # Calcula o tamanho total que será copiado (isso leva tempo)
    TOTAL_SIZE_TO_COPY=$(calculate_total_size "$SOURCE")
    # Para a animação de leitura
    kill $READ_ANIMATION_PID 2>/dev/null
    wait $READ_ANIMATION_PID 2>/dev/null
    echo -e "\r✅ Análise concluída!"
    echo "📊 Tamanho total: $(format_size $TOTAL_SIZE_TO_COPY)"
    echo ""

    # Captura o tempo de início da cópia
    START_TIME=$(date +%s)
    
    echo "🔄 Iniciando cópia..."
    
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
    
    # Se o rsync foi bem-sucedido, sincroniza os dados com animação
    if [ $EXIT_CODE -eq 0 ]; then
        echo "🔄 Iniciando sincronização..."
        # Inicia animação de sincronização em background
        (
            sync_frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
            frame_index=0
            while true; do
                echo -ne "\r${sync_frames[$frame_index]} Sincronizando dados..."
                frame_index=$((frame_index + 1))
                if [ $frame_index -ge ${#sync_frames[@]} ]; then
                    frame_index=0
                fi
                sleep 0.1
            done
        ) &
        SYNC_ANIMATION_PID=$!
        
        # Executa o sync
        sync
        
        # Para a animação de sincronização
        kill $SYNC_ANIMATION_PID 2>/dev/null
        wait $SYNC_ANIMATION_PID 2>/dev/null
        echo -e "\r✅ Sincronização concluída!"
    fi
    
    echo "✅ Cópia concluída!"
    
    # Captura o tempo de fim da cópia
    END_TIME=$(date +%s)
    
    # Calcula o tempo decorrido
    ELAPSED_TIME=$((END_TIME - START_TIME))
    

    # --- Verificação Final ---

    print_separator

    if [ $EXIT_CODE -eq 0 ]; then
        print_box "Resumo da Cópia" \
            "${color_green}✅ Dados verificados com sucesso!${color_reset}" \
            "${color_cyan}Origem:${color_reset} $SOURCE" \
            "${color_cyan}Destino:${color_reset} $DESTINATION" \
            "${color_cyan}Tempo:${color_reset} $(format_time $ELAPSED_TIME)" \
            "${color_cyan}Tamanho:${color_reset} $(format_size $TOTAL_SIZE_TO_COPY)"
    else
        print_box "Erro" \
            "${color_red}❌ Ocorreu um erro durante a cópia ou a verificação.${color_reset}" \
            "${color_yellow}Código de erro:${color_reset} $EXIT_CODE"
    fi
    print_separator
    echo
    echo "🔄 Preparando para próxima cópia..."
    echo "Pressione Enter para continuar ou Ctrl + C para sair..."
    read
done
