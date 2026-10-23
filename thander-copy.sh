#!/usr/bin/env bash
#
# ⚡ THANDER COPY — copia e move arquivos com integridade verificada.
#
# Etapas de cada operação:
#   1. Análise      tamanho, quantidade, espaço livre e limitações do destino
#   2. Cópia        rsync com perfil adequado ao sistema de arquivos de destino
#   3. Gravação     força a escrita do cache no dispositivo (syncfs) com progresso
#   4. Verificação  checksum relendo o destino do disco, ou tamanho + data
#   5. Remoção      só ao mover: apaga a origem depois da verificação

if [ -z "${BASH_VERSION:-}" ]; then
    echo "O thander-copy precisa ser executado com o bash." >&2
    exit 1
fi
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
    echo "O thander-copy precisa do bash 4.4 ou superior." >&2
    exit 1
fi

VERSION="2.0.0"

set -o pipefail
shopt -s extglob

ORIG_PWD=$PWD
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/thander-copy
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/thander-copy.XXXXXX") || exit 1
ERR_LOG=$TMP_DIR/erros.log

OP_RUNNING=0
INTERRUPTED=0
JOB_PID=""
SPIN_PID=""
SYNCER_PID=""
DASH=()
declare -i DASH_N=0 DIRTY_KB=0 NOW_MS=0 BANNER_SHOWN=0 WIZ_PRINTED=0

# ───────────────────────────── Aparência ─────────────────────────────

