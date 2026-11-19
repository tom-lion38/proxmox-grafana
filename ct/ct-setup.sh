#!/usr/bin/env bash
#
# proxmox-grafana : installation dans le conteneur (InfluxDB 2 + Grafana).
# Lance par install.sh depuis l'hote Proxmox, pas a la main.
# Lit setup.env (a cote de ce script) et ecrit result.env.

set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 LANG=C.UTF-8

DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/setup.env"

: "${PG_LANG:=en}" "${PG_ORG:=proxmox}" "${PG_BUCKET:=proxmox}" "${PG_RETENTION:=2160h}"
: "${PG_GRAFANA_PASSWORD:?missing}"

INFLUX_FPR="24C975CBA61A024EE1B631787C3D57159FC2F927"
APT=(apt-get -y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
DASH_DIR="/var/lib/grafana/dashboards/proxmox-grafana"

L() { if [[ "$PG_LANG" == "fr" ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
step() { echo "==> $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }
randpw() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-"${1:-24}"; }

wait_http() { # url secondes
  local i
  for ((i = 0; i < ${2:-90}; i += 2)); do
    curl -fsS -o /dev/null --max-time 3 "$1" 2>/dev/null && return 0
    sleep 2
  done
  return 1
}

# --- Systeme --------------------------------------------------------------

step "$(L "Mise à jour du système du conteneur" "Updating the container system")"
apt-get update -q
"${APT[@]}" full-upgrade
"${APT[@]}" install curl ca-certificates gnupg jq

# --- Depots officiels -----------------------------------------------------

step "$(L "Ajout des dépôts officiels InfluxData et Grafana" "Adding the official InfluxData and Grafana repositories")"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL --retry 3 https://repos.influxdata.com/influxdata-archive.key -o /tmp/influxdata-archive.key
gpg --show-keys --with-fingerprint --with-colons /tmp/influxdata-archive.key 2>/dev/null |
  grep -q "^fpr:\+${INFLUX_FPR}:$" || fail "unexpected InfluxData signing key"
gpg --dearmor </tmp/influxdata-archive.key >/etc/apt/keyrings/influxdata-archive.gpg
rm -f /tmp/influxdata-archive.key
echo "deb [signed-by=/etc/apt/keyrings/influxdata-archive.gpg] https://repos.influxdata.com/debian stable main" \
  >/etc/apt/sources.list.d/influxdata.list
curl -fsSL --retry 3 https://apt.grafana.com/gpg.key | gpg --dearmor >/etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  >/etc/apt/sources.list.d/grafana.list
chmod 0644 /etc/apt/keyrings/*.gpg
apt-get update -q

# --- InfluxDB 2 -----------------------------------------------------------

step "$(L "Installation d'InfluxDB 2" "Installing InfluxDB 2")"
"${APT[@]}" install influxdb2 influxdb2-cli
# Le paquet influxdata-archive-keyring (installe avec InfluxDB) tient la cle a jour :
# on l'utilise pour que les futures rotations de cle se fassent toutes seules.
if [[ -f /usr/share/keyrings/influxdata-archive.gpg ]]; then
  sed -i 's#/etc/apt/keyrings/influxdata-archive.gpg#/usr/share/keyrings/influxdata-archive.gpg#' \
    /etc/apt/sources.list.d/influxdata.list
  rm -f /etc/apt/sources.list.d/influxdata.list.ucf-dist /etc/apt/keyrings/influxdata-archive.gpg
fi
if [[ -f /etc/influxdb/config.toml ]] && ! grep -q '^reporting-disabled' /etc/influxdb/config.toml; then
  echo 'reporting-disabled = true' >>/etc/influxdb/config.toml
fi
systemctl enable influxdb >/dev/null 2>&1 || true
systemctl restart influxdb
wait_http http://127.0.0.1:8086/health 120 || fail "InfluxDB does not answer"

step "$(L "Configuration d'InfluxDB (organisation, bucket, jetons)" "Configuring InfluxDB (organization, bucket, tokens)")"
INFLUX_PW=$(randpw 24)
ADMIN_TOKEN=$(randpw 64)
influx setup --host http://127.0.0.1:8086 --org "$PG_ORG" --bucket "$PG_BUCKET" \
  --username admin --password "$INFLUX_PW" --token "$ADMIN_TOKEN" \
  --retention "$PG_RETENTION" --force >/dev/null
export INFLUX_HOST=http://127.0.0.1:8086 INFLUX_TOKEN="$ADMIN_TOKEN" INFLUX_ORG="$PG_ORG"
BUCKET_ID=$(influx bucket list --name "$PG_BUCKET" --json | jq -r '.[0].id')
[[ -n "$BUCKET_ID" && "$BUCKET_ID" != "null" ]] || fail "bucket not found"
TOKEN_JQ='if type == "array" then .[0].token else .token end'
WRITE_TOKEN=$(influx auth create --write-bucket "$BUCKET_ID" \
  --description "proxmox-grafana: Proxmox VE and agent (write)" --json | jq -r "$TOKEN_JQ")
READ_TOKEN=$(influx auth create --read-bucket "$BUCKET_ID" \
  --description "proxmox-grafana: Grafana (read)" --json | jq -r "$TOKEN_JQ")
[[ -n "$WRITE_TOKEN" && "$WRITE_TOKEN" != "null" && -n "$READ_TOKEN" && "$READ_TOKEN" != "null" ]] ||
  fail "token creation failed"

# --- Grafana --------------------------------------------------------------

step "$(L "Installation de Grafana" "Installing Grafana")"
"${APT[@]}" install grafana

install -d -m 0755 /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
umask 027
cat >/etc/grafana/provisioning/datasources/proxmox-grafana.yaml <<EOF
apiVersion: 1
datasources:
  - name: InfluxDB Proxmox
    uid: proxmox-grafana-influxdb
    type: influxdb
    access: proxy
    url: http://127.0.0.1:8086
    isDefault: true
    editable: false
    jsonData:
      version: Flux
      organization: ${PG_ORG}
      defaultBucket: ${PG_BUCKET}
      timeInterval: 10s
    secureJsonData:
      token: ${READ_TOKEN}
EOF
cat >/etc/grafana/provisioning/dashboards/proxmox-grafana.yaml <<EOF
apiVersion: 1
providers:
  - name: proxmox-grafana
    orgId: 1
    folder: Proxmox
    folderUid: proxmox-grafana
    type: file
    disableDeletion: true
    allowUiUpdates: false
    updateIntervalSeconds: 30
    options:
      path: ${DASH_DIR}
EOF
umask 022
chown root:grafana /etc/grafana/provisioning/datasources/proxmox-grafana.yaml \
  /etc/grafana/provisioning/dashboards/proxmox-grafana.yaml
chmod 0640 /etc/grafana/provisioning/datasources/proxmox-grafana.yaml \
  /etc/grafana/provisioning/dashboards/proxmox-grafana.yaml

install -d -o grafana -g grafana -m 0755 "$DASH_DIR"
install -o grafana -g grafana -m 0644 "$DIR"/dashboards/*.json "$DASH_DIR/"

GF_LANG="en-US"
[[ "$PG_LANG" == "fr" ]] && GF_LANG="fr-FR"
install -d -m 0755 /etc/systemd/system/grafana-server.service.d
cat >/etc/systemd/system/grafana-server.service.d/proxmox-grafana.conf <<EOF
[Service]
Environment=GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH=${DASH_DIR}/01-overview.json
Environment=GF_USERS_DEFAULT_LANGUAGE=${GF_LANG}
Environment=GF_ANALYTICS_REPORTING_ENABLED=false
EOF
systemctl daemon-reload
systemctl enable grafana-server >/dev/null 2>&1 || true
systemctl restart grafana-server
wait_http http://127.0.0.1:3000/api/health 180 || fail "Grafana does not answer"

step "$(L "Mot de passe du compte admin de Grafana" "Grafana admin password")"
BODY=$(jq -n --arg p "$PG_GRAFANA_PASSWORD" '{oldPassword: "admin", newPassword: $p, confirmNew: $p}')
CODE=$(curl -s -o /dev/null -w '%{http_code}' -u admin:admin -H 'Content-Type: application/json' \
  -X PUT --data "$BODY" http://127.0.0.1:3000/api/user/password) || CODE=000
if [[ "$CODE" != "200" ]]; then
  grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
    admin reset-admin-password "$PG_GRAFANA_PASSWORD" >/dev/null 2>&1 ||
    grafana-cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
      admin reset-admin-password "$PG_GRAFANA_PASSWORD" >/dev/null 2>&1 ||
    fail "cannot set the Grafana admin password"
fi
curl -fsS -o /dev/null -u "admin:${PG_GRAFANA_PASSWORD}" http://127.0.0.1:3000/api/user ||
  fail "Grafana login check failed"

step "$(L "Attente du chargement des tableaux de bord" "Waiting for the dashboards to load")"
for ((i = 0; i < 30; i++)); do
  n=$(curl -fsS -u "admin:${PG_GRAFANA_PASSWORD}" "http://127.0.0.1:3000/api/search?tag=proxmox-grafana" 2>/dev/null |
    jq 'length' 2>/dev/null) || n=0
  ((n >= 4)) && break
  sleep 2
done

# --- Resultat ---------------------------------------------------------------

umask 077
cat >"$DIR/result.env" <<EOF
PG_WRITE_TOKEN=${WRITE_TOKEN}
PG_READ_TOKEN=${READ_TOKEN}
PG_INFLUX_PASSWORD=${INFLUX_PW}
PG_GRAFANA_VERSION=$(dpkg-query -W -f='${Version}' grafana 2>/dev/null || echo "?")
PG_INFLUX_VERSION=$(dpkg-query -W -f='${Version}' influxdb2 2>/dev/null || echo "?")
EOF
cat >/root/proxmox-grafana.txt <<EOF
proxmox-grafana

Grafana  : http://<IP>:3000  (admin)
InfluxDB : http://<IP>:8086
  admin / ${INFLUX_PW}
  organization ${PG_ORG}, bucket ${PG_BUCKET}
EOF
rm -f "$DIR/setup.env"
step "$(L "Conteneur prêt" "Container ready")"
