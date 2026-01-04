#!/usr/bin/env bash
set -euo pipefail

NS1_PUBLIC_IP="NS1_PUBLIC_IP"
APEX_PUBLIC_IP="APEX_PUBLIC_IP"
EL_PUBLIC_IP="EL_PUBLIC_IP"
API_PUBLIC_IP="API_PUBLIC_IP"

ZONE_NAME="nexusaievr.com.br"
ZONE_FILE="/etc/bind/db.nexusaievr.com.br"
LOCAL_CONF="/etc/bind/named.conf.local"
OPTIONS_CONF="/etc/bind/named.conf.options"
DEFAULT_TTL=3600

log() {
  echo "[bind9-setup] $*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "Execute como root (ou via sudo)."
    exit 1
  fi
}

backup_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local ts
    ts=$(date +"%Y%m%d%H%M%S")
    cp "$file" "${file}.bak.${ts}"
    log "Backup criado: ${file}.bak.${ts}"
  fi
}

install_packages() {
  log "Instalando pacotes..."
  apt-get update -y
  apt-get install -y bind9 bind9utils dnsutils
}

ensure_named_options() {
  backup_file "$OPTIONS_CONF"
  if [[ ! -f "$OPTIONS_CONF" ]]; then
    cat <<'CONF' > "$OPTIONS_CONF"
options {
  directory "/var/cache/bind";
  recursion no;
  allow-recursion { none; };
  allow-query { any; };
  allow-transfer { none; };
  dnssec-validation auto;
  listen-on { any; };
  listen-on-v6 { any; };
  version "not disclosed";
};
CONF
    return
  fi

  if ! grep -q "recursion no;" "$OPTIONS_CONF"; then
    sed -i "s/^options {/options {\n  recursion no;/" "$OPTIONS_CONF"
  fi
  if ! grep -q "allow-recursion" "$OPTIONS_CONF"; then
    sed -i "s/^options {/options {\n  allow-recursion { none; };/" "$OPTIONS_CONF"
  fi
  if ! grep -q "allow-query" "$OPTIONS_CONF"; then
    sed -i "s/^options {/options {\n  allow-query { any; };/" "$OPTIONS_CONF"
  fi
  if ! grep -q "allow-transfer" "$OPTIONS_CONF"; then
    sed -i "s/^options {/options {\n  allow-transfer { none; };/" "$OPTIONS_CONF"
  fi
  if ! grep -q "version \"not disclosed\";" "$OPTIONS_CONF"; then
    sed -i "s/^options {/options {\n  version \"not disclosed\";/" "$OPTIONS_CONF"
  fi
}

ensure_named_local() {
  backup_file "$LOCAL_CONF"
  if ! grep -q "zone \"${ZONE_NAME}\"" "$LOCAL_CONF" 2>/dev/null; then
    cat <<CONF >> "$LOCAL_CONF"
zone "${ZONE_NAME}" {
  type master;
  file "${ZONE_FILE}";
  allow-transfer { none; };
};
CONF
  fi
}

current_serial() {
  if [[ -f "$ZONE_FILE" ]]; then
    awk '/SOA/ {getline; print $1}' "$ZONE_FILE" | tr -d ';'
  else
    echo ""
  fi
}

next_serial() {
  local today serial
  today=$(date +"%Y%m%d")
  serial="${today}01"
  local existing
  existing=$(current_serial)
  if [[ -n "$existing" && "$existing" == ${today}* ]]; then
    local suffix=${existing:8:2}
    local inc=$((10#$suffix + 1))
    printf "%s%02d" "$today" "$inc"
  else
    echo "$serial"
  fi
}

render_zone() {
  local serial
  serial=$(next_serial)
  cat <<ZONE
$TTL ${DEFAULT_TTL}
@   IN  SOA ns1.${ZONE_NAME}. admin.${ZONE_NAME}. (
        ${serial} ; serial
        3600 ; refresh
        900 ; retry
        604800 ; expire
        3600 ; minimum
)

@   IN  NS  ns1.${ZONE_NAME}.

ns1 IN  A   ${NS1_PUBLIC_IP}
@   IN  A   ${APEX_PUBLIC_IP}
el  IN  A   ${EL_PUBLIC_IP}
api IN  A   ${API_PUBLIC_IP}
ZONE
}

write_zone_if_changed() {
  local tmp
  tmp=$(mktemp)
  render_zone > "$tmp"

  if [[ -f "$ZONE_FILE" ]] && cmp -s "$tmp" "$ZONE_FILE"; then
    log "Zona sem alterações."
    rm -f "$tmp"
    return
  fi

  backup_file "$ZONE_FILE"
  cp "$tmp" "$ZONE_FILE"
  rm -f "$tmp"
  log "Zona atualizada: ${ZONE_FILE}"
}

validate_and_restart() {
  log "Validando configuração..."
  named-checkconf
  named-checkzone "$ZONE_NAME" "$ZONE_FILE"

  log "Habilitando e reiniciando bind9..."
  systemctl enable --now bind9
  systemctl restart bind9
}

configure_ufw() {
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
      log "Liberando porta 53 TCP/UDP no UFW..."
      ufw allow 53/tcp
      ufw allow 53/udp
    fi
  fi
}

run_local_tests() {
  log "Testes de resolução local:"
  dig @127.0.0.1 "$ZONE_NAME" A +short
  dig @127.0.0.1 "el.${ZONE_NAME}" A +short
  dig @127.0.0.1 "api.${ZONE_NAME}" A +short
  dig @127.0.0.1 "$ZONE_NAME" NS +short
  dig @127.0.0.1 "$ZONE_NAME" SOA +short
}

main() {
  require_root
  install_packages
  ensure_named_options
  ensure_named_local
  write_zone_if_changed
  validate_and_restart
  configure_ufw
  run_local_tests

  cat <<'README'

README PÓS-IMPLANTAÇÃO

1) No Registro.br, configure “Servidores DNS” para:
   - ns1.nexusaievr.com.br

2) Configure o glue record do ns1 com o IP público do servidor:
   - NS1_PUBLIC_IP

3) Garanta que o servidor esteja acessível publicamente na porta 53 TCP/UDP.

4) Validação externa após delegação:
   dig nexusaievr.com.br NS
   dig @ns1.nexusaievr.com.br nexusaievr.com.br SOA
   dig @ns1.nexusaievr.com.br el.nexusaievr.com.br A
   dig @ns1.nexusaievr.com.br api.nexusaievr.com.br A

5) Site público: http://nexusaievr.com.br/
README
}

main "$@"
