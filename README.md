# cashbook-kit

Suas contas do banco no Claude, pelo Open Finance. Funciona em português, no Brasil, de graça.

Este kit instala o [cashbook-mcp](https://github.com/TrainedLoop/cashbook-mcp) numa máquina sua (Mac, Linux ou
Windows). O cashbook-mcp só **lê** os seus dados e não tem como pagar nem transferir nada. Ele busca saldos,
transações, faturas e investimentos pelo **Meu Pluggy**, guarda tudo num banco criptografado na sua máquina e
vira um conector do claude.ai (web, celular e rotinas). Aí você pergunta coisas como "quanto gastei com
delivery esse mês?" ou "minha conta vai ficar negativa antes do salário?".

Não é um serviço: ninguém vê os seus dados além de você. Cada pessoa sobe o próprio servidor, porque o uso
gratuito da Pluggy é só para dados de quem tem a conta.

## O que você precisa

- uma máquina que **fique ligada**:
  - Mac com [OrbStack](https://orbstack.dev);
  - Linux com Docker;
  - Windows 10 ou 11 com o Ubuntu do WSL2 (o script instala o Docker lá dentro; passo a passo no
    [GUIA.md](GUIA.md#no-windows)). Testado no Windows 10; no 11 deve funcionar igual, mas não foi testado;
- contas gratuitas em: Pluggy, Meu Pluggy, Tailscale e Google Cloud;
- uns 40 minutos.

## Três jeitos de instalar

Rode `./instalar.sh` e escolha:

| Modo | Como funciona | Para quem |
|---|---|---|
| **1 · Na mão** | Você segue o [GUIA.md](GUIA.md), que tem um print com as marcações de onde clicar em cada tela, e o script só pede as chaves no fim | quem gosta de ver cada passo |
| **2 · Misto** (padrão) | O script abre cada página no navegador na hora certa, junto com o print do passo, e espera você terminar | quem quer um empurrão, sem instalar mais nada |
| **3 · Automático** | O [Claude Code](https://claude.com/claude-code), com a extensão [Claude in Chrome](https://claude.com/chrome), pilota o seu Chrome e roda o script | quem já usa o Claude Code (Mac e Linux; no Windows ainda não) |

No modo automático:

```bash
git clone https://github.com/otavio27costa/cashbook-kit && cd cashbook-kit && claude
```

e diga **"instala o cashbook pra mim"**. O Claude faz a parte mecânica: as regras do Tailscale, o projeto e o
client do Google, a chave do Tailscale e o script. Ele **para e pede para você** fazer o que é seu: login,
aceitar termos, aprovar no app do banco e gerar ou copiar segredos. Os segredos vão da área de transferência
direto para `cashbook-mcp/secrets/` pelo próprio script, sem passar pela conversa.

## O que o `instalar.sh` faz

1. Confere a máquina (Docker, git, curl, python3; no Windows, também o WSL2, o systemd e se o Docker não é o
   Docker Desktop).
2. Baixa o cashbook-mcp **na versão revisada** (commit fixo no script) e compila a imagem.
3. Pede o nome do tailnet e o seu Gmail e mostra os dois endereços que vão no Google.
4. Recebe as chaves da Pluggy, do Google e do Tailscale e confere cada uma na hora (a Pluggy precisa aceitar,
   o JSON precisa ter os redirecionamentos certos, a chave precisa ter o formato certo).
5. Cria as chaves locais e o banco criptografado.
6. Liga o isolamento: o container exposto na internet só alcança a internet, nunca a sua máquina, a sua rede
   ou os seus aparelhos. No Mac isso é um serviço do próprio compose (`mac/`); no Linux e no Windows, o
   firewall do autor, como serviço do sistema. Num Linux comum (fora do WSL) esse caminho ainda não foi testado.
7. No Windows, deixa o servidor sempre ligado: uma tarefa agendada liga o Ubuntu quando o Windows inicia,
   mesmo sem ninguém entrar, e o mantém ligado (o Windows pede permissão de admin na primeira vez).
8. Sobe tudo, espera o certificado e testa o endereço público.

Pode rodar de novo quantas vezes quiser: ele pula o que já está pronto. `./instalar.sh --checar` só confere a
máquina e `./instalar.sh status` mostra se está no ar.

## Segurança, em uma lista

- Só leitura no banco: o cashbook-mcp só faz consultas na Pluggy. Além delas, só faz o login da API e gera o
  token do widget de conexão. Não existe código de pagamento nem de Pix nele.
- Login só do seu Gmail (`ALLOWED_EMAILS`), no conector e no `/admin`.
- Banco DuckDB criptografado, com a chave separada dos dados.
- Segredos em `cashbook-mcp/secrets/`, legíveis só pelo seu usuário. O script nunca os mostra na tela.
- Isolamento de rede: o container exposto só alcança a internet. No Mac (OrbStack), isso foi testado:
  Pluggy e Google ficaram abertos, e a sua máquina, a rede de casa (192.168.x, 10.x…) e o tailnet ficaram
  bloqueados. No Windows (Ubuntu 24.04 no WSL2, Docker Engine), o firewall do autor também foi testado: a
  internet abriu, e o roteador, o Windows (pelo IP da rede e pela ponte do WSL) e o próprio Ubuntu ficaram
  bloqueados, inclusive depois de reiniciar o PC sem ninguém logado. Num Linux comum é o mesmo firewall, mas
  ele não foi testado fora do WSL.

**Ainda não testado no Windows:** a instalação completa com contas reais (Pluggy, Google e Tailscale); a
janela de permissão do Windows (UAC) quando o usuário não está como admin, e o que acontece se ele recusar;
a recusa do Docker Desktop; o Ubuntu instalado pela Microsoft Store (o teste usou a imagem oficial do Ubuntu
24.04 importada); e as páginas e prints abrindo de verdade no modo misto.

## Créditos

O cashbook-mcp é de Daniel Porto ([TrainedLoop/cashbook-mcp](https://github.com/TrainedLoop/cashbook-mcp),
licença MIT). Este kit não copia o código dele, só baixa a versão revisada. O firewall do Mac
(`mac/mac-firewall.sh`) é uma adaptação do script do autor. Projeto não oficial, sem relação com a Pluggy.
