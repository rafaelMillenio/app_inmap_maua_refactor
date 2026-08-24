
# InMap Mauá — Log de Alterações (V7 -> V8)

Documentação do histórico de atualizações, refatorações e correções efetuadas no projeto **InMap Mauá**.

---

## 📋 Changelog

### 🟢 [7.02] 

#### Refatoração
- Fotos login e menu, renomeadas para facilitar migração de cidade (procure as outras para trocar tudo)
- 

---

### 🔵 [7.01] - Correções e Padronizações
#### 🎨 Interface & UI
- **Página de Login:**
  - Estilo do botão **"Esqueci a Senha"** corrigido.
  - Centralização dos botões **Entrar**, **Cadastrar** e **Visitante**.
- **Impressão Imobiliária (Empresas):**
  - Tela `print` padronizada para o modelo do município de Mauá ao clicar em um lote.

#### ⚙️ Backend & Regras de Negócio
- **`t_memo_registro` (Events):**
  - Query sincronizada e igualada à versão do servidor de produção (220).
- **Segurança & Autenticação:**
  - Mapeamento de usuários na aba de segurança atualizado para fazer referência à tabela `t_users`.

---

### 🟡 [7.00] - Migração de Engine & Refatoração Base
#### 🚀 Infraestrutura
- Implementação do **PHPRunner 11** para ambiente de testes.

#### 🛠️ Correções & Refatorações
- **Caixa de Seleção de Grupos:** Ajuste nos estilos e seletores de grupo.
- **Memorial Descritivo:** Adição e geração de memorial descritivo restabelecidas.
- **Impressão Imobiliária Default (`print`):**
  - Correção no fluxo de impressão acionado ao clicar em um lote.
  - Layout e regras pareados com o padrão do servidor de produção (220).
- **Visualização Imobiliária Default (`view`):**
  - Refatoração completa da tela de visualização para manter equivalência com o servidor 220.

---

> **Servidor de Referência:** `Servidor 220`