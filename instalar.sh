#!/usr/bin/env bash
# Instala o cashbook-mcp (Open Finance → Claude) numa máquina sua: Mac, Linux ou Windows (dentro do WSL2).
# Pode rodar quantas vezes quiser: cada passo pula o que já está feito.
#
#   ./instalar.sh                 instala ou continua de onde parou (pergunta o modo)
#   ./instalar.sh --modo misto    já escolhe o modo: mao | misto | auto
#   ./instalar.sh --checar        só confere a máquina
#   ./instalar.sh status          mostra se o servidor está no ar
#   ./instalar.sh docker          (Windows/WSL) instala o Docker dentro do Ubuntu
#
# Comandos sem pergunta nenhuma, para o Claude usar no modo automático:
#   ./instalar.sh configurar --tailnet tail1234.ts.net --email voce@gmail.com
#   ./instalar.sh guardar pluggy-id <client id>
#   ./instalar.sh guardar pluggy-secret      (lê da área de transferência, no Mac)
#   ./instalar.sh guardar tailscale          (lê da área de transferência, no Mac)
#   ./instalar.sh guardar google [arquivo]   (sem arquivo: o client_secret_*.json mais novo em ~/Downloads)
#   ./instalar.sh subir                      (banco, isolamento, subida e teste)
#
# Segredo nenhum aparece na tela: eles vão direto para cashbook-mcp/secrets/.
set -euo pipefail

UPSTREAM_URL="https://github.com/TrainedLoop/cashbook-mcp.git"
UPSTREAM_COMMIT="4516d8a"   # versão revisada; troque só depois de revisar a nova
IMAGEM="ghcr.io/trainedloop/cashbook-mcp:0.2"
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$KIT/cashbook-mcp"
IMG="$KIT/docs/img"
SO="$(uname -s)"
MODO="${CASHBOOK_MODO:-}"
WSL=0   # 1 = Windows, rodando dentro do WSL2
if [ "$SO" = "Linux" ] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then WSL=1; fi
UID_APP=10001   # usuário do container do cashbook-mcp

if [ -d "$HOME/.orbstack/bin" ]; then export PATH="$HOME/.orbstack/bin:$PATH"; fi

ok()    { printf '  \033[32m✓\033[0m %s\n' "$*"; }
falta() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
aviso() { printf '  \033[33m!\033[0m %s\n' "$*"; }
passo() { printf '\n\033[1m▸ %s\033[0m\n' "$*"; }
pare()  { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
pergunta() {
  local r
  read -r -p "  $1 " r || pare "Entrada encerrada: rode ./instalar.sh num terminal, ou use os comandos sem pergunta (veja o topo do script)."
  printf '%s' "$r"
}
espera_enter() { [ "$MODO" = "misto" ] || return 0; pergunta "Quando terminar, aperte Enter…" >/dev/null; }

abrir() {
  if [ "$SO" = "Darwin" ]; then open "$@" 2>/dev/null || true
  elif [ "$WSL" = 1 ]; then   # abre no Windows: o navegador e o visualizador de imagens de lá
    local a; for a in "$@"; do   # em segundo plano e com limite: abrir nunca segura o instalador
      case "$a" in
        http*) (cd /mnt/c && timeout 20 cmd.exe /c start "" "$a" >/dev/null 2>&1 &) ;;
        *)     (cd /mnt/c && timeout 20 explorer.exe "$(wslpath -w "$a")" >/dev/null 2>&1 &) ;;
      esac
    done
  else xdg-open "$@" >/dev/null 2>&1 || true; fi
}

# No modo misto, abre a página certa e os prints marcados do passo.
mostrar() {
  local url="$1"; shift
  [ "$MODO" = "misto" ] || return 0
  echo "  abrindo $url e o print com as marcações…"
  local f; for f in "$@"; do abrir "$IMG/$f"; done
  abrir "$url"
}

compose() {
  local extra=()
  if [ "$SO" = "Darwin" ]; then extra=(-f local/compose.mac-firewall.yml); fi
  (cd "$APP" && docker compose -f docker-compose.yml -f examples/tailscale-sidecar/compose.yml ${extra[@]+"${extra[@]}"} "$@")
}

