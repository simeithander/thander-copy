# ⚡ THANDER COPY

> **Uma ferramenta de terminal para copiar arquivos e pastas com verificação de integridade, animações suaves, visual moderno e feedback detalhado!**

---

## 📦 **Instalação**

### Instalação Automática (Recomendada)

Para instalar o script globalmente e poder executá-lo de qualquer lugar:

```bash
# Clone ou baixe o repositório
git clone <url-do-repositorio>
cd thander-copy

# Execute o instalador como root
sudo ./install.sh
```

Após a instalação, você poderá executar o comando `thander-copy` de qualquer diretório.

### Instalação Manual

Se preferir não instalar globalmente:

```bash
# Torne o script executável
chmod +x thander-copy.sh

# Execute diretamente
./thander-copy.sh
```

---

## ✨ **Destaques do Projeto**

- Visual inspirado em **neofetch** e **btop** (cores, caixas, separadores, emojis)
- Cópia robusta com `rsync` e verificação de integridade (checksum)
- Animações suaves de spinner durante análise e sincronização
- Feedback visual em tempo real durante a cópia
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
4. Aguarde a análise (com animação de spinner!) e a cópia dos arquivos.
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
⠋ Lendo arquivos...
✅ Análise concluída!
📊 Tamanho total: 1.5GB

🔄 Iniciando cópia...
arquivo.iso
          2,83G 100%  762,05MB/s    0:00:03 (xfr#1, to-chk=0/1)
🔄 Iniciando sincronização...
⠙ Sincronizando dados...
✅ Sincronização concluída!
✅ Cópia concluída!

──────────────────────────────────────────────────────────────────────
┌─[ Resumo da Cópia ]
│ ✅ Dados verificados com sucesso!
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

- **Cópia Robusta**: Arquivos e pastas com preservação de permissões, datas e donos
- **Verificação de Integridade**: Checksum garante que tudo foi copiado corretamente
- **Animações Suaves**: Spinner animado durante análise e sincronização
- **Feedback em Tempo Real**: Progresso detalhado do rsync durante a cópia
- **Sincronização Visual**: Feedback específico durante o processo de sync (importante para USB/dispositivos externos)
- **Resumo Final**: Tempo, tamanho e status da operação
- **Mensagens de Erro Amigáveis**: Validações claras e orientações

---

## 🔄 **Processo de Cópia**

1. **Análise**: Calcula tamanho total com animação de spinner
2. **Cópia**: rsync com progresso detalhado em tempo real
3. **Sincronização**: Garante que dados em cache sejam escritos no dispositivo (especialmente importante para USB)
4. **Verificação**: Checksum confirma integridade dos dados
5. **Resumo**: Exibe estatísticas finais da operação

---

## ⚠️ **Limitações**

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
