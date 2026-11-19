#!/usr/bin/env bash
# Entrypoint do servidor dedicado de Project Zomboid (Build 42).
# Gerenciado pelo Ansible (role gs_zomboid).
#
# 1. Instala o servidor na primeira vez ou atualiza SÓ quando o backup
#    liberou (arquivo /state/update-requested, criado pelo zomboid-backup).
# 2. Aplica o heap Java (-Xmx) no ProjectZomboid64.json, que é sobrescrito
#    a cada update do steamcmd.
# 3. Aplica as chaves gerenciadas (/config/server.ini) no <servername>.ini.
# 4. Sobe o servidor com o console ligado a um FIFO. Isso permite enviar
#    comandos (servermsg, save, quit) com docker exec e encerrar com "quit"
#    no SIGTERM, para o mundo ser salvo antes de o container parar.
set -Eeuo pipefail

APP_ID=380870
INSTALL_DIR=/opt/pzserver
ZOMBOID_DIR="${HOME}/Zomboid"
SERVERNAME="${PZ_SERVERNAME:-gameserver}"
JAVA_XMX="${PZ_JAVA_XMX:-6g}"
OVERRIDES=/config/server.ini
UPDATE_FLAG=/state/update-requested
CONSOLE=/tmp/pz-console

: "${PZ_ADMIN_PASSWORD:?PZ_ADMIN_PASSWORD não definido (ver .env)}"

log() { echo "[entrypoint] $*"; }

update_server() {
  # force_install_dir precisa vir ANTES do login. Branch padrão (Build 42
  # stable): sem -beta.
  /usr/games/steamcmd \
    +force_install_dir "${INSTALL_DIR}" \
    +login anonymous \
    +app_update "${APP_ID}" validate \
    +quit
}

if [[ ! -x "${INSTALL_DIR}/start-server.sh" ]]; then
  log "Servidor não instalado - instalação inicial (app ${APP_ID})."
  update_server
elif [[ -f "${UPDATE_FLAG}" ]]; then
  log "Update liberado pelo backup - atualizando (app ${APP_ID})."
  if update_server; then
    rm -f "${UPDATE_FLAG}"
  else
    log "AVISO: update falhou; subindo a versão já instalada (nova tentativa no próximo start)."
  fi
else
  log "Sem update liberado - subindo a versão instalada."
fi

# --- Heap Java ---------------------------------------------------------------
if [[ ! "${JAVA_XMX}" =~ ^[0-9]+[mMgG]$ ]]; then
  log "PZ_JAVA_XMX inválido: '${JAVA_XMX}' (use ex: 6g ou 6144m)"; exit 1
fi
PZ_JSON="${INSTALL_DIR}/ProjectZomboid64.json"
if [[ -f "${PZ_JSON}" ]]; then
  sed -i -E "s/\"-Xmx[0-9]+[kKmMgG]?\"/\"-Xmx${JAVA_XMX}\"/" "${PZ_JSON}"
  log "Heap Java: -Xmx${JAVA_XMX}"
fi

# --- Chaves gerenciadas do <servername>.ini -----------------------------------
# O próprio servidor reescreve o .ini ao iniciar (acrescenta todas as chaves
# padrão). Por isso o Ansible não é dono do arquivo inteiro: só das chaves em
# /config/server.ini, aplicadas aqui por cima a cada start.
apply_overrides() {
  local ini="${ZOMBOID_DIR}/Server/${SERVERNAME}.ini" line key tmp
  mkdir -p "${ZOMBOID_DIR}/Server"
  touch "${ini}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"
    tmp="$(mktemp)"
    KEY="${key}" LINE="${line}" awk '
      BEGIN { k = ENVIRON["KEY"] "="; l = ENVIRON["LINE"]; found = 0 }
      index($0, k) == 1 { print l; found = 1; next }
      { print }
      END { if (!found) print l }
    ' "${ini}" > "${tmp}"
    cat "${tmp}" > "${ini}"
    rm -f "${tmp}"
  done < "${OVERRIDES}"
  log "Configuração aplicada em ${ini}"
}
apply_overrides

# --- Console via FIFO + parada graciosa -----------------------------------------
rm -f "${CONSOLE}"
mkfifo -m 600 "${CONSOLE}"
# Abre o FIFO para leitura E escrita no próprio PID 1: o servidor nunca
# recebe EOF no stdin, mesmo quando ninguém está escrevendo.
exec 3<>"${CONSOLE}"

# -cachedir fixa a pasta Zomboid no volume. Sem ele o jogo usa o user.home do
# Java (vindo do /etc/passwd pelo UID), que não segue o $HOME do container.
"${INSTALL_DIR}/start-server.sh" \
  -cachedir="${ZOMBOID_DIR}" \
  -servername "${SERVERNAME}" \
  -adminpassword "${PZ_ADMIN_PASSWORD}" <&3 &
PZ_PID=$!

graceful_stop() {
  log "Sinal de parada recebido - enviando 'quit' (salva o mundo)."
  echo "quit" >&3
  wait "${PZ_PID}" || true
  log "Servidor encerrado."
  exit 0
}
trap graceful_stop TERM INT

wait "${PZ_PID}"