valor_env() { grep -E "^$1=" "$APP/.env" 2>/dev/null | head -1 | cut -d= -f2-; }

# Segredo: só o seu usuário lê (Mac). No Linux o container roda como 10001, então o grupo 10001 também lê.
protege() {
  if [ "$SO" = "Linux" ]; then sudo chgrp "$UID_APP" "$@"; chmod 640 "$@"; else chmod 600 "$@"; fi
}

# Lê um segredo sem mostrar: no Mac, da área de transferência; senão, digitado às cegas.
le_segredo() {
  local rotulo="$1" interativo="${2:-sim}" v
  if [ "$SO" = "Darwin" ] && command -v pbpaste >/dev/null; then
    if [ "$interativo" = sim ]; then pergunta "Copie $rotulo e aperte Enter (leio da área de transferência)…" >/dev/null; fi
    v="$(pbpaste | tr -d '[:space:]')"
    printf '' | pbcopy
  else
    [ "$interativo" = sim ] || pare "No Linux o segredo é digitado: rode ./instalar.sh num terminal."
    read -r -s -p "  Cole $rotulo (não aparece) e aperte Enter: " v || pare "Entrada encerrada."
    echo >&2
    v="$(printf '%s' "$v" | tr -d '[:space:]')"
  fi
  printf '%s' "$v"
}

