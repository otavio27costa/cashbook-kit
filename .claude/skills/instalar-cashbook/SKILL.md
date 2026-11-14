---
name: instalar-cashbook
description: Instala o cashbook-mcp (modo automático do kit) para a pessoa que clonou este repositório, pilotando o Chrome dela nas etapas de navegador (Pluggy, Tailscale, Google) e rodando os comandos sem pergunta do instalar.sh. Use quando ela disser "instala o cashbook", "me ajuda a configurar", "conecta meus bancos no Claude", "adiciona outro banco" ou "o conector caiu".
---

# Instalar o cashbook (Claude pilotando)

O caminho é o mesmo do GUIA.md, que tem os prints marcados de cada tela: use-os para se orientar. O Claude faz a
parte mecânica e a pessoa faz o que é dela. Use o Claude in Chrome, que é o Chrome dela e já está logado.
Antes de cada mudança numa conta dela, diga em uma linha o que vai mudar e espere o "sim".

## Regras de segredo (valem o tempo todo)
- **Depois que um segredo aparece na tela, não leia a página.** Isso vale para as três telas: o secret da Pluggy
  (depois de "Gerenciar secret"), a chave do Tailscale (depois de "Generate key") e o client do Google (a
  janela "OAuth client created"). Nessas telas, nada de screenshot, `get_page_text`, `read_page` ou `find`.
  Peça para a pessoa clicar no botão de copiar (ou "Download JSON") e avisar; só então rode o `guardar`.
- Os segredos entram na máquina **só** pelos comandos `./instalar.sh guardar …`, que leem da área de
  transferência (Mac) ou do arquivo baixado. Nunca os escreva em comando, arquivo ou mensagem.
- Login, criação de conta, aceite de termos (Pluggy Connect, User Data Policy do Google), CPF e aprovação no
  app do banco são da pessoa: pare e peça.

## No Linux
- Os comandos `guardar pluggy-secret` e `guardar tailscale` só leem da área de transferência no Mac. No Linux,
  peça para a pessoa rodar `./instalar.sh` no terminal dela, na hora dos segredos: ele pede cada um sem
  mostrar. O resto (navegador, `configurar`, `guardar google`, `subir`) segue igual.

## No Windows
- O modo automático ainda não é suportado no Windows (o Claude Code no WSL pilotando o Chrome do Windows não foi
  testado). Se
  `./instalar.sh --checar` disser "Windows (WSL2…)", avise e indique o modo misto (`./instalar.sh --modo misto`)
  e a seção "No Windows" do GUIA.md.

## 0. Antes de começar
- `./instalar.sh --checar`. Se faltar Docker no Mac, peça para instalar o OrbStack (orbstack.dev) e abrir uma
  vez.
- Pergunte se ela já tem conta em Pluggy, Meu Pluggy, Tailscale e Google Cloud. A criação e o login são dela.

## 1. Tailscale (login.tailscale.com/admin)
- **DNS:** leia o "Tailnet name". Se o HTTPS estiver desligado, peça o ok e clique em "Enable HTTPS".
- Rode `./instalar.sh configurar --tailnet <nome> --email <gmail dela>`. Ele baixa o código, compila a imagem
  e mostra os dois redirects do Google.
- **Access controls → JSON editor:** aplique `tailscale/politica.txt`. Leia o arquivo atual antes. Se
  `tagOwners` ou `nodeAttrs` já existirem, acrescente dentro deles em vez de duplicar. Mostre a ela o trecho
  que vai mudar e salve com o ok. O Tailscale valida: se recusar, corrija.
- **Settings → Keys → Generate auth key:** Reusable e Ephemeral desligados, Expiration 1, Tags com
  `tag:cashbook`. Clique em Generate key; a partir daí não leia a página. Peça para ela clicar no botão de
  copiar da chave e, quando ela avisar, rode `./instalar.sh guardar tailscale`.

## 2. Google (console.cloud.google.com)
- Crie o projeto `cashbook-mcp`. Em Google Auth Platform → Get started: app name, support email, External,
  contato. O **aceite da User Data Policy é dela**.
- **Branding:** home page `https://cashbook.<tailnet>`, privacy `https://cashbook.<tailnet>/privacy` (só o
  endereço; não precisa abrir), authorized domain `<tailnet>`, e Save.
- **Clients → Create client:** Web application, com os dois redirects. Clique em Create. Na janela do client
  criado, peça para ela clicar em "Download JSON" e fechar (não leia a janela), e rode
  `./instalar.sh guardar google`. Ele pega o
  `client_secret_*.json` mais novo de ~/Downloads, confere os redirects, guarda e apaga a cópia.
- **Audience → Publish app → Confirm.**

## 3. Pluggy (dashboard.pluggy.ai e meu.pluggy.ai)
- Em Aplicações, leia o Client ID do card "Pluggy Demo App" (não é segredo) e rode
  `./instalar.sh guardar pluggy-id <id>`.
- O secret: peça para ela clicar em "Gerenciar secret", gerar e copiar. Depois rode
  `./instalar.sh guardar pluggy-secret`. O comando testa as chaves na Pluggy na hora.
- Avise que pode ignorar "Solicitar produção", webhook, due diligence e "liberar dados reais".
- Meu Pluggy: ela conecta os bancos com o mesmo e-mail. Confira em meu.pluggy.ai/connections quantos ficaram
  ativos.

## 4. Subir
- `./instalar.sh subir`: cria o banco criptografado, liga o isolamento (no Linux pede sudo), sobe e testa.
  O final esperado é "✓ no ar … {"ok":true}" e "/mcp pede login (401)".

## 5. Bancos no /admin
- Primeiro banco: ela abre `/admin`, entra com o Google e usa "Connect with MeuPluggy" (um banco por vez).
- Do segundo em diante, o `/admin` recusa como duplicado, porque a Pluggy devolve a lista de itens vazia.
  O caminho é:
  1. Dashboard → Aplicações → ▷ do app (Demo) → Conectar Conta → conector **MeuPluggy**. Nunca o conector do
     banco direto: esse dá erro de sandbox.
  2. Ela escolhe o banco. O "Continuar" da Pluggy aceita termos, então é ela quem clica.
  3. Clique no item novo em "Itens Conectados" e leia o ID no topo do painel (ou o `itemId` da URL). Esse ID
     não é segredo.
  4. No `/admin`: Add existing item → apelido + ID → Preview → Add connection (Personal).
- O ID do link do meu.pluggy.ai não é o do item: ele dá 404.

## 6. Claude
- claude.ai → Settings → Connectors → Add custom connector → `https://cashbook.<tailnet>/mcp`.
- Teste com `list_connections` e `finance_overview`. Mostre só os totais, não a lista de transações.

## Quando algo quebra
- `./instalar.sh status`. São três containers no Mac (app, tailscale, firewall) e dois no Linux.
- Endereço não responde: `docker logs cashbook-mcp-tailscale` (o certificado leva ~1 min na primeira vez).
- A chave do Tailscale venceu antes de subir: gere outra e rode `./instalar.sh guardar tailscale` de novo.
- A máquina dormiu: o conector cai e volta quando ela acorda.
