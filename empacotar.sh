#!/usr/bin/env bash
#
# Pergunta qual pacote do thander-copy criar e gera o arquivo em dist/.
#
#   ./empacotar.sh            pergunta: Debian, RPM ou Pacman
#   ./empacotar.sh debian     .deb
#   ./empacotar.sh rpm        .rpm  (precisa do rpmbuild)
#   ./empacotar.sh pacman     .pkg.tar.zst (precisa do makepkg)
#   ./empacotar.sh todos

if [ -z "${BASH_VERSION:-}" ]; then
    echo "Este script precisa do bash." >&2
    exit 1
fi

set -euo pipefail

RAIZ=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$RAIZ"
DIST=$RAIZ/dist

NOME="thander-copy"
RELEASE="1"
MANUTENCAO="Simei Thander <simeithander@gmail.com>"
URL="https://github.com/simeithander/thander-copy"
RESUMO="Copia e move arquivos com integridade verificada"
DESCRICAO="Ferramenta de terminal para copiar e mover arquivos e pastas, com verificação de checksum, gravação garantida no dispositivo e progresso em tempo real."

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
    C0=$'\e[0m' CB=$'\e[1m' CVER=$'\e[1;32m' CAM=$'\e[1;33m' CER=$'\e[1;31m' CC=$'\e[1;36m'
else
    C0="" CB="" CVER="" CAM="" CER="" CC=""
fi

if [[ ! -f thander-copy.sh || ! -f LICENSE || ! -f README.md ]]; then
    echo "Execute este script dentro do repositório do thander-copy." >&2
    exit 1
fi

VERSAO=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' thander-copy.sh)
if [[ -z $VERSAO ]]; then
    echo "Não foi possível ler a versão em thander-copy.sh." >&2
    exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/thander-copy-pkg.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT

# Monta a árvore que vai dentro do pacote.
preparar_raiz() {
    local destino=$1
    install -Dm755 thander-copy.sh "$destino/usr/bin/$NOME"
    install -Dm644 LICENSE "$destino/usr/share/licenses/$NOME/LICENSE"
    install -Dm644 README.md "$destino/usr/share/doc/$NOME/README.md"
}

aviso_instalacao() {
    local ferramenta=$1
    echo "${CER}Falta o comando '$ferramenta' para gerar este pacote.${C0}" >&2
    if command -v pacman >/dev/null 2>&1; then
        echo "Instale com: sudo pacman -S $2" >&2
    elif command -v apt-get >/dev/null 2>&1; then
        echo "Instale com: sudo apt install $3" >&2
    elif command -v dnf >/dev/null 2>&1; then
        echo "Instale com: sudo dnf install $4" >&2
    elif command -v zypper >/dev/null 2>&1; then
        echo "Instale com: sudo zypper install $4" >&2
    fi
}

# ───────────────────────────── Debian ─────────────────────────────

montar_deb() {
    local raiz=$1 controle=$2
    mkdir -p "$controle"

    cat >"$controle/control" <<EOF
Package: $NOME
Version: $VERSAO
Section: utils
Priority: optional
Architecture: all
Maintainer: $MANUTENCAO
Depends: bash (>= 4.4), rsync, gawk, findutils, coreutils
Recommends: util-linux, python3, udisks2, psmisc
Homepage: $URL
Installed-Size: $(du -sk "$raiz" | cut -f1)
Description: $RESUMO
 ${DESCRICAO}
EOF

    (
        cd -- "$raiz"
        find . -type f -printf '%P\0' | sort -z | while IFS= read -r -d '' arquivo; do
            md5sum -- "$arquivo"
        done >"$controle/md5sums"
    )
}

empacotar_deb_com_ar() {
    local raiz=$1 controle=$2 saida=$3
    echo "2.0" >"$TMP/debian-binary"
    tar --owner=0 --group=0 --numeric-owner -czf "$TMP/control.tar.gz" -C "$controle" .
    tar --owner=0 --group=0 --numeric-owner -czf "$TMP/data.tar.gz" -C "$raiz" .
    rm -f -- "$saida"
    ar r "$saida" "$TMP/debian-binary" "$TMP/control.tar.gz" "$TMP/data.tar.gz" >/dev/null 2>&1
}

