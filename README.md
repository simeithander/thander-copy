# ⚡ THANDER COPY

> **Uma ferramenta de terminal para copiar arquivos e pastas com verificação de integridade, barra de progresso animada, visual moderno e feedback detalhado!**

---

## ✨ **Destaques do Projeto**

- Visual inspirado em **neofetch** e **btop** (cores, caixas, separadores, emojis)
- Cópia robusta com `rsync` e verificação de integridade (checksum)
- Barra de progresso animada estilo Pacman durante análise
- Resumo visual da cópia ao final
- Mensagens de erro e sucesso destacadas
- Suporte a caminhos com espaços e autocompletar
- Experiência agradável mesmo com listas grandes de arquivos

---

## 🚀 **Como Usar**

```bash
chmod +x thander-copy.sh
./thander-copy.sh
```

1. **Execute o script** no terminal.
2. **Arraste ou digite** o caminho do arquivo/pasta de ORIGEM e pressione Enter.
3. **Arraste ou digite** o caminho da pasta de DESTINO e pressione Enter.
4. Aguarde a análise (com animação!) e a cópia dos arquivos.
5. Veja o resumo visual ao final!

---

## 🎨 **Exemplo Visual**

```
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃   ⚡  THANDER COPY - Cópia poderosa com integridade e estilo!   ⚡   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
🚀 Uma ferramenta poderosa para copiar arquivos e pastas com verificação de integridade.
💡 Para sair do script, pressione Ctrl + C
──────────────────────────────────────────────────────────────────────
Arraste ou digite o caminho do arquivo/pasta de ORIGEM e pressione Enter:
Arraste ou digite o caminho da pasta de DESTINO e pressione Enter:
💬 Lendo arquivos... (isso pode levar algum tempo dependendo do tamanho dos arquivos)
⏳ [██████████C○○○○○○○○○○○○○○○○○○] 9s
✅ Análise concluída! [████████████████████]
📊 Tamanho total: 1.5GB

──────────────────────────────────────────────────────────────────────
┌─[ Resumo da Cópia ]
│ ✅ Cópia concluída e dados verificados com sucesso!
│ Origem: /caminho/origem
│ Destino: /caminho/destino
│ Tempo: 16s
│ Tamanho: 1.5GB
└
──────────────────────────────────────────────────────────────────────
```

---

## ⚙️ **Requisitos**

- **Bash** 4+ (testado no Linux)
- **rsync**
- **awk**
- Terminal com suporte a cores ANSI (praticamente todos)

---

## 📝 **Funcionalidades**

- Cópia de arquivos e pastas com preservação de permissões, datas e donos
- Verificação de integridade via checksum (garante que tudo foi copiado corretamente)
- Feedback visual durante análise e cópia
- Resumo final com tempo, tamanho e status
- Mensagens de erro amigáveis
- Suporte a caminhos com espaços e autocompletar

---

## ⚠️ **Limitações**

- Não mostra barra de progresso customizada durante o rsync (usa a do próprio rsync)
- Não faz cópia entre hosts remotos (apenas local)
- Não há opção de exclusão/remoção, apenas cópia
- Não há interface gráfica (apenas terminal)
- Listas muito grandes do rsync podem poluir o terminal, mas o resumo final sempre aparece destacado

---

## 👨‍💻 **Autor & Licença**

- Feito por Simei Thander com auxilio do Claude 4
- Licença MIT

---

## ⭐ **Contribua!**

Sugestões, issues e pull requests são muito bem-vindos!
