
# InMap Maua V6 -> v7 log

## 6.1
- excluir comum na tabela temas no geoserver config agora deleta relacao tema_pack se existir automaticamente
- botao deleta cascata para realizar a rotina de cima com a adicao de apagar todos os pacotes amarrados pelo tema_pack

## 6.2
- manual inmap atualizado
- responsividade para celular no login corrigido

## 6.3
- erro de registro de usuario PUBLICO resolvido (dashboard permissoes)
- botoes entrar, cadastrar, visitante e esqueci a senha reposicionados e centralizados (login page)
- modal esqueci a senha agora mostra nome do modal e nao geoportal (login page)
- tela de cadastro agora é um modal
- campos tipo, grupo base, ativo, user_type retirados (tela cadastro)

## 6.4
- botao deletar em cascata desativado por problemas na logica [revisao] (t_tema)
- lógica para adicionar o usuario ao grupo publico ao se registrar para que ele tenha este perfil (tela cadastro)
- nome e logo do print da t_imobiliario_default configurado para mostrar mauá 

## 6.5
- botão visitante registra na tabela acess_audit a entrada de visitantes para uso de dados na dashboard (tela de cadastro)
- resgistra ip do usuario para guardar segundo LGPD lei 12.965/2014(Art. 15)


# InMap Maua V5 -> V6 Log

## V5.1
- apontamento de armazenamento de arquivos para o storage no 253 (retrabalhando todo o codigo)
- função global para sanitizar nome de arquivos
- user ID do botão visitante na variavel de sessão da tela de login mudada de "28" para "5" para concertar problema de visitante adm

## V5.2
- apontamento arquivos_outros corrigido
- se o campo inscrição estiver vazio, configura que esta sem quadra

## V5.3
- corrigida apontamento de todas as telas
- corrigida apontamento storage todas as telas
- corrigida update que procura osasco em matricula

## V5.4
- corrigida a responsividade do painel

## V5.5
- corrigida a responsividade tela de login

## V5.6
- tela de registrar 

## V5.7
- melhorando responsividade do painel

## V6
- responsividade totalmente concertada (aba css da propria pagina carregando uma tag tr)
- painel adequado a botões que faltavam comparado a outras cidades
- dashboard removido
- inclusão de botão voltar em todas as tabelas internas do php runner
- logo e nome alterados

# InMap Maua V4 -> V5 Log

## V4.1
- Telas Sistema(fileman), GeoServer(web), PgAdmin e Portainer redirecionando corretamente

## V4.2
- CRUD da tabela t_depart_tabela na admin_cadastros
- padronização da tabela admin_cadastros

## V4.3
- conectar o crud da tabela grupo cadastro com todas as outras tabelas respectivas para preenchimento
- apontamento o webgis corrigido
- list concatenado no grupo x cadastro (agora o campo link aparece com o _list.php ao lado)
- fuid depart cadastro corrigido (agora esse campo é coletado e inserido na tabela)

## V4.4
- tabela depart cadastro com crud no cadastro
- replanejamento de organização de tabelas para a tela cadastro

## V4.5
- view depart_cadastro removida
- edit corrigida para salvar id (depart_cadastro) e bloquear usuario de alterar esse dado (depart_cadastro e grupo cadastro)

# TODO
- corrigir envio de varios arquivos de uma vez (só coloca contador caso varios arquivos sejam enviados de uma vez)
- implementar mostrar popup do inmap (perguntar para o nicholas)
- colocar confirmação de senha na tela de casdastro
- validação para nome de usuario não começar com numeros registro
- deletar em cascata na tabela t_tema não está funcionando
- novos usuarios não funcionam porque está apontando para a tabela de homologação