criar_deb() {
    local raiz=$TMP/deb-raiz controle=$TMP/DEBIAN
    local saida=$DIST/${NOME}_${VERSAO}_all.deb
    echo "${CC}▸${C0} Gerando pacote Debian ${CB}$VERSAO${C0}"
    rm -rf -- "$raiz" "$controle"
    preparar_raiz "$raiz"
    montar_deb "$raiz" "$controle"
    mkdir -p -- "$DIST"

    if command -v dpkg-deb >/dev/null 2>&1; then
        rm -rf -- "$TMP/deb-dpkg"
        mkdir -p -- "$TMP/deb-dpkg"
        cp -a -- "$raiz/." "$TMP/deb-dpkg/"
        cp -a -- "$controle" "$TMP/deb-dpkg/DEBIAN"
        dpkg-deb --root-owner-group --build "$TMP/deb-dpkg" "$saida" >/dev/null
    else
        empacotar_deb_com_ar "$raiz" "$controle" "$saida"
    fi
    echo "${CVER}✓${C0} $saida"
}

# ───────────────────────────── RPM ─────────────────────────────

criar_rpm() {
    if ! command -v rpmbuild >/dev/null 2>&1; then
        aviso_instalacao rpmbuild rpm-tools rpm rpm-build
        return 1
    fi

    local topo=$TMP/rpmbuild
    local saida
    echo "${CC}▸${C0} Gerando pacote RPM ${CB}$VERSAO${C0}"
    mkdir -p "$topo"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    cp -- thander-copy.sh LICENSE README.md "$topo/SOURCES/"

    cat >"$topo/SPECS/$NOME.spec" <<EOF
Name:           $NOME
Version:        $VERSAO
Release:        $RELEASE%{?dist}
Summary:        $RESUMO
License:        MIT
URL:            $URL
BuildArch:      noarch
Requires:       bash >= 4.4
Requires:       rsync
Requires:       gawk
Requires:       findutils
Requires:       coreutils
Recommends:     util-linux
Recommends:     python3
Recommends:     udisks2
Recommends:     psmisc

Source0:        thander-copy.sh
Source1:        LICENSE
Source2:        README.md

%description
$DESCRICAO

%prep

%build

%install
install -Dm755 %{SOURCE0} %{buildroot}/usr/bin/$NOME
install -Dm644 %{SOURCE1} %{buildroot}/usr/share/licenses/$NOME/LICENSE
install -Dm644 %{SOURCE2} %{buildroot}/usr/share/doc/$NOME/README.md

%files
/usr/bin/$NOME
%license /usr/share/licenses/$NOME/LICENSE
%doc /usr/share/doc/$NOME/README.md
EOF

    rpmbuild -bb --quiet \
        --define "_topdir $topo" \
        --define "dist %{nil}" \
        "$topo/SPECS/$NOME.spec"

    saida=$(find "$topo/RPMS" -type f -name '*.rpm' -print -quit)
    if [[ -z $saida ]]; then
        echo "${CER}O rpmbuild terminou sem gerar o pacote.${C0}" >&2
        return 1
    fi
    mkdir -p -- "$DIST"
    cp -- "$saida" "$DIST/"
    echo "${CVER}✓${C0} $DIST/$(basename -- "$saida")"
}

# ───────────────────────────── Pacman ─────────────────────────────

