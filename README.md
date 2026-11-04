# Estoque de Caixas de Emenda — V1

## Instalação
1. Crie um projeto Supabase e execute `schema.sql` no SQL Editor.
2. Em Authentication > Users, crie o login do gestor e os logins dos técnicos.
3. No SQL Editor, execute `insert into public.estoque_gestores(uid) values ('UUID-DO-GESTOR');` com o UUID real.
4. Associe cada login ao destino correspondente: `update public.estoque_destinos set auth_uid='UUID-DO-TECNICO' where nome='BERNARDO KM';` (repita por técnico).
5. Crie um repositório GitHub novo (recomendado: privado), envie `index.html`, `schema.sql` e este README; configure GitHub Pages ou outra hospedagem estática. GitHub Pages em repositórios privados depende do plano/configuração.
6. No site, informe a URL e a chave pública do Supabase. **Nunca** cole uma chave `service_role`.

## Regras V1
- Entrada apenas pelo gestor.
- Distribuição obrigatória de 2 caixas, somente quando saldo do destino = 0 e estoque central >= 2.
- Utilização exige incidente/OS, endereço/local, serviço e quantidade, com baixa imediata e validação no banco.
- Histórico por mês e responsável.
- OUTROS exige identificação textual no lançamento de distribuição. **Limitação V1:** o saldo de OUTROS é compartilhado; para controle individual de cada destinatário eventual, cadastre um destino específico na próxima versão.
- Registro de uso só pelo gestor ou pelo usuário vinculado ao destino.
- Movimentos não podem ser alterados diretamente por usuários autenticados (somente função RPC); ajustes administrativos devem ser tratados com lançamento de contrapartida, nunca exclusão do histórico.

## Limites da V1
- Um tipo de caixa (modelo ainda não separado).
- Até 10 mil movimentações carregadas no navegador; para volumes maiores implementar paginação e agregação SQL.
- Não há anexo de fotos, alerta de reposição nem cadastro de novos destinos pelo painel.
- Sem projeto Supabase configurado, o HTML não salva dados.
- O frontend depende de internet para carregar a biblioteca Supabase via CDN.

## Testes antes de produção
- Gestor cadastra entrada, distribui 2, técnico lança uso de 1 e depois 1, nova distribuição só após saldo 0.
- Testar bloqueio de entrega com saldo 1 e estoque central insuficiente.
- Testar login de técnico sem permissão para lançar entrada ou acessar movimentos de outros técnicos.
- Testar registro sem incidente e tentativa de baixa acima do saldo.