# ---------------------------------------------------------------- checagem e modo
checar() {
  passo "Conferindo a máquina"
  local faltou=0
  case "$SO" in
    Darwin) ok "macOS" ;;
    Linux)  if [ "$WSL" = 1 ]; then ok "Windows (WSL2, ${WSL_DISTRO_NAME:-Ubuntu})"; else ok "Linux"; fi ;;
    *) falta "sistema $SO não suportado. No Windows, rode dentro do Ubuntu do WSL2 (GUIA.md, passo 5)"; faltou=1 ;;
  esac
  if [ "$WSL" = 1 ]; then
    if ! grep -qi wsl2 /proc/sys/kernel/osrelease; then falta "este Ubuntu está no WSL1. No PowerShell: wsl --set-version ${WSL_DISTRO_NAME:-Ubuntu} 2"; faltou=1; fi
    case "$KIT" in /mnt/*) falta "o kit está numa pasta do Windows ($KIT). Clone dentro do Ubuntu: cd ~ && git clone …"; faltou=1 ;; esac
    if [ -d /run/systemd/system ]; then ok "systemd ligado"
    else falta "systemd desligado. Abra o arquivo (sudo nano /etc/wsl.conf), deixe na seção [boot] a linha systemd=true e, no PowerShell, rode wsl --shutdown"; faltou=1; fi
  fi
  local c
  for c in git curl python3; do
    if command -v "$c" >/dev/null; then ok "$c"; else falta "$c não encontrado"; faltou=1; fi
  done
  if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    ok "Docker rodando"
    if docker compose version >/dev/null 2>&1; then ok "docker compose"; else falta "docker compose não encontrado"; faltou=1; fi
    local info; info="$(docker info 2>/dev/null || true)"
    if [ "$SO" = "Darwin" ] && ! grep -qi orbstack <<<"$info"; then
      aviso "este kit foi testado no Mac com o OrbStack; com outro Docker o isolamento pode não valer"
    fi
    if [ "$WSL" = 1 ] && grep -qi 'docker desktop' <<<"$info"; then
      falta "este é o Docker Desktop: o isolamento não chega nos containers dele. Desligue a integração dele com este Ubuntu e rode ./instalar.sh docker"
      faltou=1
    fi
  else
    if [ "$SO" = "Darwin" ]; then
      falta "Docker não está rodando. No Mac use o OrbStack (https://orbstack.dev): instale, abra uma vez e rode de novo."
    elif [ "$WSL" = 1 ] && command -v docker >/dev/null && ! id -nG | grep -qw docker && getent group docker | grep -qw "$USER"; then
      falta "o Docker está instalado, mas este terminal ainda não está no grupo docker. Feche o Ubuntu, abra de novo e rode ./instalar.sh"
    elif [ "$WSL" = 1 ]; then
      falta "Docker não encontrado. Instale dentro do Ubuntu (não o Docker Desktop): ./instalar.sh docker"
    else
      falta "Docker não está rodando (https://docs.docker.com/engine/install/)."
    fi
    faltou=1
  fi
  [ "$faltou" = 0 ] || pare "Resolva o que está com ✗ e rode ./instalar.sh de novo."
}

escolher_modo() {
  if [ "$MODO" = auto ]; then modo_auto; fi
  [ -z "$MODO" ] || return 0
  cat <<'EOF'

Como você quer fazer as etapas de navegador (Pluggy, Tailscale, Google)?
  1  Na mão     você segue o GUIA.md (com prints) e o script só pede as chaves
  2  Misto      o script abre cada página na hora certa, mostra o print com onde clicar e espera você
  3  Automático o Claude Code pilota o seu Chrome; você só faz login, aceita termos e aprova no banco
EOF
  case "$(pergunta 'Escolha 1, 2 ou 3 [2]:')" in
    1) MODO=mao ;;
    3) MODO=auto ;;
    *) MODO=misto ;;
  esac
  if [ "$MODO" = auto ]; then modo_auto; fi
}

modo_auto() {
  if [ "$WSL" = 1 ]; then
    echo; echo "  No Windows o modo automático ainda não é suportado (o Claude Code no WSL pilotando o Chrome do Windows não foi testado)."
    echo "  Rode de novo e escolha 1 ou 2."; exit 0
  fi
  cat <<'EOF'

Modo automático: abra o Claude Code nesta pasta e peça para ele instalar:
    cd cashbook-kit && claude
    > instala o cashbook pra mim
Ele usa a extensão Claude in Chrome (https://claude.com/chrome). Se preferir não usar, rode de novo e escolha 2.
EOF
  exit 0
}

# ---------------------------------------------------------------- Windows (WSL2)
instalar_docker_wsl() {
  [ "$WSL" = 1 ] || pare "Este comando é para o Windows (WSL2). No Linux: https://docs.docker.com/engine/install/"
  passo "Docker dentro do Ubuntu (repositório oficial da Docker; precisa de sudo)"
  [ -d /run/systemd/system ] || pare "O systemd está desligado neste Ubuntu: rode ./instalar.sh --checar para ver como ligar."
  if command -v docker >/dev/null; then ok "Docker já instalado"; else
    . /etc/os-release
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl git python3 >/dev/null
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
    ok "Docker instalado"
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1
  if id -nG | grep -qw docker; then ok "seu usuário já usa o Docker"; return; fi
  sudo usermod -aG docker "$USER"
  echo
  echo "  Falta uma coisa: feche esta janela do Ubuntu, abra de novo e rode ./instalar.sh"
  echo "  (o acesso ao Docker só vale numa sessão nova)."
  exit 0
}

# Variável de ambiente do Windows, em UTF-8 (o cmd.exe devolve "João" na codepage antiga e o caminho quebra).
win_var() {
  (cd /mnt/c && powershell.exe -NoProfile -NonInteractive -Command \
    "[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Environment]::GetEnvironmentVariable('$1')" 2>/dev/null) | tr -d '\r' || true
}

manter_ligado_windows() {
  [ "$WSL" = 1 ] || return 0
  passo "Windows: manter o servidor ligado"
  local ps1 tmp saida
  tmp="$(win_var TEMP)"
  [ -n "$tmp" ] || pare "Não consegui ler a pasta temporária do Windows (%TEMP%)."
  ps1="$(wslpath "$tmp")/cashbook-manter-ligado.ps1"
  cp "$KIT/windows/manter-ligado.ps1" "$ps1" || pare "Não consegui copiar o script para $tmp."
  saida="$(cd /mnt/c && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$tmp\\cashbook-manter-ligado.ps1" -Distro "${WSL_DISTRO_NAME:?}" 2>&1 | tr -d '\r')" \
    || { printf '%s\n' "$saida" | sed 's/^/  /'; rm -f "$ps1"; pare "Não consegui configurar o Windows para manter o WSL ligado (veja acima)."; }
  rm -f "$ps1"
  printf '%s\n' "$saida" | sed -e 's/^ok /  ✓ /' -e 's/^aviso /  ! /'
  # dispara a tarefa agora: o Agendador do Windows segura o WSL ligado, mesmo depois que esta janela fechar
  if (cd /mnt/c && schtasks.exe /run /tn "cashbook-mcp (WSL)") >/dev/null 2>&1; then
    ok "o WSL fica ligado a partir de agora, mesmo com esta janela fechada"
  else
    aviso "não consegui disparar a tarefa: até reiniciar o PC, deixe uma janela do Ubuntu aberta"
  fi
}

# Pastas onde o navegador salva o JSON do Google (no Windows, a Downloads de lá).
pastas_downloads() {
  echo "$HOME/Downloads"
  if [ "$WSL" = 1 ]; then
    local p; p="$(win_var USERPROFILE)"
    [ -z "$p" ] || echo "$(wslpath "$p")/Downloads"
  fi
}

# ---------------------------------------------------------------- código e imagem
baixar_codigo() {
  passo "Código do cashbook-mcp (versão revisada $UPSTREAM_COMMIT)"
  if [ ! -d "$APP/.git" ]; then git clone -q "$UPSTREAM_URL" "$APP"; fi
  (cd "$APP" && git fetch -q origin && git -c advice.detachedHead=false checkout -q "$UPSTREAM_COMMIT")
  ok "código em $APP"
  if [ ! -d "$APP/secrets" ]; then
    mkdir -p "$APP/data" "$APP/secrets"
    if [ "$SO" = "Linux" ]; then
      echo "  No Linux e no WSL o container roda como o usuário $UID_APP: preciso de sudo para dar acesso às pastas."
      sudo chgrp "$UID_APP" "$APP/data" "$APP/secrets"; chmod 770 "$APP/data" "$APP/secrets"
    else
      chmod 700 "$APP/secrets"
    fi
  fi
  if [ "$SO" = "Darwin" ]; then
    mkdir -p "$APP/local"
    cp "$KIT/mac/mac-firewall.sh" "$KIT/mac/compose.mac-firewall.yml" "$APP/local/"
    grep -qx '/local/' "$APP/.git/info/exclude" 2>/dev/null || echo '/local/' >> "$APP/.git/info/exclude"
  fi
  passo "Imagem do servidor"
  if docker image inspect "$IMAGEM" >/dev/null 2>&1; then
    ok "já compilada"
  else
    echo "  compilando (alguns minutos na primeira vez)…"
    (cd "$APP" && docker build -q -t "$IMAGEM" . >/dev/null)
    ok "compilada"
  fi
}

# ---------------------------------------------------------------- contas (navegador)
etapa_pluggy() {
  passo "1. Pluggy e Meu Pluggy (GUIA.md, passos 1 e 2)"
  if [ -f "$APP/secrets/pluggy.json" ]; then ok "chaves da Pluggy já guardadas"; return; fi
  echo "  Crie a conta em dashboard.pluggy.ai e anote o Client ID; gere o secret em 'Gerenciar secret'."
  mostrar "https://dashboard.pluggy.ai/applications" 01-pluggy-aplicacoes.jpg
  echo "  Depois conecte seus bancos em meu.pluggy.ai, com o mesmo e-mail."
  mostrar "https://meu.pluggy.ai/connections" 02-meupluggy-conexoes.jpg
  espera_enter
}

etapa_tailscale_conta() {
  passo "2. Tailscale: HTTPS e nome do tailnet (GUIA.md, passo 3)"
  if [ -f "$APP/.env" ]; then ok "já configurado: $(valor_env PUBLIC_URL)"; return; fi
  echo "  Em DNS: ligue o HTTPS e copie o 'Tailnet name'."
  mostrar "https://login.tailscale.com/admin/dns" 03-tailscale-dns-nome.jpg 04-tailscale-https.jpg
  espera_enter
}

etapa_tailscale_regras() {
  passo "3. Tailscale: regras de acesso e chave (GUIA.md, passo 3)"
  if [ -f "$APP/secrets/ts-authkey" ] || docker volume inspect cashbook-mcp-tailscale >/dev/null 2>&1; then
    ok "chave do Tailscale já guardada"; return
  fi
  echo "  Em Access controls → JSON editor, aplique tailscale/politica.txt e salve."
  mostrar "https://login.tailscale.com/admin/acls/file" 05-tailscale-regras.jpg
  if [ "$MODO" = misto ]; then abrir "$KIT/tailscale/politica.txt"; fi
  espera_enter
  echo "  Em Settings → Keys → Generate auth key: Reusable e Ephemeral desligados, 1 dia, Tags com tag:cashbook."
  mostrar "https://login.tailscale.com/admin/settings/keys" 06-tailscale-chave.jpg
}

etapa_google() {
  passo "4. Google: o login (GUIA.md, passo 4)"
  if [ -f "$APP/secrets/google-oauth.json" ]; then ok "JSON do Google já guardado"; return; fi
  local url; url="$(valor_env PUBLIC_URL)"
  echo "  Crie o projeto, configure a tela de login (External), preencha a Branding e crie o client Web com:"
  echo "    $url/auth/callback"
  echo "    $url/admin/auth/callback"
  echo "  Baixe o JSON e publique o app em Audience."
  mostrar "https://console.cloud.google.com/auth/overview" 07-google-branding.jpg 08-google-client.jpg 09-google-publicar.jpg
  espera_enter
}

# ---------------------------------------------------------------- configuração e segredos
configurar_env() {   # $1 = tailnet, $2 = e-mail (vazios: pergunta)
  passo "Endereço e login"
  if [ -f "$APP/.env" ]; then ok "já configurado: $(valor_env PUBLIC_URL)"; return; fi
  local tailnet="${1:-}" email="${2:-}"
  if [ -z "$tailnet" ]; then echo "  O nome do tailnet aparece no Tailscale em DNS (ex.: tail1234.ts.net)."; fi
  while :; do
    [ -n "$tailnet" ] || tailnet="$(pergunta 'Nome do tailnet:')"
    tailnet="$(printf '%s' "$tailnet" | tr 'A-Z' 'a-z')"; tailnet="${tailnet#https://}"; tailnet="${tailnet%/}"
    [[ "$tailnet" =~ ^[a-z0-9-]+\.ts\.net$ ]] && break
    [ -z "${1:-}" ] || pare "Tailnet inválido: $tailnet (esperado algo.ts.net)"
    echo "  formato esperado: algo.ts.net"; tailnet=""
  done
  while :; do
    [ -n "$email" ] || email="$(pergunta 'Seu Gmail (o único login liberado):')"
    email="$(printf '%s' "$email" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
    [[ "$email" =~ ^[^@]+@[^@]+\.[a-z]+$ ]] && break
    [ -z "${2:-}" ] || pare "E-mail inválido: $email"
    echo "  e-mail inválido"; email=""
  done
  ( umask 077; cat > "$APP/.env" <<EOF
PUBLIC_URL=https://cashbook.$tailnet
ALLOWED_EMAILS=$email
TZ=America/Sao_Paulo
HISTORY_MONTHS=12
TS_HOSTNAME=cashbook
EOF
  )
  ok "endereço: https://cashbook.$tailnet"
}

guarda_pluggy() {   # $1 = client id (vazio: pergunta); $2 = sim|nao (interativo)
  local f="$APP/secrets/pluggy.json" id="${1:-}" secret
  [ -n "$id" ] || id="$(pergunta 'Client ID da Pluggy:')"
  id="$(printf '%s' "$id" | tr -d '[:space:]')"
  [[ "$id" =~ ^[0-9a-fA-F-]{36}$ ]] || pare "Client ID não parece válido (36 caracteres, com hífens)."
  secret="$(le_segredo 'o Client Secret' "${2:-sim}")"
  [ -n "$secret" ] || pare "Secret vazio."
  ( umask 077; ID="$id" SECRET="$secret" python3 -c 'import json,os;print(json.dumps({"clientId":os.environ["ID"],"clientSecret":os.environ["SECRET"]}))' > "$f" )
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' --data @"$f" https://api.pluggy.ai/auth || true)"
  if [ "$code" != 200 ]; then rm -f "$f"; pare "A Pluggy recusou as chaves (HTTP $code). Confira o Client ID, gere um secret novo e tente de novo."; fi
  protege "$f"
  ok "a Pluggy aceitou as chaves"
}

segredo_pluggy() {
  passo "Chaves da Pluggy"
  if [ -f "$APP/secrets/pluggy.json" ]; then ok "pluggy.json já existe"; return; fi
  guarda_pluggy "" sim
}

guarda_google() {   # $1 = caminho do JSON (vazio: o mais novo em ~/Downloads, e pergunta se interativo)
  local f="$APP/secrets/google-oauth.json" caminho="${1:-}" interativo="${2:-sim}" sugestao g
  if [ -z "$caminho" ]; then
    local d arqs=()
    while IFS= read -r d; do
      for g in "$d"/client_secret_*.json; do if [ -f "$g" ]; then arqs+=("$g"); fi; done
    done < <(pastas_downloads)
    sugestao="$( [ ${#arqs[@]} -gt 0 ] && ls -t "${arqs[@]}" | head -1 || true)"
    if [ "$interativo" = sim ]; then
      if [ -n "$sugestao" ]; then
        caminho="$(pergunta "Arquivo JSON do Google [Enter = $(basename "$sugestao")]:")"; caminho="${caminho:-$sugestao}"
      else
        caminho="$(pergunta 'Caminho do JSON baixado do Google (client_secret_….json):')"
      fi
    else
      caminho="$sugestao"
    fi
  fi
  caminho="${caminho/#\~/$HOME}"
  [ -f "$caminho" ] || pare "Arquivo do Google não encontrado: ${caminho:-(nenhum client_secret_*.json em Downloads)}"
  local url; url="$(valor_env PUBLIC_URL)"
  [ -n "$url" ] || pare "Configure o tailnet antes (./instalar.sh configurar …)."
  URL="$url" python3 - "$caminho" <<'PY' || pare "O JSON do Google não serve (veja a mensagem acima)."
import json, os, sys
d = json.load(open(sys.argv[1]))
w = d.get("web")
if not w: sys.exit("  ✗ o client precisa ser do tipo 'Web application'")
url = os.environ["URL"]
need = {url + "/auth/callback", url + "/admin/auth/callback"}
missing = need - set(w.get("redirect_uris", []))
if missing: sys.exit("  ✗ faltam estes redirecionamentos no client: " + ", ".join(sorted(missing)))
PY
  ( umask 077; cp "$caminho" "$f" ); protege "$f"
  ok "JSON do Google conferido e guardado"
  if [ "$interativo" = sim ]; then
    local r; r="$(pergunta "Apagar a cópia $(basename "$caminho") da pasta de origem? [s/N]")"
    if [[ "$r" =~ ^[sS]$ ]]; then rm -f "$caminho"; ok "cópia apagada"; fi
  else
    rm -f "$caminho"; ok "cópia em Downloads apagada"
  fi
}

segredo_google() {
  passo "JSON do Google"
  if [ -f "$APP/secrets/google-oauth.json" ]; then ok "google-oauth.json já existe"; return; fi
  guarda_google "" sim
}

guarda_tailscale() {   # $1 = sim|nao (interativo)
  local f="$APP/secrets/ts-authkey" k
  k="$(le_segredo 'a auth key (tskey-auth-…)' "${1:-sim}")"
  [[ "$k" == tskey-auth-* ]] || pare "Isso não parece uma auth key do Tailscale (começa com tskey-auth-)."
  ( umask 077; printf '%s' "$k" > "$f" ); protege "$f"
  ok "chave do Tailscale guardada"
}

segredo_tailscale() {
  passo "Chave do Tailscale"
  if [ -f "$APP/secrets/ts-authkey" ]; then ok "ts-authkey já existe"; return; fi
  if docker volume inspect cashbook-mcp-tailscale >/dev/null 2>&1; then
    ok "o servidor já entrou no tailnet antes"
    ( umask 077; : > "$APP/secrets/ts-authkey" ); protege "$APP/secrets/ts-authkey"   # o compose monta este arquivo
    return
  fi
  guarda_tailscale sim
}

# ---------------------------------------------------------------- banco, isolamento e subida
iniciar_banco() {
  passo "Chaves locais e banco de dados"
  if [ -f "$APP/data/cashbook.duckdb" ]; then ok "já iniciado"; return; fi
  local f; for f in pluggy.json google-oauth.json; do
    [ -f "$APP/secrets/$f" ] || pare "Falta secrets/$f. Rode ./instalar.sh (ou ./instalar.sh guardar …) antes."
  done
  docker run --rm -v "$APP/data:/data" -v "$APP/secrets:/secrets" "$IMAGEM" cashbook-admin init | sed 's/^/  /'
  [ -f "$APP/data/cashbook.duckdb" ] || pare "O init não criou o banco (veja acima)."
  ok "banco criado e criptografado"
}

isolar_linux() {
  [ "$SO" = "Linux" ] || return 0
  passo "Isolamento (firewall)"
  if systemctl is-active --quiet cashbook-mcp-firewall 2>/dev/null; then ok "firewall ativo"; return; fi
  echo "  Instalo o firewall do autor do cashbook-mcp como serviço do sistema (precisa de sudo)."
  sed "s#/opt/cashbook-mcp#$APP#" "$APP/examples/tailscale-sidecar/firewall/cashbook-mcp-firewall.service" \
    | sudo tee /etc/systemd/system/cashbook-mcp-firewall.service >/dev/null
  sudo systemctl daemon-reload && sudo systemctl enable --now cashbook-mcp-firewall
  ok "firewall ativo"
}

subir() {
  passo "Subindo"
  [ -f "$APP/secrets/ts-authkey" ] || pare "Falta a chave do Tailscale (./instalar.sh guardar tailscale)."
  local saida
  if ! saida="$(compose up -d --build 2>&1)"; then
    printf '%s\n' "$saida" | tail -15 | sed 's/^/  /'
    pare "O docker compose falhou (veja acima)."
  fi
  printf '%s\n' "$saida" | tail -3 | sed 's/^/  /'
  testar
}

testar() {
  local url host ips ip r
  url="$(valor_env PUBLIC_URL)"; host="${url#https://}"
  [ -n "$url" ] || pare "Ainda não instalado: rode ./instalar.sh."
  echo "  esperando o endereço público (o certificado leva até ~2 min na primeira vez)…"
  for _ in $(seq 1 36); do
    ips="$(python3 -c "import socket,sys;print(' '.join(sorted({a[4][0] for a in socket.getaddrinfo(sys.argv[1],443,socket.AF_INET)})))" "$host" 2>/dev/null || true)"
    # o Mac guarda por um tempo a falha de quando o endereço ainda não existia: pergunta direto ao 1.1.1.1
    if [ -z "$ips" ] && command -v dig >/dev/null; then ips="$(dig +short @1.1.1.1 "$host" A | grep -E '^[0-9.]+$' | tr '\n' ' ' || true)"; fi
    for ip in $ips; do
      r="$(curl -s --max-time 8 --resolve "$host:443:$ip" "$url/health" || true)"
      if [[ "$r" == *'"ok":true'* ]]; then
        ok "no ar: $url/health → $r"
        local mcp; mcp="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 --resolve "$host:443:$ip" "$url/mcp" || true)"
        if [ "$mcp" = 401 ]; then ok "/mcp pede login (401), como deve"; else falta "/mcp respondeu $mcp (esperado 401)"; fi
        return 0
      fi
    done
    sleep 5
  done
  falta "o endereço não respondeu em 3 min. Veja: docker logs cashbook-mcp-tailscale"
  echo "  Se o log falar de auth key inválida ou vencida: gere outra (GUIA.md, passo 3c) e rode"
  echo "    ./instalar.sh guardar tailscale && ./instalar.sh subir"
  return 1
}

proximos() {
  local url; url="$(valor_env PUBLIC_URL)"
  cat <<EOF

Pronto. Faltam dois passos seus (GUIA.md, passos 6 e 7):
  1. Abra $url/admin, entre com o Google e conecte o primeiro banco (Connect with MeuPluggy).
     Do segundo banco em diante: dashboard da Pluggy → Demo → Conectar Conta → MeuPluggy,
     copie o ID do item e use "Add existing item" no /admin.
  2. No claude.ai: Settings → Connectors → Add custom connector → $url/mcp

O servidor só funciona com esta máquina ligada. Ele volta sozinho quando o Docker sobe.
EOF
  if [ "$MODO" = misto ]; then abrir "$IMG/10-admin-botoes.jpg"; abrir "$url/admin"; fi
}

instalar() {
  checar; escolher_modo; baixar_codigo
  etapa_pluggy; segredo_pluggy          # o secret da Pluggy aparece uma vez só: guarda logo
  etapa_tailscale_conta; configurar_env
  etapa_tailscale_regras; segredo_tailscale
  etapa_google; segredo_google
  iniciar_banco; isolar_linux; manter_ligado_windows; subir && proximos
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0   # permite "source" nos testes

case "${1:-}" in
  ""|instalar) instalar ;;
  --modo) MODO="${2:-}"; [[ "$MODO" =~ ^(mao|misto|auto)$ ]] || pare "modos: mao, misto, auto"; instalar ;;
  --checar) checar; ok "máquina pronta para instalar" ;;
  status)
    [ -f "$APP/.env" ] || pare "Ainda não instalado: rode ./instalar.sh."
    compose ps --format '{{.Name}}  {{.Status}}'; testar ;;
  configurar)
    shift; t=""; e=""
    while [ $# -gt 0 ]; do case "$1" in --tailnet) t="${2:-}"; shift 2 ;; --email) e="${2:-}"; shift 2 ;; *) pare "opção desconhecida: $1" ;; esac; done
    [ -n "$t" ] && [ -n "$e" ] || pare "uso: ./instalar.sh configurar --tailnet algo.ts.net --email voce@gmail.com"
    checar >/dev/null; baixar_codigo >/dev/null; configurar_env "$t" "$e"
    url="$(valor_env PUBLIC_URL)"; echo "  redirects do Google: $url/auth/callback  $url/admin/auth/callback" ;;
  guardar)
    [ -d "$APP/secrets" ] || pare "Rode antes: ./instalar.sh configurar …"
    case "${2:-}" in
      pluggy-id)     [ -n "${3:-}" ] || pare "uso: ./instalar.sh guardar pluggy-id <client id>"; printf '%s' "$3" > "$APP/secrets/.pluggy-id"; ok "Client ID anotado" ;;
      pluggy-secret) [ -f "$APP/secrets/.pluggy-id" ] || pare "Antes: ./instalar.sh guardar pluggy-id <client id>"
                     guarda_pluggy "$(cat "$APP/secrets/.pluggy-id")" nao; rm -f "$APP/secrets/.pluggy-id" ;;
      tailscale)     guarda_tailscale nao ;;
      google)        guarda_google "${3:-}" nao ;;
      *) pare "uso: ./instalar.sh guardar pluggy-id <id> | pluggy-secret | tailscale | google [arquivo]" ;;
    esac ;;
  subir) checar >/dev/null; iniciar_banco; isolar_linux; manter_ligado_windows; subir && proximos ;;
  docker) instalar_docker_wsl ;;
  *) echo "uso: ./instalar.sh [--modo mao|misto|auto] | --checar | status | configurar | guardar | subir | docker"; exit 2 ;;
esac
