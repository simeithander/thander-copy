# ⚡ THANDER COPY

> **Copie e mova arquivos pelo terminal com integridade verificada, gravação garantida no dispositivo e um painel de progresso moderno.**

---

## 📦 **Instalação**

### Opção 1: Pacotes das Releases (Recomendado)

Pacotes pré-compilados estão disponíveis nas [Releases](https://github.com/simeithander/thander-copy/releases):

#### Para sistemas baseados em Debian/Ubuntu:
```bash
# Baixe o arquivo .deb da release mais recente
wget https://github.com/simeithander/thander-copy/releases/latest/download/thander-copy_*.amd64.deb

# Instale o pacote (Substitua o * pela versão)
sudo dpkg -i thander-copy_*.amd64.deb

# Se houver dependências faltando, execute:
sudo apt-get install -f
```

#### Para sistemas baseados em Red Hat/Fedora:
```bash
# Baixe o arquivo .rpm da release mais recente
wget https://github.com/simeithander/thander-copy/releases/latest/download/thander-copy-*.amd64.rpm

# Instale o pacote (Substitua o * pela versão)
sudo rpm -i thander-copy-*.amd64.rpm
```

### Opção 2: Instalação Automática via Script

Para instalar o script globalmente a partir do código fonte:

```bash
# Clone ou baixe o repositório
git clone <url-do-repositorio>
cd thander-copy

# Execute o instalador como root
sudo ./install.sh
```

Após a instalação, você poderá executar o comando `thander-copy` de qualquer diretório.

### Opção 3: Instalação Manual

Se preferir não instalar globalmente:

```bash
# Torne o script executável
chmod +x thander-copy.sh

# Execute diretamente
./thander-copy.sh
```

### Desinstalação

#### Para pacotes DEB/RPM:
```bash
# Debian/Ubuntu
sudo apt remove thander-copy

# Red Hat/Fedora
sudo rpm -e thander-copy
```

#### Para instalação via script:
```bash
sudo ./uninstall.sh
```

O script pedirá confirmação antes de remover o programa.

---

## ✨ **Destaques**

- **Copiar ou mover**: ao mover, a origem só é apagada depois que a cópia foi gravada e verificada
- **Gravação garantida no dispositivo**: ao terminar, nada fica pendente no cache, então o pendrive pode ser removido sem o aviso de "dispositivo ocupado"
- **Ejetar com segurança** direto pelo programa, mostrando quais programas estão usando o dispositivo se ele estiver ocupado
- **Verificação de integridade real**: checksum relendo os dados **do disco** (e não do cache da memória)
- **Progresso em tempo real**: barra contínua, bytes transferidos, velocidade atual e média, tempo decorrido, tempo restante, horário de término e arquivo atual
- **Retomada**: se a operação for interrompida, basta repeti-la; o que já foi copiado é pulado e entra na conta do progresso
- **Ciente do sistema de arquivos**: perfis próprios para FAT32, exFAT e NTFS, com alertas antes de começar (arquivos acima de 4 GB, nomes inválidos, links simbólicos, espaço livre)
- **Interface moderna**: assistente passo a passo, menus navegáveis com as setas, caixas, degradê de cores e resumo final

---

## 🚀 **Como Usar**

### Modo interativo

```bash
thander-copy
```

1. Escolha **Copiar** ou **Mover** (↑/↓ e Enter, ou as teclas numéricas).
2. **Arraste** um ou mais arquivos/pastas para o terminal, ou digite o caminho (TAB completa e ↑ recupera caminhos usados antes).
3. Informe a pasta de **destino**; se ela não existir, o programa oferece criá-la.
4. Escolha o tipo de **verificação**.
5. Confira o resumo e inicie.
6. Ao final, escolha entre uma nova operação, **ejetar o dispositivo** ou sair.

Pressione **Ctrl + C** durante uma operação para interrompê-la com segurança: o que já foi copiado é gravado no dispositivo antes de parar.

### Linha de comando

```bash
thander-copy [opções] ORIGEM... DESTINO
```

| Opção | Descrição |
|---|---|
| `-c`, `--copiar` | Copia (padrão) |
| `-m`, `--mover` | Move: apaga a origem só depois de verificar a cópia |
| `-v`, `--verificacao MODO` | `completa` (padrão), `rapida` ou `nenhuma` |
| `-y`, `--sim` | Não pede confirmação (cria o destino se necessário) |
| `-h`, `--ajuda` | Mostra a ajuda |
| `-V`, `--versao` | Mostra a versão |

Exemplos:

```bash
thander-copy ~/Fotos /run/media/$USER/PENDRIVE
thander-copy -m -y ~/Downloads/video.mp4 ~/Videos
thander-copy -v rapida ~/Projetos /mnt/backup
```

O código de saída é `0` quando tudo foi copiado (e verificado), e `1` caso contrário.

---

## 🎨 **Exemplo Visual**

```
  ⚡ THANDER COPY  v2.0.0
  Cópia e movimentação de arquivos com integridade verificada
  ──────────────────────────────────────────────────────────────────────────

  Copiando  ~/Fotos  →  /run/media/simei/PENDRIVE
  2.3 GB · 245 arquivos · PENDRIVE · exfat · USB

  ● Copiando

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╸━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   52.3%

    Transferido  1.2 GB de 2.3 GB
    Velocidade   38.4 MB/s · média 35.1 MB/s
    Tempo        00:32 decorrido · ~00:29 restante · termina às 21:45
    Itens        120 de 257
    Em cache     12.0 MB aguardando gravação no dispositivo
    Arquivo      Fotos/2024/IMG_2033.jpg
```

Ao final:

```
  ✓ Cópia        2.3 GB · 35.1 MB/s  01:05
  ✓ Gravação     cache gravado no dispositivo  (12.0 MB)  0.4s
  ✓ Verificação  245 arquivos idênticos · checksum relido do disco  00:41

  ╭─ Concluído ──────────────────────────────────────────────────────────────╮
  │ ✓ Cópia concluída e verificada                                           │
  │                                                                          │
  │ Origem       ~/Fotos                                                     │
  │ Destino      /run/media/simei/PENDRIVE                                   │
  │ Volume       2.3 GB · 245 arquivos                                       │
  │ Tempo total  01:46                                                       │
  │ Etapas       cópia 01:05 · gravação 0.4s · verificação 00:41             │
  │ Velocidade   35.0 MB/s  (média real, incluindo a gravação)               │
  │ Integridade  checksum idêntico relendo o disco                           │
  ╰──────────────────────────────────────────────────────────────────────────╯

  ✓ Todos os dados foram gravados em PENDRIVE. Já é seguro ejetar.
```

---

## 🔄 **Como funciona**

1. **Análise**: levanta tamanho e quantidade de arquivos em uma única passada e verifica espaço livre e limitações do sistema de arquivos de destino.
2. **Cópia**: `rsync` com opções adequadas ao destino. Em FAT/exFAT não são aplicados dono, permissões nem links (que esses sistemas não suportam), evitando falsos erros. Em dispositivos removíveis o cache é gravado periodicamente durante a cópia, para que a velocidade exibida seja a real.
3. **Gravação**: força a escrita de tudo o que está no cache para o dispositivo (`sync -f`), mostrando o progresso. Essa etapa sempre acontece, mesmo após erro ou interrupção.
4. **Verificação**:
   - **Completa**: descarta o cache dos arquivos copiados e compara o checksum de origem e destino relendo os dados do disco.
   - **Rápida**: compara tamanho e data de modificação.
5. **Remoção** (somente ao mover): apaga da origem apenas o que foi confirmado no destino. Se a origem e o destino estão no mesmo disco, a movimentação é instantânea (apenas renomeia).

---

## ⚙️ **Requisitos**

- **Bash** 4.4+ (Linux)
- **rsync**, **awk**, **find** e **coreutils**
- Opcionais, para recursos extras:
  - `findmnt` e `lsblk` (util-linux): detectam o sistema de arquivos e se o destino é removível
  - `python3`: descarta o cache antes da verificação completa (sem ele é usado o `dd`, mais lento com muitos arquivos)
  - `udisksctl`: ejeta o dispositivo sem precisar de root
  - `fuser` (psmisc): mostra quais programas mantêm o dispositivo ocupado

---

## ⚠️ **Limitações**

- Não faz cópia entre hosts remotos (apenas local)
- Não há interface gráfica (apenas terminal)
- O destino precisa ser uma pasta (não é possível renomear durante a cópia)

---

## 👨‍💻 **Autor & Licença**

- Feito por Simei Thander com auxilio do Claude 4
- Licença MIT

---

## ⭐ **Contribua!**

Sugestões, issues e pull requests são muito bem-vindos!