criar_pacman() {
    if ! command -v makepkg >/dev/null 2>&1; then
        aviso_instalacao makepkg pacman pacman pacman
        return 1
    fi

    local dir=$TMP/pacman soma1 soma2 soma3 pacote
    echo "${CC}▸${C0} Gerando pacote do Pacman ${CB}$VERSAO${C0}"
    mkdir -p -- "$dir"
    cp -- thander-copy.sh LICENSE README.md "$dir/"
    soma1=$(sha256sum "$dir/thander-copy.sh" | cut -d' ' -f1)
    soma2=$(sha256sum "$dir/LICENSE" | cut -d' ' -f1)
    soma3=$(sha256sum "$dir/README.md" | cut -d' ' -f1)

    cat >"$dir/PKGBUILD" <<EOF
# Maintainer: $MANUTENCAO
pkgname=$NOME
pkgver=$VERSAO
pkgrel=$RELEASE
pkgdesc="$RESUMO"
arch=('any')
url="$URL"
license=('MIT')
depends=('bash' 'rsync' 'gawk' 'findutils' 'coreutils')
optdepends=(
    'util-linux: detecta o sistema de arquivos e dispositivos removíveis'
    'python: verificação completa mais rápida'
    'udisks2: ejetar o dispositivo sem precisar de root'
    'psmisc: mostra quais programas estão usando o dispositivo'
)
options=('!strip' '!debug')
source=('thander-copy.sh' 'LICENSE' 'README.md')
sha256sums=('$soma1' '$soma2' '$soma3')

package() {
    install -Dm755 "\$srcdir/thander-copy.sh" "\$pkgdir/usr/bin/$NOME"
    install -Dm644 "\$srcdir/LICENSE" "\$pkgdir/usr/share/licenses/$NOME/LICENSE"
    install -Dm644 "\$srcdir/README.md" "\$pkgdir/usr/share/doc/$NOME/README.md"
}
EOF

    (cd -- "$dir" && makepkg --noconfirm --clean >/dev/null)
    pacote=$(find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.*' -print -quit)
    if [[ -z $pacote ]]; then
        echo "${CER}O makepkg terminou sem gerar o pacote.${C0}" >&2
        return 1
    fi
    mkdir -p -- "$DIST"
    cp -- "$pacote" "$DIST/"
    echo "${CVER}✓${C0} $DIST/$(basename -- "$pacote")"
}

# ───────────────────────────── Escolha ─────────────────────────────

uso() {
    cat <<EOF
Uso: ./empacotar.sh [debian|rpm|pacman|todos]

Sem argumento, pergunta qual pacote criar. Os arquivos vão para dist/.
EOF
}

ALVOS=()
case ${1:-} in
    "")
        if [[ ! -t 0 ]]; then
            uso >&2
            exit 2
        fi
        echo
        echo "${CB}Qual pacote deseja criar do thander-copy?${C0}  ${CC}v$VERSAO${C0}"
        echo
        PS3=$'\nNúmero da opção: '
        colunas=${COLUMNS:-80}
        COLUMNS=1
        select _ in "Debian (.deb)" "RPM (.rpm)" "Pacman (.pkg.tar.zst)" "Os três"; do
            case $REPLY in
                1 | debian | deb) ALVOS=(deb); break ;;
                2 | rpm) ALVOS=(rpm); break ;;
                3 | pacman | arch) ALVOS=(pacman); break ;;
                4 | todos | all) ALVOS=(deb rpm pacman); break ;;
                *) echo "Opção inválida. Escolha de 1 a 4." ;;
            esac
        done
        COLUMNS=$colunas
        ;;
    debian | deb) ALVOS=(deb) ;;
    rpm) ALVOS=(rpm) ;;
    pacman | arch) ALVOS=(pacman) ;;
    todos | all) ALVOS=(deb rpm pacman) ;;
    -h | --ajuda | --help) uso; exit 0 ;;
    *)
        echo "Opção desconhecida: $1" >&2
        uso >&2
        exit 2
        ;;
esac

echo
falhas=0
for alvo in "${ALVOS[@]}"; do
    case $alvo in
        deb) criar_deb || falhas=$((falhas + 1)) ;;
        rpm) criar_rpm || falhas=$((falhas + 1)) ;;
        pacman) criar_pacman || falhas=$((falhas + 1)) ;;
    esac
done

if (( falhas == 1 )); then
    echo >&2
    echo "${CAM}!${C0} 1 pacote não foi gerado." >&2
    exit 1
elif (( falhas > 1 )); then
    echo >&2
    echo "${CAM}!${C0} $falhas pacotes não foram gerados." >&2
    exit 1
fi
