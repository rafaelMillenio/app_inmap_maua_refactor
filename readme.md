
# Projeto InMap Mauá

Este repositório contém a estrutura de arquivos e configurações do projeto **InMap Mauá** para desenvolvimento e manutenção no PHPRunner.

---

## 📂 Estrutura de Diretórios

```text
APP_INMAP_MAUA/
├── docs/                                # Documentações técnicas
│   ├── readme_old_runner10_91.md        # Documentação história phprunner 10.91 pra baixo
│   └── deply_nova_cidade.md             # guia para migrar o projeto para outra cidade
│
├── project/                             # Conteúdo principal lido pelo PHPRunner
│   ├── project.json                     # Arquivo de configuração e importação do projeto
│   └── files/
│       └── images/                      # Recursos visuais e imagens utilizados no projeto
├── version.md                           # Documentação historia do projeto
└── readme.md                            # Documentação principal
```
### Detalhamento das Pastas:

- **`docs/`**: Reservada para documentos explicativos, históricos de versão e especificações técnicas do projeto.
- **`project/`**: Contém todo o código-fonte, regras e definições de telas gerenciadas pelo PHPRunner.
- **`project/project.json`**: Arquivo principal do projeto que deve ser selecionado para abrir ou importar a aplicação.
- **`project/files/images/`**: Diretório onde estão salvas todas as imagens e ativos visuais utilizados nas páginas do sistema.

---

## 🚀 Como Abrir / Importar o Projeto no PHPRunner

1. Abra o **PHPRunner** (versão 11 ou superior).
2. Na tela inicial, clique em **Import Project**.
3. Navegue até a pasta do repositório e acesse o diretório **`project/`**.
4. Selecione o arquivo **`project.json`** e clique em **Abrir**.
5. O PHPRunner carregará automaticamente todas as configurações, tabelas, layouts e conexões do sistema.

---

> ⚠️ **Nota:** Não altere a estrutura das pastas internas ou o caminho das imagens em `project/files/images/` para evitar a perda de referências visuais no PHPRunner.