setup_colors() {
    IS_TTY=0
    [[ -t 1 ]] && IS_TTY=1
    if (( IS_TTY )) && [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
        C0=$'\e[0m' CB=$'\e[1m'
        CRED=$'\e[38;5;203m' CGRN=$'\e[38;5;114m' CYLW=$'\e[38;5;221m'
        CCYN=$'\e[38;5;81m' CGRY=$'\e[38;5;245m' CTRK=$'\e[38;5;238m'
        BAR_EMPTY="━"
        TRUECOLOR=0
        [[ ${COLORTERM:-} == @(truecolor|24bit) ]] && TRUECOLOR=1
    else
        C0="" CB="" CRED="" CGRN="" CYLW="" CCYN="" CGRY="" CTRK=""
        BAR_EMPTY="·"
        TRUECOLOR=0
    fi
    SEP=" ${CGRY}·${C0} "
}

update_layout() {
    local cols
    cols=$(tput cols 2>/dev/null)
    [[ $cols =~ ^[0-9]+$ ]] || cols=${COLUMNS:-80}
    COLS=$cols
    UI_W=$(( COLS - 4 ))
    (( UI_W > 78 )) && UI_W=78
    (( UI_W < 36 )) && UI_W=36
    BAR_W=$(( UI_W - 12 ))
    build_gradient
}

# Degradê ciano → violeta usado na barra de progresso e no título.
build_gradient() {
    local -a pal=(51 45 39 33 69 105 141 177)
    local i n=$BAR_W d r g b
    GRAD=()
    d=$(( n > 1 ? n - 1 : 1 ))
    for (( i = 0; i < n; i++ )); do
        if [[ -z $C0 ]]; then
            GRAD[i]=""
        elif (( TRUECOLOR )); then
            r=$(( 34 + (168 - 34) * i / d ))
            g=$(( 211 + (85 - 211) * i / d ))
            b=$(( 238 + (247 - 238) * i / d ))
            GRAD[i]=$'\e[38;2;'"$r;$g;${b}m"
        else
            GRAD[i]=$'\e[38;5;'"${pal[i * ${#pal[@]} / n]}m"
        fi
    done
}

hide_cursor() { if (( IS_TTY )); then printf '\e[?25l'; fi; }
show_cursor() { if (( IS_TTY )); then printf '\e[?25h'; fi; }

# ───────────────────────────── Utilitários ─────────────────────────────
# Funções de formatação devolvem o resultado em REPLY para evitar subshells
# dentro dos laços de progresso.

now_ms() {
    if [[ -n ${EPOCHREALTIME:-} ]]; then
        local t=${EPOCHREALTIME//[!0-9]/}
        NOW_MS=$(( 10#$t / 1000 ))
    else
        printf -v NOW_MS '%(%s)T' -1
        NOW_MS=$(( NOW_MS * 1000 ))
    fi
}

fmt_size() {
    local -i b=${1:-0} x i=0
    local -a u=(B KB MB GB TB PB)
    if (( b < 1024 )); then
        REPLY="$b B"
        return
    fi
    x=$(( b * 10 ))
    while (( x >= 10240 && i < 5 )); do
        x=$(( x / 1024 ))
        i+=1
    done
    REPLY="$(( x / 10 )).$(( x % 10 )) ${u[i]}"
}

fmt_dur() {
    local -i s=${1:-0}
    (( s < 0 )) && s=0
    if (( s >= 3600 )); then
        printf -v REPLY '%d:%02d:%02d' $(( s / 3600 )) $(( s % 3600 / 60 )) $(( s % 60 ))
    else
        printf -v REPLY '%02d:%02d' $(( s / 60 )) $(( s % 60 ))
    fi
}

fmt_ms() {
    local -i ms=${1:-0}
    if (( ms < 10000 )); then
        REPLY="$(( ms / 1000 )).$(( ms % 1000 / 100 ))s"
    else
        fmt_dur $(( ms / 1000 ))
    fi
}

fmt_permil() { printf -v REPLY '%3d.%d%%' $(( $1 / 10 )) $(( $1 % 10 )); }

fmt_int() {
    local n=$1 out=""
    while (( ${#n} > 3 )); do
        out=".${n: -3}$out"
        n=${n:0:${#n}-3}
    done
    REPLY=$n$out
}

plural() {
    fmt_int "$1"
    if (( $1 == 1 )); then REPLY="$REPLY $2"; else REPLY="$REPLY $3"; fi
}

repeat() {
    printf -v REPLY '%*s' "$2" ''
    REPLY=${REPLY// /$1}
}

pad_r() {
    local s=$1 w=$2
    if (( ${#s} < w )); then
        printf -v REPLY '%s%*s' "$s" $(( w - ${#s} )) ''
    else
        REPLY=$s
    fi
}

vis_len() {
    local s=${1//$'\e'\[*([0-9;])m/}
    REPLY=${#s}
}

trunc_mid() {
    local s=$1 m=$2 h t
    if (( ${#s} <= m )); then
        REPLY=$s
    elif (( m < 5 )); then
        REPLY=${s:0:m}
    else
        h=$(( (m - 1) / 2 ))
        t=$(( m - 1 - h ))
        REPLY="${s:0:h}…${s: -t}"
    fi
}

home_path() {
    if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then REPLY="~${1#"$HOME"}"; else REPLY=$1; fi
}

read_dirty() {
    local k v rest
    DIRTY_KB=0
    [[ -r /proc/meminfo ]] || return 0
    while read -r k v rest; do
        case $k in Dirty:|Writeback:) DIRTY_KB+=v ;; esac
    done </proc/meminfo
}

# Soma os bytes lidos (rchar) por um processo e todos os seus descendentes.
proc_tree_rchar() {
    local -a queue=("$1") kids
    local -i i=0 sum=0
    local p k v
    while (( i < ${#queue[@]} )); do
        p=${queue[i]}
        i+=1
        if [[ -r /proc/$p/task/$p/children ]]; then
            kids=()
            read -ra kids 2>/dev/null </proc/"$p"/task/"$p"/children
            queue+=("${kids[@]}")
        fi
        [[ -r /proc/$p/io ]] || continue
        while read -r k v; do
            if [[ $k == rchar: ]]; then
                sum+=v
                break
            fi
        done 2>/dev/null </proc/"$p"/io
    done
    REPLY=$sum
}

# Bytes já gravados (wchar) pelo processo receptor do rsync. Numa cópia local o
# rsync forma a cadeia remetente → gerador → receptor; o receptor é a folha e só
# escreve nos arquivos de destino, o que dá o progresso real entre as
# atualizações (≈1 por segundo) que o próprio rsync imprime.
proc_leaf_wchar() {
    local p=$1 k v
    local -a kids
    REPLY=0
    while [[ -r /proc/$p/task/$p/children ]]; do
        kids=()
        read -ra kids 2>/dev/null </proc/"$p"/task/"$p"/children
        (( ${#kids[@]} )) || break
        p=${kids[0]}
    done
    [[ -r /proc/$p/io ]] || return 0
    while read -r k v; do
        if [[ $k == wchar: ]]; then
            REPLY=$v
            break
        fi
    done 2>/dev/null </proc/"$p"/io
}

if sync --help 2>&1 | grep -q -- '--file-system'; then SYNC_FS=1; else SYNC_FS=0; fi

sync_path() {
    if (( SYNC_FS )); then
        sync -f "$1" 2>/dev/null || sync
    else
        sync
    fi
}

# ───────────────────────────── Componentes de UI ─────────────────────────────

banner() {
    if (( IS_TTY )); then
        printf '\e[H\e[2J'
    elif (( BANNER_SHOWN )); then
        return
    fi
    BANNER_SHOWN=1
    local title="THANDER COPY" out="" i n=12
    for (( i = 0; i < n; i++ )); do out+="${GRAD[i * BAR_W / n]}${title:i:1}"; done
    printf '\n  %s⚡%s %s%s%s  %sv%s%s\n' "$CYLW" "$C0" "$CB" "$out" "$C0" "$CGRY" "$VERSION" "$C0"
    printf '  %sCópia e movimentação de arquivos com integridade verificada%s\n' "$CGRY" "$C0"
    repeat "─" "$UI_W"
    printf '  %s%s%s\n\n' "$CTRK" "$REPLY" "$C0"
}

# Barra contínua com resolução de meio caractere.
render_bar() {
    local -i p=$1 w=$BAR_W i halves full
    local fixed=${2:-}
    (( p < 0 )) && p=0
    (( p > 1000 )) && p=1000
    halves=$(( p * w * 2 / 1000 ))
    full=$(( halves / 2 ))
    BAR=""
    for (( i = 0; i < full; i++ )); do BAR+="${fixed:-${GRAD[i]}}━"; done
    if (( full < w )); then
        if (( halves % 2 )); then
            BAR+="${fixed:-${GRAD[full]}}╸"
            i=$(( full + 1 ))
        else
            i=$full
        fi
        BAR+=$CTRK
        for (( ; i < w; i++ )); do BAR+=$BAR_EMPTY; done
    fi
    BAR+=$C0
}

# Barra indeterminada (um segmento que desliza) para etapas sem total conhecido.
render_pulse() {
    local -i w=$BAR_W seg i pos
    seg=$(( w / 5 ))
    pos=$(( $1 % (w + seg) - seg ))
    BAR=""
    for (( i = 0; i < w; i++ )); do
        if (( i >= pos && i < pos + seg )); then BAR+="${GRAD[i]}━"; else BAR+="${CTRK}${BAR_EMPTY}"; fi
    done
    BAR+=$C0
}

# Rótulo alinhado das linhas de painel (em LBL, preservando REPLY).
lbl() {
    local r=$REPLY
    pad_r "$1" 12
    LBL="    ${CGRY}${REPLY}${C0} "
    REPLY=$r
}

# Redesenha o painel (array DASH) no mesmo lugar da tela.
dash_draw() {
    local out="" l plain
    (( IS_TTY )) || return 0
    (( DASH_N )) && printf -v out '\e[%dA' "$DASH_N"
    for l in "${DASH[@]}"; do
        vis_len "$l"
        if (( REPLY > COLS - 1 )); then
            plain=${l//$'\e'\[*([0-9;])m/}
            l="${plain:0:COLS-2}…"
        fi
        out+=$'\r\e[K'"$l"$'\n'
    done
    printf '%s' "$out"
    DASH_N=${#DASH[@]}
}

dash_clear() {
    (( DASH_N )) && printf '\e[%dA\e[J' "$DASH_N"
    DASH_N=0
}

# phase_line <ok|warn|fail|skip> <etapa> <detalhe> [duração em ms]
phase_line() {
    local icon t=""
    case $1 in
        ok)   icon="${CGRN}✓" ;;
        warn) icon="${CYLW}!" ;;
        fail) icon="${CRED}✗" ;;
        *)    icon="${CGRY}–" ;;
    esac
    if [[ -n ${4:-} ]]; then
        fmt_ms "$4"
        t="  ${CGRY}${REPLY}${C0}"
    fi
    pad_r "$2" 12
    printf '  %s%s %s%s%s %s%s\n' "$icon" "$C0" "$CB" "$REPLY" "$C0" "$3" "$t"
}

# box <cor> <título> <linhas...>
box() {
    local color=$1 title=$2 line
    local -i pad
    shift 2
    repeat "─" $(( UI_W - 5 - ${#title} ))
    printf '  %s╭─ %s%s%s %s%s╮%s\n' "$color" "$CB" "$title" "$C0" "$color" "$REPLY" "$C0"
    for line in "$@"; do
        vis_len "$line"
        pad=$(( UI_W - 4 - REPLY ))
        (( pad < 0 )) && pad=0
        printf '  %s│%s %s%*s %s│%s\n' "$color" "$C0" "$line" "$pad" '' "$color" "$C0"
    done
    repeat "─" $(( UI_W - 2 ))
    printf '  %s╰%s╯%s\n' "$color" "$REPLY" "$C0"
}

kv() {
    pad_r "$1" 13
    REPLY="${CGRY}${REPLY}${C0}$2"
}

spinner_start() {
    local msg=$1
    (( IS_TTY )) || return 0
    hide_cursor
    (
        frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
        i=0
        start=$SECONDS
        while :; do
            printf '\r  %s%s%s %s %s%ds%s\e[K' "$CCYN" "${frames[i++ % 10]}" "$C0" "$msg" \
                "$CGRY" $(( SECONDS - start )) "$C0"
            sleep 0.08
        done
    ) &
    SPIN_PID=$!
}

spinner_stop() {
    if [[ -n $SPIN_PID ]]; then
        kill "$SPIN_PID" 2>/dev/null
        wait "$SPIN_PID" 2>/dev/null
        SPIN_PID=""
        printf '\r\e[K'
    fi
    show_cursor
}

# choose <variável> <pergunta> <índice padrão> "Rótulo|descrição"...
# Navegação com ↑/↓ (ou j/k), atalhos numéricos e Enter.
choose() {
    local __out=$1 __q=$2
    local -i __sel=$3 __n __i
    shift 3
    local -a __opts=("$@")
    local __key __rest __label __desc __buf
    __n=${#__opts[@]}
    printf '  %s?%s %s%s%s\n' "$CCYN" "$C0" "$CB" "$__q" "$C0"
    hide_cursor
    while :; do
        __buf=""
        for (( __i = 0; __i < __n; __i++ )); do
            __label=${__opts[__i]%%|*}
            __desc=""
            [[ ${__opts[__i]} == *"|"* ]] && __desc=${__opts[__i]#*|}
            if (( __i == __sel )); then
                __buf+=$'\r\e[K'"    ${CCYN}❯ ${CB}${__label}${C0}  ${CGRY}${__desc}${C0}"$'\n'
            else
                __buf+=$'\r\e[K'"      ${__label}  ${CTRK}${__desc}${C0}"$'\n'
            fi
        done
        printf '%s' "$__buf"
        IFS= read -rsn1 __key || quit
        case $__key in
            $'\e')
                IFS= read -rsn2 -t 0.05 __rest
                case $__rest in
                    '[A'|'OA') __sel=$(( (__sel - 1 + __n) % __n )) ;;
                    '[B'|'OB') __sel=$(( (__sel + 1) % __n )) ;;
                esac
                ;;
            k|K) __sel=$(( (__sel - 1 + __n) % __n )) ;;
            j|J|$'\t') __sel=$(( (__sel + 1) % __n )) ;;
            [1-9])
                if (( __key <= __n )); then
                    __sel=$(( __key - 1 ))
                    break
                fi
                ;;
            '') break ;;
        esac
        printf '\e[%dA' "$__n"
    done
    printf '\e[%dA\e[J' $(( __n + 1 ))
    printf '  %s✓%s %s %s%s%s\n' "$CGRN" "$C0" "$__q" "$CCYN" "${__opts[__sel]%%|*}" "$C0"
    show_cursor
    printf -v "$__out" '%s' "$__sel"
}

ask_line() {
    local prompt="  › "
    printf '  %s?%s %s%s%s  %s%s%s\n' "$CCYN" "$C0" "$CB" "$1" "$C0" "$CGRY" "$2" "$C0"
    [[ -n $C0 ]] && prompt=$'  \001'"$CCYN"$'\002›\001'"$C0"$'\002 '
    show_cursor
    IFS= read -e -r -p "$prompt" LINE || quit
}

setup_history() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0
    HISTFILE=$STATE_DIR/historico
    HISTSIZE=300
    history -r "$HISTFILE" 2>/dev/null
}

remember() {
    [[ -n ${HISTFILE:-} && -n ${1//[[:space:]]/} ]] || return 0
    history -s "$1"
    history -w "$HISTFILE" 2>/dev/null
}

# ───────────────────────────── Caminhos ─────────────────────────────

# Converte a entrada do usuário em uma lista de caminhos (PARSED). Aceita
# caminhos arrastados pelo gerenciador de arquivos ('...' ou "..."), espaços
# escapados com \, URIs file:// e, se a linha inteira existir, um único caminho
# com espaços sem aspas.
parse_paths() {
    local s=$1 tok="" q="" c p
    local -i i inword=0
    PARSED=()
    s=${s##+([[:space:]])}
    s=${s%%+([[:space:]])}
    [[ -z $s ]] && return
    if [[ -e $s || -L $s ]]; then
        PARSED=("$s")
    else
        for (( i = 0; i < ${#s}; i++ )); do
            c=${s:i:1}
            if [[ -n $q ]]; then
                if [[ $c == "$q" ]]; then
                    q=""
                elif [[ $q == '"' && $c == '\' ]]; then
                    i+=1
                    tok+=${s:i:1}
                else
                    tok+=$c
                fi
                continue
            fi
            case $c in
                "'"|'"') q=$c; inword=1 ;;
                '\') i+=1; tok+=${s:i:1}; inword=1 ;;
                ' '|$'\t')
                    if (( inword )); then PARSED+=("$tok"); tok=""; inword=0; fi
                    ;;
                *) tok+=$c; inword=1 ;;
            esac
        done
        (( inword )) && PARSED+=("$tok")
    fi
    for i in "${!PARSED[@]}"; do
        p=${PARSED[i]}
        if [[ $p == file://* ]]; then
            p=${p#file://}
            printf -v p '%b' "${p//%/\\x}"
        fi
        [[ $p == "~" || $p == "~/"* ]] && p=$HOME${p:1}
        PARSED[i]=$p
    done
}

# Caminho absoluto, normalizado e sem barra final (sem resolver links).
normalize_path() {
    local p=$1
    [[ $p != /* ]] && p=$ORIG_PWD/$p
    REPLY=$(realpath -s -m -- "$p" 2>/dev/null) || REPLY=$p
}

resolve_sources() {
    local p
    local -A seen=()
    SOURCES=()
    if (( $# == 0 )); then
        WIZ_ERR="Nenhum caminho informado."
        return 1
    fi
    for p in "$@"; do
        normalize_path "$p"
        p=$REPLY
        if [[ ! -e $p && ! -L $p ]]; then
            WIZ_ERR="Origem não encontrada: $p"
            return 1
        fi
        if [[ $p == / ]]; then
            WIZ_ERR="Não é possível usar a raiz do sistema (/) como origem."
            return 1
        fi
        [[ -n ${seen[$p]:-} ]] && continue
        seen[$p]=1
        SOURCES+=("$p")
    done
}

sources_label() {
    home_path "${SOURCES[0]}"
    trunc_mid "$REPLY" "${1:-50}"
    if (( ${#SOURCES[@]} == 2 )); then
        REPLY+="  ${CGRY}(+1 item)${C0}"
    elif (( ${#SOURCES[@]} > 2 )); then
        REPLY+="  ${CGRY}(+$(( ${#SOURCES[@]} - 1 )) itens)${C0}"
    fi
}

# ───────────────────────────── Destino ─────────────────────────────

detect_dest() {
    local info pinfo rm="" hp="" tran="" model="" label="" realfs="" pk="" name
    local -a parts=()
    DEST_FSTYPE="" DEST_DEV="" DEST_DISK="" DEST_REMOVABLE=0 DEST_DESC="" DEST_NAME=""
    DEST_MNT=$(stat -c %m -- "$DEST" 2>/dev/null)
    if command -v findmnt >/dev/null 2>&1; then
        DEST_FSTYPE=$(findmnt -n -o FSTYPE -T "$DEST" 2>/dev/null | head -n1)
        DEST_DEV=$(findmnt -n -o SOURCE -T "$DEST" 2>/dev/null | head -n1)
        DEST_DEV=${DEST_DEV%%\[*}
    fi
    [[ -z $DEST_FSTYPE ]] && DEST_FSTYPE=$(stat -f -c %T -- "$DEST" 2>/dev/null)

    if [[ $DEST_DEV == /dev/* ]] && command -v lsblk >/dev/null 2>&1; then
        pinfo=$(lsblk -ndP -o PKNAME,FSTYPE,LABEL "$DEST_DEV" 2>/dev/null)
        [[ $pinfo =~ PKNAME=\"([^\"]*)\" ]] && pk=${BASH_REMATCH[1]}
        [[ $pinfo =~ FSTYPE=\"([^\"]*)\" ]] && realfs=${BASH_REMATCH[1]}
        [[ $pinfo =~ LABEL=\"([^\"]*)\" ]] && label=${BASH_REMATCH[1]}
        DEST_DISK=${pk:+/dev/$pk}
        DEST_DISK=${DEST_DISK:-$DEST_DEV}
        info=$(lsblk -ndP -o RM,HOTPLUG,TRAN,MODEL "$DEST_DISK" 2>/dev/null)
        [[ $info =~ RM=\"([^\"]*)\" ]] && rm=${BASH_REMATCH[1]}
        [[ $info =~ HOTPLUG=\"([^\"]*)\" ]] && hp=${BASH_REMATCH[1]}
        [[ $info =~ TRAN=\"([^\"]*)\" ]] && tran=${BASH_REMATCH[1]}
        [[ $info =~ MODEL=\"([^\"]*)\" ]] && model=${BASH_REMATCH[1]}
        [[ $rm == 1 || $hp == 1 || $tran == usb ]] && DEST_REMOVABLE=1
    fi
    # fuseblk esconde o sistema real (ntfs-3g, exfat-fuse...).
    [[ $DEST_FSTYPE == fuseblk && -n $realfs ]] && DEST_FSTYPE=$realfs

    name=${label:-${model:-${DEST_MNT##*/}}}
    DEST_NAME=${name:-dispositivo}
    [[ -n $name ]] && parts+=("$name")
    [[ -n $DEST_FSTYPE ]] && parts+=("$DEST_FSTYPE")
    if [[ $tran == usb ]]; then
        parts+=("USB")
    elif (( DEST_REMOVABLE )); then
        parts+=("removível")
    fi
    local IFS=$'\x1f'
    DEST_DESC=${parts[*]}
    DEST_DESC=${DEST_DESC//$'\x1f'/ · }
}

# Escolhe as opções do rsync conforme o sistema de arquivos de destino. Em
# FAT/exFAT não existem dono, permissões nem links: pedir isso ao rsync gera
# erros (código 23) mesmo com todos os dados copiados.
fs_profile() {
    FS_NO_LINKS=0 FS_FAT32=0 FS_WIN_NAMES=0
    case ${DEST_FSTYPE,,} in
        vfat|msdos|fat|fat16|fat32)
            COPY_ARGS=(-rt --modify-window=2)
            FS_NO_LINKS=1 FS_FAT32=1 FS_WIN_NAMES=1
            ;;
        exfat)
            COPY_ARGS=(-rt --modify-window=2)
            FS_NO_LINKS=1 FS_WIN_NAMES=1
            ;;
        ntfs|ntfs3|ntfs-3g)
            COPY_ARGS=(-rlt)
            ;;
        *)
            COPY_ARGS=(-a)
            ;;
    esac
    COPY_ARGS+=(--no-inc-recursive)
}

same_mount() {
    local a b
    a=$(stat -c '%d:%m' -- "$1" 2>/dev/null) || return 1
    b=$(stat -c '%d:%m' -- "$2" 2>/dev/null) || return 1
    [[ $a == "$b" ]]
}

# ───────────────────────────── Análise ─────────────────────────────

analyze() {
    local out
    spinner_start "Analisando os arquivos de origem…"
    out=$(find "${SOURCES[@]}" \
            \( -type f -printf 'f %s\n' \) -o \( -type d -printf 'd\n' \) \
            -o \( -type l -printf 'l\n' \) -o -printf 'o\n' 2>"$TMP_DIR/find.err" \
        | awk '{ c[$1]++; if ($1 == "f") s += $2 }
               END { printf "%.0f %d %d %d %d\n", s, c["f"], c["d"], c["l"], c["o"] }')
    read -r TOTAL_BYTES TOTAL_FILES TOTAL_DIRS TOTAL_LINKS TOTAL_OTHER <<<"$out"
    UNREADABLE=$(grep -c . "$TMP_DIR/find.err" 2>/dev/null)
    BIG_FILES=()
    BAD_NAMES=0
    if (( FS_FAT32 )); then
        mapfile -t BIG_FILES < <(find "${SOURCES[@]}" -type f -size +4294967295c 2>/dev/null | head -n 3)
    fi
    if (( FS_WIN_NAMES )); then
        BAD_NAMES=$(find "${SOURCES[@]}" -name '*[:*?"<>|\\]*' 2>/dev/null | wc -l)
    fi
    DEST_FREE=$(df -P -B1 -- "$DEST" 2>/dev/null | awk 'NR == 2 { print $4 }')
    spinner_stop
}

# ───────────────────────────── Assistente ─────────────────────────────

show_wizard() {
    local -i i=0
    banner
    # Fora de um terminal não há como redesenhar: imprime só as respostas novas.
    (( IS_TTY )) || i=$WIZ_PRINTED
    for (( ; i < ${#WIZ[@]}; i++ )); do
        pad_r "${WIZ[i]%%|*}" 10
        printf '  %s✓%s %s%s%s %s\n' "$CGRN" "$C0" "$CGRY" "$REPLY" "$C0" "${WIZ[i]#*|}"
    done
    (( IS_TTY || ${#WIZ[@]} > WIZ_PRINTED )) && (( ${#WIZ[@]} )) && echo
    WIZ_PRINTED=${#WIZ[@]}
    if [[ -n $WIZ_ERR ]]; then
        printf '  %s✗ %s%s\n\n' "$CRED" "$WIZ_ERR" "$C0"
        WIZ_ERR=""
    fi
}

cli_fail() {
    printf '  %s✗ %s%s\n' "$CRED" "$1" "$C0" >&2
    exit 1
}

ask_sources() {
    if (( CLI_MODE )); then
        resolve_sources "${PRESET_SOURCES[@]}" || cli_fail "$WIZ_ERR"
        return
    fi
    while :; do
        show_wizard
        ask_line "Origem" "arraste arquivos/pastas para cá ou digite o caminho (TAB completa)"
        [[ -z ${LINE//[[:space:]]/} ]] && continue
        remember "$LINE"
        parse_paths "$LINE"
        resolve_sources "${PARSED[@]}" && return
    done
}

# Valida o destino em REPLY; devolve 1 com WIZ_ERR preenchido se inválido.
check_dest() {
    local d=$1 src sreal dreal parent sel
    if [[ -e $d && ! -d $d ]]; then
        WIZ_ERR="O destino não é uma pasta: $d"
        return 1
    fi
    if [[ ! -e $d ]]; then
        if (( CLI_MODE )); then
            (( ASSUME_YES )) || { WIZ_ERR="A pasta de destino não existe: $d (use -y para criá-la)"; return 1; }
        else
            printf '  %s!%s A pasta %s%s%s não existe.\n' "$CYLW" "$C0" "$CB" "$d" "$C0"
            choose sel "Criar a pasta?" 0 "Criar|mkdir -p" "Informar outro destino|"
            (( sel == 0 )) || return 1
        fi
        if ! mkdir -p -- "$d" 2>"$TMP_DIR/mkdir.err"; then
            WIZ_ERR="Não foi possível criar a pasta: $(<"$TMP_DIR/mkdir.err")"
            return 1
        fi
    fi
    if [[ ! -w $d ]]; then
        WIZ_ERR="Sem permissão de escrita em: $d"
        return 1
    fi
    dreal=$(realpath -e -- "$d")
    for src in "${SOURCES[@]}"; do
        parent=$(realpath -e -- "${src%/*}/" 2>/dev/null)
        if [[ $parent == "$dreal" ]]; then
            WIZ_ERR="O destino é a própria pasta onde '${src##*/}' já está."
            return 1
        fi
        if [[ -d $src && ! -L $src ]]; then
            sreal=$(realpath -e -- "$src")
            if [[ $dreal == "$sreal" || $dreal == "$sreal"/* ]]; then
                WIZ_ERR="O destino está dentro da origem '${src##*/}'."
                return 1
            fi
        fi
    done
}

ask_dest() {
    while :; do
        if (( CLI_MODE )); then
            PARSED=("$PRESET_DEST")
        else
            show_wizard
            ask_line "Destino" "pasta onde os itens serão colocados"
            [[ -z ${LINE//[[:space:]]/} ]] && continue
            remember "$LINE"
            parse_paths "$LINE"
        fi
        if (( ${#PARSED[@]} != 1 )); then
            WIZ_ERR="Informe apenas uma pasta de destino."
        else
            normalize_path "${PARSED[0]}"
            DEST=$REPLY
            check_dest "$DEST" && return 0
        fi
        (( CLI_MODE )) && cli_fail "$WIZ_ERR"
    done
}

# Monta a lista de avisos do plano a partir da análise.
collect_warnings() {
    local src name
    WARNS=()
    CONFLICTS=()
    DEST_ITEMS=()
    for src in "${SOURCES[@]}"; do
        name=${src##*/}
        DEST_ITEMS+=("$DEST/$name")
        [[ -e $DEST/$name || -L $DEST/$name ]] && CONFLICTS+=("$name")
    done

    FAST_MOVE=0
    if [[ $MODE == move ]] && (( ${#CONFLICTS[@]} == 0 )); then
        FAST_MOVE=1
        for src in "${SOURCES[@]}"; do
            same_mount "$src" "$DEST" || { FAST_MOVE=0; break; }
        done
    fi
    (( FAST_MOVE )) && return

    if [[ $DEST_FREE =~ ^[0-9]+$ ]] && (( TOTAL_BYTES > DEST_FREE )); then
        fmt_size "$TOTAL_BYTES"; local need=$REPLY
        fmt_size "$DEST_FREE"
        WARNS+=("${CRED}Espaço insuficiente:${C0} são necessários $need e há $REPLY livres.")
    fi
    if (( ${#BIG_FILES[@]} )); then
        home_path "${BIG_FILES[0]}"
        trunc_mid "$REPLY" 40
        WARNS+=("${CRED}Arquivos acima de 4 GB não cabem em FAT32${C0} (ex.: $REPLY). Use exFAT ou NTFS.")
    fi
    if (( BAD_NAMES )); then
        local fail="não poderão ser copiados"
        (( BAD_NAMES == 1 )) && fail="não poderá ser copiado"
        plural "$BAD_NAMES" "item" "itens"
        WARNS+=("$REPLY com caracteres não permitidos em ${DEST_FSTYPE} (: * ? \" < > | \\) $fail.")
    fi
    if (( FS_NO_LINKS && TOTAL_LINKS )); then
        plural "$TOTAL_LINKS" "link simbólico será ignorado" "links simbólicos serão ignorados"
        WARNS+=("$REPLY (${DEST_FSTYPE} não suporta links).")
    fi
    if (( UNREADABLE )); then
        plural "$UNREADABLE" "item não pôde ser lido" "itens não puderam ser lidos"
        WARNS+=("$REPLY na origem (permissão negada?).")
    fi
    if (( ${#CONFLICTS[@]} )); then
        trunc_mid "${CONFLICTS[0]}" 30
        local more=""
        (( ${#CONFLICTS[@]} > 1 )) && more=" e mais $(( ${#CONFLICTS[@]} - 1 ))"
        WARNS+=("'$REPLY'$more já existe no destino: arquivos idênticos serão pulados e os diferentes, atualizados.")
    fi
}

verify_label() {
    case $1 in
        full)  REPLY="Completa — checksum relendo os dados do disco" ;;
        quick) REPLY="Rápida — tamanho e data de modificação" ;;
        *)     REPLY="Nenhuma" ;;
    esac
}

plan_box() {
    local -a L=()
    local w=$(( UI_W - 4 - 13 )) op
    [[ $MODE == move ]] && op="Mover" || op="Copiar"
    (( FAST_MOVE )) && op+="  ${CGRY}(mesmo disco: instantâneo)${C0}"
    kv "Operação" "$op"; L+=("$REPLY")
    sources_label "$w"; kv "Origem" "$REPLY"; L+=("$REPLY")
    home_path "$DEST"; trunc_mid "$REPLY" "$w"; kv "Destino" "$REPLY"; L+=("$REPLY")
    [[ -n $DEST_DESC ]] && { trunc_mid "$DEST_DESC" "$w"; kv "Dispositivo" "$REPLY"; L+=("$REPLY"); }
    fmt_size "$TOTAL_BYTES"; local size=$REPLY
    plural "$TOTAL_FILES" "arquivo" "arquivos"; local files=$REPLY
    plural "$TOTAL_DIRS" "pasta" "pastas"
    kv "Volume" "$size${SEP}$files${SEP}$REPLY"; L+=("$REPLY")
    if (( ! FAST_MOVE )); then
        if [[ $DEST_FREE =~ ^[0-9]+$ ]]; then fmt_size "$DEST_FREE"; kv "Espaço livre" "$REPLY"; L+=("$REPLY"); fi
        verify_label "$VERIFY"; kv "Verificação" "$REPLY"; L+=("$REPLY")
    fi
    box "$CCYN" "Resumo da operação" "${L[@]}"
    local warn
    for warn in "${WARNS[@]}"; do printf '  %s!%s %s\n' "$CYLW" "$C0" "$warn"; done
    echo
}

# Devolve 0 para executar, 1 para recomeçar.
wizard() {
    local sel
    WIZ=() WIZ_ERR="" WIZ_PRINTED=0

    if [[ -n $PRESET_MODE ]]; then
        MODE=$PRESET_MODE
    else
        show_wizard
        choose sel "O que deseja fazer?" 0 \
            "Copiar|mantém os arquivos originais" \
            "Mover|apaga os originais só depois de verificar a cópia"
        if (( sel == 0 )); then MODE=copy; else MODE=move; fi
    fi
    if [[ $MODE == move ]]; then WIZ+=("Operação|Mover"); else WIZ+=("Operação|Copiar"); fi

    ask_sources
    sources_label 60
    WIZ+=("Origem|$REPLY")

    ask_dest
    home_path "$DEST"
    WIZ+=("Destino|$REPLY")

    detect_dest
    fs_profile
    show_wizard
    analyze
    collect_warnings

    if (( FAST_MOVE )); then
        VERIFY=none
    elif [[ -n $PRESET_VERIFY ]]; then
        VERIFY=$PRESET_VERIFY
    elif (( CLI_MODE )); then
        VERIFY=full
    else
        local -a vopts=(
            "Completa|compara o checksum relendo os dados do disco (recomendado)"
            "Rápida|compara tamanho e data de modificação"
        )
        [[ $MODE == copy ]] && vopts+=("Nenhuma|apenas copia e grava no dispositivo")
        choose sel "Como verificar a integridade?" 0 "${vopts[@]}"
        case $sel in 0) VERIFY=full ;; 1) VERIFY=quick ;; *) VERIFY=none ;; esac
    fi
    [[ $MODE == move && $VERIFY == none && $FAST_MOVE == 0 ]] && VERIFY=quick

    show_wizard
    plan_box
    if (( ASSUME_YES )); then
        return 0
    fi
    if [[ ! -t 0 ]]; then
        cli_fail "Entrada não interativa: use -y para confirmar automaticamente."
    fi
    local verb="a cópia"
    [[ $MODE == move ]] && verb="a movimentação"
    choose sel "Iniciar $verb?" 0 "Iniciar|" "Recomeçar|volta ao início" "Sair|"
    case $sel in
        0) return 0 ;;
        1) (( CLI_MODE )) && quit; return 1 ;;
        *) quit ;;
    esac
}

# ───────────────────────────── Etapas ─────────────────────────────

start_syncer() {
    (( DEST_REMOVABLE )) || return 0
    # Em dispositivos removíveis, grava o cache periodicamente durante a cópia:
    # o progresso passa a refletir a velocidade real do dispositivo e a etapa
    # final de gravação fica curta.
    (
        while sleep 2; do sync_path "$DEST"; done
    ) &
    SYNCER_PID=$!
}

stop_syncer() {
    if [[ -n $SYNCER_PID ]]; then
        kill "$SYNCER_PID" 2>/dev/null
        wait "$SYNCER_PID" 2>/dev/null
        SYNCER_PID=""
    fi
}

rsync_msg() {
    case $1 in
        0)  REPLY="sucesso" ;;
        1)  REPLY="erro de uso do rsync" ;;
        3)  REPLY="erro ao selecionar arquivos ou pastas" ;;
        11) REPLY="erro de leitura/escrita (disco cheio ou dispositivo removido?)" ;;
        12) REPLY="erro no fluxo de dados (disco cheio ou dispositivo removido?)" ;;
        20) REPLY="operação interrompida" ;;
        23) REPLY="alguns arquivos não puderam ser copiados" ;;
        24) REPLY="alguns arquivos sumiram da origem durante a cópia" ;;
        30) REPLY="tempo esgotado aguardando dados" ;;
        *)  REPLY="erro inesperado" ;;
    esac
}

phase_copy() {
    local title=$1 fd chunk piece pending="" code="" cur=""
    local s_pct s_done s_total s_speed s_avg s_time s_items extra fin
    local -i rc xfer=0 skipped=0 done_b=0 permil=0 items_done=0 items_total=0
    local -i t0 el last_ms last_b=0 ema=0 inst dt last_draw=0 eta pend dirty0 avg
    local re_prog='^[[:space:]]*([0-9][0-9.,]*)B?[[:space:]]+[0-9]+%'
    local re_chk='(to|ir)-chk=([0-9]+)/([0-9]+)'
    local re_item='^(.{11})\|([0-9]+)\|(.*)$'

    now_ms
    t0=$NOW_MS
    last_ms=$t0
    read_dirty
    dirty0=$DIRTY_KB
    : >"$TMP_DIR/rc"
    : >"$TMP_DIR/pid"
    start_syncer
    hide_cursor

    # name2 + out-format informam também os arquivos que já existem no destino
    # (".f"), cujos bytes o progress2 do rsync não contabiliza.
    exec {fd}< <(
        rsync "${COPY_ARGS[@]}" --info=progress2,name2 --out-format='%i|%l|%n' \
            "${SOURCES[@]}" "$DEST/" 2>>"$ERR_LOG" &
        echo "$!" >"$TMP_DIR/pid"
        wait "$!"
        echo "$?" >"$TMP_DIR/rc"
    )

    while :; do
        IFS= read -r -t 0.2 -d $'\r' -u "$fd" chunk
        rc=$?
        [[ -z $JOB_PID ]] && read -r JOB_PID 2>/dev/null <"$TMP_DIR/pid"
        if (( INTERRUPTED )) && [[ -n $JOB_PID ]]; then kill "$JOB_PID" 2>/dev/null; fi

        if (( rc > 128 )); then
            pending+=$chunk
        else
            chunk=$pending$chunk
            pending=""
            while IFS= read -r piece; do
                if [[ $piece =~ $re_item ]]; then
                    case ${BASH_REMATCH[1]} in
                        .f*)   skipped+=${BASH_REMATCH[2]} ;;
                        '>f'*) cur=${BASH_REMATCH[3]} ;;
                    esac
                elif [[ $piece =~ $re_prog ]]; then
                    inst=$(( 10#${BASH_REMATCH[1]//[!0-9]/} ))
                    (( inst > xfer )) && xfer=$inst
                    if [[ $piece =~ $re_chk ]]; then
                        items_total=${BASH_REMATCH[3]}
                        items_done=$(( items_total - BASH_REMATCH[2] ))
                    fi
                fi
            done <<<"$chunk"
        fi
        if [[ -n $JOB_PID ]]; then
            proc_leaf_wchar "$JOB_PID"
            (( REPLY > xfer )) && xfer=$REPLY
        fi

        now_ms
        el=$(( NOW_MS - t0 ))
        dt=$(( NOW_MS - last_ms ))
        if (( dt >= 500 )); then
            inst=$(( (xfer - last_b) * 1000 / dt ))
            (( inst < 0 )) && inst=0
            if (( ema == 0 )); then ema=$inst; else ema=$(( (ema * 7 + inst * 3) / 10 )); fi
            last_b=$xfer
            last_ms=$NOW_MS
        fi
        done_b=$(( xfer + skipped ))

        (( rc > 0 && rc <= 128 )) && break
        (( NOW_MS - last_draw < 150 )) && continue
        last_draw=$NOW_MS

        if (( TOTAL_BYTES > 0 )); then
            permil=$(( done_b * 1000 / TOTAL_BYTES ))
        elif (( items_total > 0 )); then
            permil=$(( items_done * 1000 / items_total ))
        fi
        (( permil > 999 )) && permil=999
        render_bar "$permil"
        fmt_permil "$permil"; s_pct=$REPLY
        fmt_size "$done_b"; s_done=$REPLY
        fmt_size "$TOTAL_BYTES"; s_total=$REPLY
        extra=""
        if (( skipped > 0 )); then fmt_size "$skipped"; extra="  ${CGRY}($REPLY já existiam)${C0}"; fi

        avg=0
        (( el > 0 )) && avg=$(( xfer * 1000 / el ))
        if (( el >= 1000 )); then
            fmt_size "$ema"; s_speed="$REPLY/s"
            fmt_size "$avg"; s_avg="$REPLY/s"
        else
            s_speed="—" s_avg="—"
        fi

        fmt_dur $(( el / 1000 )); s_time="$REPLY decorrido"
        if (( el >= 1500 && ema > 0 )); then
            eta=$(( (TOTAL_BYTES - done_b) / ema ))
            (( eta < 0 )) && eta=0
            fmt_dur "$eta"
            printf -v fin '%(%H:%M)T' $(( NOW_MS / 1000 + eta ))
            s_time+="${SEP}~$REPLY restante ${CGRY}· termina às $fin${C0}"
        else
            s_time+=" ${CGRY}· calculando o tempo restante…${C0}"
        fi

        if (( items_total > 0 )); then
            fmt_int "$items_done"; s_items=$REPLY
            fmt_int "$items_total"; s_items+=" ${CGRY}de${C0} $REPLY"
        else
            s_items="${CGRY}preparando a lista…${C0}"
        fi

        DASH=("  ${CCYN}●${C0} ${CB}${title}${C0}" "")
        DASH+=("    ${BAR} ${CB}${s_pct}${C0}" "")
        lbl "Transferido"; DASH+=("$LBL$s_done ${CGRY}de${C0} $s_total$extra")
        lbl "Velocidade";  DASH+=("$LBL$s_speed ${CGRY}· média $s_avg${C0}")
        lbl "Tempo";       DASH+=("$LBL$s_time")
        lbl "Itens";       DASH+=("$LBL$s_items")
        if (( DEST_REMOVABLE )); then
            read_dirty
            pend=$(( (DIRTY_KB - dirty0) * 1024 ))
            (( pend < 0 )) && pend=0
            fmt_size "$pend"
            lbl "Em cache"; DASH+=("$LBL$REPLY ${CGRY}aguardando gravação no dispositivo${C0}")
        fi
        trunc_mid "${cur:-…}" $(( UI_W - 17 ))
        lbl "Arquivo"; DASH+=("$LBL${CGRY}$REPLY${C0}")
        dash_draw
    done

    exec {fd}<&-
    stop_syncer
    read -r code 2>/dev/null <"$TMP_DIR/rc"
    [[ $code =~ ^[0-9]+$ ]] || code=20
    (( INTERRUPTED )) && code=20
    RSYNC_RC=$code
    JOB_PID=""
    now_ms
    COPY_MS=$(( NOW_MS - t0 ))
    COPY_BYTES=$xfer
    SKIPPED_BYTES=$skipped
    dash_clear

    fmt_size "$(( xfer + skipped ))"; local size=$REPLY
    if (( RSYNC_RC == 0 )); then
        local detail=$size
        (( COPY_MS > 0 )) && { fmt_size $(( xfer * 1000 / COPY_MS )); detail+="${SEP}$REPLY/s"; }
        (( skipped > 0 )) && { fmt_size "$skipped"; detail+=" ${CGRY}· $REPLY já existiam${C0}"; }
        phase_line ok "Cópia" "$detail" "$COPY_MS"
    elif (( RSYNC_RC == 20 )); then
        phase_line warn "Cópia" "interrompida após $size" "$COPY_MS"
    else
        rsync_msg "$RSYNC_RC"
        phase_line fail "Cópia" "${CRED}$REPLY${C0} ${CGRY}(código $RSYNC_RC)${C0}" "$COPY_MS"
    fi
}

# Força a gravação do cache no dispositivo e mostra o progresso. Nunca é
# interrompida: abortar aqui deixaria o dispositivo inconsistente.
phase_flush() {
    local label=${1:-Gravação} pid
    local -i t0 start best=0 permil el
    now_ms
    t0=$NOW_MS
    read_dirty
    start=$DIRTY_KB
    sync_path "$DEST" &
    pid=$!
    hide_cursor
    while kill -0 "$pid" 2>/dev/null; do
        sleep 0.2
        kill -0 "$pid" 2>/dev/null || break
        read_dirty
        (( start - DIRTY_KB > best )) && best=$(( start - DIRTY_KB ))
        permil=0
        (( start > 0 )) && permil=$(( best * 1000 / start ))
        (( permil > 999 )) && permil=999
        now_ms
        el=$(( NOW_MS - t0 ))
        render_bar "$permil"
        fmt_permil "$permil"; local s_pct=$REPLY
        fmt_size $(( best * 1024 )); local s_done=$REPLY
        fmt_size $(( start * 1024 ))
        DASH=("  ${CCYN}●${C0} ${CB}Gravando no dispositivo${C0}  ${CGRY}não remova o dispositivo${C0}" "")
        DASH+=("    ${BAR} ${CB}${s_pct}${C0}" "")
        lbl "Gravado"; DASH+=("$LBL$s_done ${CGRY}de${C0} $REPLY ${CGRY}que estavam em cache${C0}")
        fmt_dur $(( el / 1000 ))
        lbl "Tempo"; DASH+=("$LBL$REPLY decorrido")
        (( INTERRUPTED )) && DASH+=("" "    ${CYLW}Interrompido: finalizando a gravação para não corromper os dados…${C0}")
        dash_draw
    done
    wait "$pid" 2>/dev/null
    now_ms
    FLUSH_MS=$(( FLUSH_MS + NOW_MS - t0 ))
    FLUSHED=1
    dash_clear
    if (( start > 0 )); then
        fmt_size $(( start * 1024 ))
        phase_line ok "$label" "cache gravado no dispositivo  ${CGRY}($REPLY)${C0}" $(( NOW_MS - t0 ))
    else
        phase_line ok "$label" "todos os dados já estão no dispositivo" $(( NOW_MS - t0 ))
    fi
}

# Descarta do cache as páginas dos arquivos de destino para que a verificação
# leia os dados do próprio dispositivo, e não da memória.
evict_cache() {
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$@" <<'PY' 2>/dev/null
import os, sys

def drop(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        return
    try:
        os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)
    except OSError:
        pass
    finally:
        os.close(fd)

for root in sys.argv[1:]:
    if os.path.isfile(root) and not os.path.islink(root):
        drop(root)
        continue
    for d, _, files in os.walk(root):
        for f in files:
            drop(os.path.join(d, f))
PY
    else
        find "$@" -type f -exec sh -c \
            'for f do dd if="$f" iflag=nocache count=0 status=none 2>/dev/null; done' sh {} +
    fi
}

phase_verify() {
    local mode=$1 pid s_pct fin
    local -i t0 el rc readb=0 permil target ema=0 last_b=0 last_ms dt inst eta frame=0
    local -a args
    now_ms
    t0=$NOW_MS
    last_ms=$t0
    hide_cursor
    if [[ $mode == full ]]; then
        DASH=("  ${CCYN}●${C0} ${CB}Verificando a integridade${C0}" ""
              "    ${CGRY}Liberando o cache para reler os dados direto do dispositivo…${C0}")
        dash_draw
        evict_cache "${DEST_ITEMS[@]}"
        args=(-r -c -n -i --no-inc-recursive)
        (( FS_NO_LINKS )) || args+=(-l)
    else
        args=("${COPY_ARGS[@]}" -n -i)
    fi

    rsync "${args[@]}" "${SOURCES[@]}" "$DEST/" >"$TMP_DIR/verify.out" 2>>"$ERR_LOG" &
    pid=$!
    JOB_PID=$pid
    target=$(( TOTAL_BYTES * 2 ))
    while kill -0 "$pid" 2>/dev/null; do
        now_ms
        el=$(( NOW_MS - t0 ))
        DASH=("  ${CCYN}●${C0} ${CB}Verificando a integridade${C0}" "")
        if [[ $mode == full ]]; then
            proc_tree_rchar "$pid"
            (( REPLY > readb )) && readb=$REPLY
            dt=$(( NOW_MS - last_ms ))
            if (( dt >= 1000 )); then
                inst=$(( (readb - last_b) * 1000 / dt ))
                if (( ema == 0 )); then ema=$inst; else ema=$(( (ema * 6 + inst * 4) / 10 )); fi
                last_b=$readb
                last_ms=$NOW_MS
            fi
            permil=0
            (( target > 0 )) && permil=$(( readb * 1000 / target ))
            (( permil > 999 )) && permil=999
            render_bar "$permil"
            fmt_permil "$permil"; s_pct=$REPLY
            DASH+=("    ${BAR} ${CB}${s_pct}${C0}" "")
            fmt_size "$readb"; local s_read=$REPLY
            fmt_size "$target"
            lbl "Lido"; DASH+=("$LBL$s_read ${CGRY}de${C0} $REPLY ${CGRY}(origem + destino)${C0}")
            if (( ema > 0 )); then fmt_size "$ema"; lbl "Velocidade"; DASH+=("$LBL$REPLY/s"); fi
            fmt_dur $(( el / 1000 )); local s_time="$REPLY decorrido"
            if (( el >= 2000 && ema > 0 )); then
                eta=$(( (target - readb) / ema ))
                (( eta < 0 )) && eta=0
                fmt_dur "$eta"
                printf -v fin '%(%H:%M)T' $(( NOW_MS / 1000 + eta ))
                s_time+="${SEP}~$REPLY restante ${CGRY}· termina às $fin${C0}"
            fi
            lbl "Tempo"; DASH+=("$LBL$s_time")
        else
            render_pulse "$frame"
            frame+=1
            DASH+=("    ${BAR}" "")
            plural "$TOTAL_FILES" "arquivo" "arquivos"
            lbl "Comparando"; DASH+=("$LBL$REPLY ${CGRY}(tamanho e data)${C0}")
            fmt_dur $(( el / 1000 ))
            lbl "Tempo"; DASH+=("$LBL$REPLY decorrido")
        fi
        dash_draw
        sleep 0.2
    done
    wait "$pid"
    rc=$?
    JOB_PID=""
    (( INTERRUPTED )) && rc=20
    now_ms
    VERIFY_MS=$(( NOW_MS - t0 ))
    dash_clear

    MISMATCH=$(grep -cE '^[<>ch]' "$TMP_DIR/verify.out")
    VERIFY_RC=$rc
    if (( rc == 0 && MISMATCH == 0 )); then
        VERIFY_OK=1
        plural "$TOTAL_FILES" "arquivo idêntico" "arquivos idênticos"
        local how="checksum relido do disco"
        [[ $mode == quick ]] && how="tamanho e data"
        phase_line ok "Verificação" "$REPLY ${CGRY}· $how${C0}" "$VERIFY_MS"
    elif (( rc == 20 )); then
        phase_line warn "Verificação" "interrompida" "$VERIFY_MS"
    elif (( MISMATCH > 0 )); then
        plural "$MISMATCH" "item diverge ou falta" "itens divergem ou faltam"
        phase_line fail "Verificação" "${CRED}$REPLY no destino${C0}" "$VERIFY_MS"
    else
        rsync_msg "$rc"
        phase_line fail "Verificação" "${CRED}$REPLY${C0} ${CGRY}(código $rc)${C0}" "$VERIFY_MS"
    fi
}

phase_remove() {
    local src
    local -i t0 rc
    now_ms
    t0=$NOW_MS
    spinner_start "Removendo os originais…"
    # Com --remove-source-files o rsync só apaga da origem o que confirmou estar
    # idêntico no destino; o que não pôde ser copiado permanece.
    rsync "${COPY_ARGS[@]}" --remove-source-files "${SOURCES[@]}" "$DEST/" >/dev/null 2>>"$ERR_LOG" &
    JOB_PID=$!
    wait "$JOB_PID"
    rc=$?
    JOB_PID=""
    LEFTOVER=0
    for src in "${SOURCES[@]}"; do
        if [[ -d $src && ! -L $src ]]; then
            find "$src" -depth -type d -empty -delete 2>/dev/null
        fi
        if [[ -e $src || -L $src ]]; then
            LEFTOVER+=$(find "$src" ! -type d 2>/dev/null | wc -l)
        fi
    done
    sync
    spinner_stop
    now_ms
    REMOVE_MS=$(( NOW_MS - t0 ))
    (( INTERRUPTED )) && rc=20
    REMOVE_RC=$rc
    if (( rc == 0 && LEFTOVER == 0 )); then
        phase_line ok "Remoção" "originais apagados" "$REMOVE_MS"
    elif (( rc == 20 )); then
        phase_line warn "Remoção" "interrompida — o que restou na origem continua intacto" "$REMOVE_MS"
    else
        plural "$LEFTOVER" "arquivo permaneceu" "arquivos permaneceram"
        phase_line warn "Remoção" "$REPLY na origem" "$REMOVE_MS"
    fi
}

# Mover dentro do mesmo sistema de arquivos é só renomear: instantâneo e sem
# reescrever dados.
phase_rename() {
    local src
    local -i t0
    RENAME_FAILED=0
    now_ms
    t0=$NOW_MS
    for src in "${SOURCES[@]}"; do
        mv -n -- "$src" "$DEST/" 2>>"$ERR_LOG" || RENAME_FAILED=1
        [[ -e $src || -L $src ]] && RENAME_FAILED=1
    done
    sync_path "$DEST"
    now_ms
    COPY_MS=$(( NOW_MS - t0 ))
    FLUSHED=1
    if (( RENAME_FAILED )); then
        phase_line fail "Movimentação" "${CRED}nem todos os itens puderam ser movidos${C0}" "$COPY_MS"
    else
        plural "${#SOURCES[@]}" "item movido" "itens movidos"
        phase_line ok "Movimentação" "$REPLY ${CGRY}· mesmo disco, sem reescrever dados${C0}" "$COPY_MS"
    fi
}

# ───────────────────────────── Execução ─────────────────────────────

exec_header() {
    local verb="Copiando"
    [[ $MODE == move ]] && verb="Movendo"
    banner
    sources_label $(( UI_W / 2 - 6 ))
    local src=$REPLY
    home_path "$DEST"
    trunc_mid "$REPLY" $(( UI_W / 2 - 6 ))
    printf '  %s%s%s  %s  %s→%s  %s\n' "$CB" "$verb" "$C0" "$src" "$CCYN" "$C0" "$REPLY"
    fmt_size "$TOTAL_BYTES"; local size=$REPLY
    plural "$TOTAL_FILES" "arquivo" "arquivos"
    printf '  %s%s · %s%s%s\n\n' "$CGRY" "$size" "$REPLY" "${DEST_DESC:+ · $DEST_DESC}" "$C0"
}

execute() {
    : >"$ERR_LOG"
    : >"$TMP_DIR/verify.out"
    INTERRUPTED=0 OP_RUNNING=1 RSYNC_RC=0 VERIFY_OK=0 VERIFY_RC=0 MISMATCH=0
    REMOVE_RC=-1 LEFTOVER=0 RENAME_FAILED=0 FLUSHED=0
    COPY_MS=0 FLUSH_MS=0 VERIFY_MS=0 REMOVE_MS=0 COPY_BYTES=0 SKIPPED_BYTES=0
    local -i t0
    exec_header
    now_ms
    t0=$NOW_MS

    if (( FAST_MOVE )); then
        phase_rename
    else
        if [[ $MODE == move ]]; then phase_copy "Copiando para o destino"; else phase_copy "Copiando"; fi
        # A gravação acontece sempre, inclusive após erro ou interrupção, para
        # que o dispositivo possa ser removido com segurança.
        phase_flush
        # Em falhas parciais a verificação mostra exatamente o que ficou faltando.
        if (( ! INTERRUPTED )) && [[ $VERIFY != none && $RSYNC_RC == @(0|23|24) ]]; then
            phase_verify "$VERIFY"
        fi
        if [[ $MODE == move ]] && (( ! INTERRUPTED && RSYNC_RC == 0 && VERIFY_OK )); then
            phase_remove
        fi
    fi

    now_ms
    TOTAL_MS=$(( NOW_MS - t0 ))
    OP_RUNNING=0
    show_cursor
    summary
}

summary() {
    local status headline color title
    local -a L=()
    local w=$(( UI_W - 4 - 13 ))

    if (( INTERRUPTED )); then
        status=warn headline="Operação interrompida"
    elif (( FAST_MOVE )); then
        if (( RENAME_FAILED )); then status=fail headline="Nem todos os itens foram movidos"
        else status=ok headline="Itens movidos com sucesso"; fi
    elif (( RSYNC_RC != 0 )); then
        rsync_msg "$RSYNC_RC"
        status=fail headline="Falha na cópia: $REPLY"
    elif [[ $VERIFY != none ]] && (( ! VERIFY_OK )); then
        status=fail headline="A verificação encontrou diferenças"
    elif [[ $MODE == move ]] && (( REMOVE_RC != 0 || LEFTOVER > 0 )); then
        status=warn headline="Cópia verificada, mas parte da origem não foi removida"
    elif [[ $MODE == move ]]; then
        status=ok headline="Arquivos movidos e verificados"
    elif [[ $VERIFY == none ]]; then
        status=ok headline="Cópia concluída (sem verificação)"
    else
        status=ok headline="Cópia concluída e verificada"
    fi

    case $status in
        ok)   color=$CGRN title="Concluído"; headline="${CGRN}✓ ${CB}$headline${C0}" ;;
        warn) color=$CYLW title="Atenção";   headline="${CYLW}! ${CB}$headline${C0}" ;;
        *)    color=$CRED title="Falhou";    headline="${CRED}✗ ${CB}$headline${C0}" ;;
    esac
    L+=("$headline" "")

    sources_label "$w"; kv "Origem" "$REPLY"; L+=("$REPLY")
    home_path "$DEST"; trunc_mid "$REPLY" "$w"; kv "Destino" "$REPLY"; L+=("$REPLY")
    fmt_size "$TOTAL_BYTES"; local size=$REPLY
    plural "$TOTAL_FILES" "arquivo" "arquivos"
    kv "Volume" "$size${SEP}$REPLY"; L+=("$REPLY")

    fmt_ms "$TOTAL_MS"; kv "Tempo total" "$REPLY"; L+=("$REPLY")
    if (( ! FAST_MOVE )); then
        local parts=""
        fmt_ms "$COPY_MS"; parts="cópia $REPLY"
        fmt_ms "$FLUSH_MS"; parts+="${SEP}gravação $REPLY"
        (( VERIFY_MS > 0 )) && { fmt_ms "$VERIFY_MS"; parts+="${SEP}verificação $REPLY"; }
        (( REMOVE_MS > 0 )) && { fmt_ms "$REMOVE_MS"; parts+="${SEP}remoção $REPLY"; }
        kv "Etapas" "$parts"; L+=("$REPLY")
    fi

    if (( ! FAST_MOVE && COPY_BYTES > 0 && COPY_MS + FLUSH_MS > 0 )); then
        fmt_size $(( COPY_BYTES * 1000 / (COPY_MS + FLUSH_MS) ))
        kv "Velocidade" "$REPLY/s  ${CGRY}(média real, incluindo a gravação)${C0}"; L+=("$REPLY")
    fi

    local integ
    if (( FAST_MOVE )); then
        integ="dados intactos (renomeados no mesmo disco)"
    elif [[ $VERIFY == none ]]; then
        integ="${CYLW}não verificada${C0}"
    elif (( VERIFY_OK )); then
        if [[ $VERIFY == full ]]; then integ="${CGRN}checksum idêntico${C0} relendo o disco"
        else integ="${CGRN}tamanho e data conferem${C0}"; fi
    elif (( MISMATCH > 0 )); then
        plural "$MISMATCH" "divergência" "divergências"
        integ="${CRED}$REPLY${C0}"
    else
        integ="${CGRY}não concluída${C0}"
    fi
    kv "Integridade" "$integ"; L+=("$REPLY")

    echo
    box "$color" "$title" "${L[@]}"

    if (( MISMATCH > 0 )); then
        printf '\n  %sItens com diferença no destino:%s\n' "$CB" "$C0"
        grep -E '^[<>ch]' "$TMP_DIR/verify.out" | head -n 5 | while IFS= read -r line; do
            trunc_mid "${line:12}" $(( UI_W - 6 ))
            printf '    %s•%s %s\n' "$CRED" "$C0" "$REPLY"
        done
        (( MISMATCH > 5 )) && printf '    %s… e mais %d%s\n' "$CGRY" $(( MISMATCH - 5 )) "$C0"
    fi

    if (( INTERRUPTED && ! FAST_MOVE )); then
        printf '\n  %sExecute a mesma operação de novo para continuar: o que já foi copiado será pulado.%s\n' "$CGRY" "$C0"
    elif [[ -s $ERR_LOG ]]; then
        mkdir -p "$STATE_DIR" 2>/dev/null
        local saved=$STATE_DIR/ultimo-erro.log
        cp -- "$ERR_LOG" "$saved" 2>/dev/null || saved=$ERR_LOG
        printf '\n  %sProblemas encontrados:%s\n' "$CB" "$C0"
        local -i shown=0 total=0
        local re_fail='"([^"]+)".* failed: (.+)$'
        while IFS= read -r line; do
            [[ $line == "rsync error:"* ]] && continue
            total+=1
            (( shown >= 5 )) && continue
            shown+=1
            if [[ $line =~ $re_fail ]]; then
                local reason=${BASH_REMATCH[2]} path=${BASH_REMATCH[1]} base
                # O rsync escapa bytes não ASCII como \#ooo (octal).
                path=${path//\\#/\\0}
                printf -v path '%b' "$path"
                path=${path#"$DEST"/}
                base=${path##*/}
                if [[ $base =~ ^\.(.+)\.[A-Za-z0-9]{6}$ ]]; then
                    path=${path%/*}
                    [[ $path == "$base" ]] && path="" || path+=/
                    path+=${BASH_REMATCH[1]}
                fi
                home_path "$path"
                trunc_mid "$REPLY" $(( UI_W - 10 - ${#reason} ))
                printf '    %s•%s %s %s→ %s%s\n' "$CRED" "$C0" "$REPLY" "$CGRY" "$reason" "$C0"
            else
                trunc_mid "${line#rsync: }" $(( UI_W - 6 ))
                printf '    %s•%s %s%s%s\n' "$CRED" "$C0" "$CGRY" "$REPLY" "$C0"
            fi
        done <"$ERR_LOG"
        (( total > shown )) && printf '    %s… e mais %d%s\n' "$CGRY" $(( total - shown )) "$C0"
        home_path "$saved"
        printf '    %sLog completo: %s%s\n' "$CGRY" "$REPLY" "$C0"
    fi

    if [[ $MODE == move && $status != ok ]] && (( ! FAST_MOVE )); then
        printf '\n  %s!%s Nada foi apagado da origem sem antes ter sido verificado no destino.\n' "$CYLW" "$C0"
    fi
    if (( FLUSHED && DEST_REMOVABLE )); then
        printf '\n  %s✓%s Todos os dados foram gravados em %s%s%s. Já é seguro ejetar.\n' \
            "$CGRN" "$C0" "$CB" "$DEST_NAME" "$C0"
    fi
}

eject_dest() {
    local out rc
    echo
    spinner_start "Ejetando $DEST_NAME…"
    sync
    if command -v udisksctl >/dev/null 2>&1; then
        out=$(udisksctl unmount -b "$DEST_DEV" 2>&1)
        rc=$?
    else
        out=$(umount -- "$DEST_MNT" 2>&1)
        rc=$?
    fi
    spinner_stop
    if (( rc != 0 )); then
        printf '  %s✗ Não foi possível desmontar:%s %s\n' "$CRED" "$C0" "${out//$'\n'/ }"
        if command -v fuser >/dev/null 2>&1; then
            local users
            users=$(fuser -vm -- "$DEST_MNT" 2>&1 | awk 'NF >= 4 && $(NF-2) ~ /^[0-9]+$/ { print "    • " $(NF) " (PID " $(NF-2) ")" }' | sort -u)
            if [[ -n $users ]]; then
                printf '  %sProgramas usando o dispositivo:%s\n%s\n' "$CB" "$C0" "$users"
            fi
        fi
        printf '  %sFeche janelas e terminais abertos dentro do dispositivo e tente de novo.%s\n' "$CGRY" "$C0"
        return 1
    fi
    if command -v udisksctl >/dev/null 2>&1 && [[ -n $DEST_DISK ]]; then
        udisksctl power-off -b "$DEST_DISK" >/dev/null 2>&1
    fi
    printf '  %s✓%s %s%s%s foi ejetado. Pode remover com segurança.\n' "$CGRN" "$C0" "$CB" "$DEST_NAME" "$C0"
    DEST_REMOVABLE=0
}

# Devolve 0 para uma nova operação, 1 para sair.
after_menu() {
    local sel label
    local -a opts
    (( CLI_MODE )) && return 1
    while :; do
        opts=("Nova operação|")
        (( DEST_REMOVABLE )) && opts+=("Ejetar $DEST_NAME com segurança|desmonta e desliga o dispositivo")
        opts+=("Sair|")
        echo
        choose sel "E agora?" 0 "${opts[@]}"
        label=${opts[sel]%%|*}
        case $label in
            "Nova operação") return 0 ;;
            Ejetar*) eject_dest ;;
            *) return 1 ;;
        esac
    done
}

# ───────────────────────────── Ciclo de vida ─────────────────────────────

cleanup() {
    [[ -n $SPIN_PID ]] && kill "$SPIN_PID" 2>/dev/null
    [[ -n $SYNCER_PID ]] && kill "$SYNCER_PID" 2>/dev/null
    show_cursor
    [[ -t 0 ]] && stty echo icanon 2>/dev/null
    rm -rf -- "$TMP_DIR"
}

quit() {
    spinner_stop
    printf '\n  %sAté logo!%s\n\n' "$CGRY" "$C0"
    exit 0
}

on_int() {
    if (( OP_RUNNING )); then
        INTERRUPTED=1
        [[ -n $JOB_PID ]] && kill "$JOB_PID" 2>/dev/null
        return
    fi
    spinner_stop
    printf '\n\n  %sAté logo!%s\n\n' "$CGRY" "$C0"
    exit 130
}

usage() {
    cat <<EOF
THANDER COPY $VERSION — copia e move arquivos com integridade verificada.

Uso:
  thander-copy                       modo interativo
  thander-copy [opções] ORIGEM... DESTINO

Opções:
  -c, --copiar             copia (padrão)
  -m, --mover              move: apaga a origem só depois de verificar a cópia
  -v, --verificacao MODO   completa (padrão), rapida ou nenhuma
  -y, --sim                não pede confirmação (cria o destino se necessário)
  -h, --ajuda              mostra esta ajuda
  -V, --versao             mostra a versão
EOF
}

parse_args() {
    local -a pos=()
    CLI_MODE=0 PRESET_MODE="" PRESET_VERIFY="" ASSUME_YES=0 PRESET_DEST=""
    PRESET_SOURCES=()
    while (( $# )); do
        case $1 in
            -c|--copiar|--copy) PRESET_MODE=copy ;;
            -m|--mover|--move)  PRESET_MODE=move ;;
            -v|--verificacao|--verify) shift; PRESET_VERIFY=${1:-} ;;
            --verificacao=*|--verify=*) PRESET_VERIFY=${1#*=} ;;
            -y|--sim|--yes) ASSUME_YES=1 ;;
            -h|--ajuda|--help) usage; exit 0 ;;
            -V|--versao|--version) echo "thander-copy $VERSION"; exit 0 ;;
            --) shift; pos+=("$@"); break ;;
            -*) echo "Opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
            *) pos+=("$1") ;;
        esac
        shift
    done
    case ${PRESET_VERIFY,,} in
        "") ;;
        completa|full) PRESET_VERIFY=full ;;
        rapida|rápida|quick) PRESET_VERIFY=quick ;;
        nenhuma|none) PRESET_VERIFY=none ;;
        *) echo "Modo de verificação inválido: $PRESET_VERIFY" >&2; exit 2 ;;
    esac
    if (( ${#pos[@]} == 1 )); then
        echo "Informe a origem e o destino." >&2
        usage >&2
        exit 2
    fi
    if (( ${#pos[@]} >= 2 )); then
        CLI_MODE=1
        PRESET_DEST=${pos[-1]}
        PRESET_SOURCES=("${pos[@]:0:${#pos[@]}-1}")
        [[ -z $PRESET_MODE ]] && PRESET_MODE=copy
    fi
}

main() {
    parse_args "$@"
    if ! command -v rsync >/dev/null 2>&1; then
        echo "O rsync não está instalado. Instale-o com o gerenciador de pacotes da sua distribuição." >&2
        exit 1
    fi
    setup_colors
    update_layout
    setup_history
    trap cleanup EXIT
    trap on_int INT
    trap 'on_int; exit 143' TERM
    trap update_layout WINCH

    while :; do
        cd -- "$ORIG_PWD" 2>/dev/null || cd -- "$HOME" 2>/dev/null || cd /
        wizard || continue
        # Durante a operação o processo não deve manter nenhuma montagem ocupada.
        cd /
        execute
        after_menu || break
    done
    if (( CLI_MODE )); then
        local ok=0
        if (( INTERRUPTED || RSYNC_RC != 0 || RENAME_FAILED )); then ok=1
        elif [[ $VERIFY != none ]] && (( ! FAST_MOVE && ! VERIFY_OK )); then ok=1; fi
        exit "$ok"
    fi
    quit
}

main "$@"
