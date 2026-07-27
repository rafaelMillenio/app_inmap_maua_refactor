# 🏙️ Guia de Implantação e Parametrização do InMap

Este documento detalha o procedimento operacional padrão para inicializar o banco de dados, configurar a aplicação no PHPRunner e realizar o deploy do projeto para um novo município.

---

## 🗄️ 1. Inicialização e Restauração do Banco de Dados

1. Navegue até o diretório **`docs/`** na raiz do projeto.
2. Localize o script SQL do template de banco mais recente (`inmap_template.sql`).
3. Conecte-se ao gerenciador de banco de dados (Navicat / pgAdmin) do novo servidor PostgreSQL.
4. Execute o arquivo SQL no servidor para restaurar a estrutura padrão de tabelas, funções e visualizações zeradas para o novo município.

---

## ⚙️ 2. Configuração de Conexão e Tabelas no PHPRunner

1. Baixe e abra a versão mais recente do projeto no **PHPRunner 11**.
2. **Alterar a Conexão Global:**
   - Acesse a aba **Database / Connect**.
   - Atualize os parâmetros de conexão (Host/IP, Porta, Usuário, Senha e Nome do Banco de Dados) para apontar para o novo banco criado.
3. **Sincronizar a Conexão no Menu de Tabelas:**
   - Vá para a aba **Tables**.
   - No menu lateral esquerdo, clique com o botão direito sobre a conexão ativa e selecione a opção de modificar/sincronizar conexão para vincular ao novo schema.
4. **Validação da Sincronização:**
   - Certifique-se de que todas as tabelas e views do schema foram sincronizadas corretamente e estão selecionadas/marcadas para uso no PHPRunner.

---

## 🖼️ 3. Substituição dos Ativos Visuais e Mídias

1. Navegue até a pasta **`project/files/images/`**.
2. Substitua todos os arquivos de imagem (logos da prefeitura, brasões, ícones e cabeçalhos) e trocando os respectivos nomes no projeto tambem.
   > ⚠️ **Atenção:** Todas as fotos do projeto devem ser substituídas para evitar que elementos visuais ou marcas d'água de cidades anteriores permaneçam na interface do novo município.

---

## 🌐 4. Reconfiguração de Links Globais e Documentação

1. No PHPRunner, acesse a aba designer, / **Global Pages** no menu lateral e a aba .
2. Localize os botões e links de navegação externa do sistema.
3. Atualize as URLs para os endereços da nova cidade:
   - Link para o novo **Manual do Usuário**.
   - Links para as **CIUs externas** (Certidões de Informação Urbanística).
   - Links para portais e serviços da prefeitura local.
   - entre outros.

---

## 🔒 5. Validação de Segurança e Permissões de Usuários

1. Vá até a aba **Security** no PHPRunner.
2. Acesse a matriz de permissões/grupos de usuários (**User Group Permissions** / **Dynamic Permissions**).
3. Verifique se as camadas de acesso e visibilidade das tabelas estão setadas corretamente para cada nível de perfil (Admin, Consulta, Operador, etc.).

---

## 📂 6. Reconfiguração de Caminhos nos Eventos (Events)

1. Acesse a aba **Events** no PHPRunner.
2. Navegue até as views referentes a gestão de arquivos (todas as variações de `t_arquivos_...`).
3. Reconfigure o código do evento responsável pelo upload/salvamento para garantir que o caminho absoluto/relativo de destino no servidor esteja correto para a nova instância.

---

## 🚀 7. Configuração de Output e Build

1. Acesse a aba **Output** no PHPRunner.
2. Defina o diretório de saída correspondente ao servidor web em uso (exemplo: pasta `htdocs` para XAMPP, ou o diretório raiz do Apache/Nginx do novo servidor).
3. Compile e gere os arquivos da aplicação.