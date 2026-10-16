# EITA! Multiplayer — primeira versão conectada

Este pacote reaproveita o estilo visual do EITA! e adiciona uma primeira sala online:
- organizador cria sala e recebe código de 6 caracteres;
- amigos entram com código e apelido;
- lista de participantes e presença atualiza a cada 3 segundos;
- organizador pode iniciar ou encerrar a sala;
- acesso às salas é validado por tokens gerados no servidor e armazenados como hash no banco.

## O que esta etapa ainda NÃO faz
A tela conectada ainda não executa as seis perguntas, respostas e votação reais. O botão “Iniciar partida” muda o estado da sala para ativa; a integração das rodadas e da votação é a próxima etapa. O HTML local original foi mantido à parte.

## Configuração
1. No Supabase, abra **SQL Editor → New query**.
2. Copie todo o conteúdo de `supabase/schema.sql`, cole e clique em **Run**.
3. No Supabase, abra **Project Settings → API Keys** (ou **Connect**) e copie:
   - Project URL
   - publishable key (ou anon key pública legada)
4. Abra `config.js` e substitua `COLE_AQUI_A_PROJECT_URL` e `COLE_AQUI_A_CHAVE_PUBLICA`.
5. Publique a pasta `eita_multiplayer` em um host estático (Netlify, Vercel ou outro). Para testar localmente, use um servidor HTTP local; abrir o HTML com `file://` pode causar restrições do navegador.
6. Abra o endereço publicado em dois celulares/navegadores. Crie uma sala em um dispositivo e entre com o código no outro.

## Segurança
- Nunca coloque a `service_role` nem uma chave secreta no navegador.
- O acesso às tabelas é bloqueado para clientes; as ações passam por funções SQL com validação de token.
- Esta é uma primeira versão de lobby. Antes de usar publicamente, recomenda-se adicionar limites de criação de sala, proteção contra abuso e política de expiração/limpeza de salas antigas.

## Arquivos
- `index.html`: interface do lobby multiplayer
- `config.js`: URL e chave pública do projeto
- `supabase/schema.sql`: tabelas e funções SQL
- `eita_local_original.html`: protótipo original local, preservado para referência
