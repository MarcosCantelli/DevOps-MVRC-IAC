#!/usr/bin/env bash
# Backup diário do Project Zomboid - gerenciado pelo Ansible (role gs_backup).
# Configuração em /etc/default/zomboid-backup (EnvironmentFile do systemd).
#
# Fluxo:
#   1. avisa os jogadores (servermsg) e espera ZB_WARN_SECONDS;
#   2. para o container (o entrypoint traduz SIGTERM em "quit", que salva);
#   3. gera tar.gz de ~/Zomboid (Saves, Server = configs, db) e testa o arquivo;
#   4. SÓ com backup íntegro, libera o update do servidor (flag lida pelo
#      entrypoint no próximo start) e sobe o container de novo;
#   5. retenção local de ZB_RETENTION_DAYS dias + rsync para ZB_BACKUP_TARGET.
# Se qualquer passo falhar com o container parado, o trap EXIT sobe o
# container de novo (sem liberar update).
set -Eeuo pipefail

: "${ZB_COMPOSE_DIR:?}" "${ZB_CONTAINER:?}" "${ZB_BACKUP_DIR:?}"
ZB_RETENTION_DAYS="${ZB_RETENTION_DAYS:-7}"
ZB_WARN_SECONDS="${ZB_WARN_SECONDS:-120}"
ZB_BACKUP_TARGET="${ZB_BACKUP_TARGET:-}"

DATA_DIR="${ZB_COMPOSE_DIR}/data/Zomboid"
UPDATE_FLAG="${ZB_COMPOSE_DIR}/state/update-requested"
COMPOSE=(docker compose -f "${ZB_COMPOSE_DIR}/compose.yaml")

log() { echo "[zomboid-backup] $*"; }

# Evita duas execuções simultâneas (timer + execução manual)
exec 9>/run/zomboid-backup.lock
flock -n 9 || { log "Outro backup já está em execução."; exit 1; }

# Envia um comando ao console do servidor (FIFO criado pelo entrypoint)
console() {
  docker exec -i "${ZB_CONTAINER}" sh -c 'cat > /tmp/pz-console' <<<"$1" \
    || log "AVISO: não foi possível enviar '$1' ao console."
}

stopped_by_us=false
on_exit() {
  local rc=$?
  if [[ "${stopped_by_us}" == true ]]; then
    log "Subindo o container novamente (após falha)."
    "${COMPOSE[@]}" start || rc=1
  fi
  exit "${rc}"
}
trap on_exit EXIT

running="$(docker inspect -f '{{.State.Running}}' "${ZB_CONTAINER}" 2>/dev/null || echo false)"

if [[ "${running}" == true ]]; then
  log "Avisando jogadores (${ZB_WARN_SECONDS}s)."
  console "servermsg \"Backup diario em ${ZB_WARN_SECONDS}s: o servidor vai reiniciar.\""
  sleep "${ZB_WARN_SECONDS}"
  console "servermsg \"Salvando e reiniciando para backup...\""
  sleep 5
  log "Parando o container (quit + save)."
  stopped_by_us=true
  "${COMPOSE[@]}" stop
else
  log "Container não está rodando - backup a frio, sem parar nada."
fi

install -d -m 0700 "${ZB_BACKUP_DIR}"
ts="$(date +%Y%m%d-%H%M%S)"
final="${ZB_BACKUP_DIR}/zomboid-${ts}.tar.gz"
partial="${final}.partial"

members=()
for d in Saves Server db; do
  [[ -e "${DATA_DIR}/${d}" ]] && members+=("${d}")
done

if (( ${#members[@]} == 0 )); then
  log "Nada para salvar ainda (sem Saves/Server/db) - sem dados em risco."
else
  log "Gerando ${final} (${members[*]})."
  tar -czf "${partial}" -C "${DATA_DIR}" "${members[@]}"
  tar -tzf "${partial}" >/dev/null   # testa a integridade do arquivo
  mv "${partial}" "${final}"
  chmod 0600 "${final}"
fi

# Backup íntegro: libera o update no próximo start. O diretório state/ é do
# usuário de serviço, então o container consegue apagar a flag depois.
touch "${UPDATE_FLAG}"
log "Update liberado para o próximo start."

if [[ "${stopped_by_us}" == true ]]; then
  log "Subindo o container (vai atualizar antes de iniciar)."
  "${COMPOSE[@]}" start
  stopped_by_us=false
fi

log "Retenção local: removendo backups com mais de ${ZB_RETENTION_DAYS} dias."
find "${ZB_BACKUP_DIR}" -maxdepth 1 -type f -name 'zomboid-*.tar.gz' \
  -mtime +"$(( ZB_RETENTION_DAYS - 1 ))" -print -delete
find "${ZB_BACKUP_DIR}" -maxdepth 1 -type f -name '*.partial' -print -delete

if [[ -n "${ZB_BACKUP_TARGET}" ]]; then
  # Sem --delete: apagar algo localmente nunca apaga a cópia remota.
  log "Enviando para ${ZB_BACKUP_TARGET}."
  rsync -a --chmod=F600 "${ZB_BACKUP_DIR}/" "${ZB_BACKUP_TARGET}"
else
  log "ZB_BACKUP_TARGET vazio - só backup local."
fi

log "Backup concluído."
