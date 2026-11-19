#!/usr/bin/env bash
#
# proxmox-grafana
# Supervision complete de Proxmox VE (InfluxDB 2 + Grafana) en une commande.
# https://github.com/tom-lion38/proxmox-grafana (licence MIT)
#
# A lancer en root dans le shell d'un noeud Proxmox VE :
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/tom-lion38/proxmox-grafana/main/install.sh)"
#
# Le script cree un conteneur LXC Debian dedie (InfluxDB 2 + Grafana), branche
# l'envoi de metriques natif de Proxmox dessus, installe un petit agent sur le
# noeud (disques, temperatures, SMART, ZFS) et provisionne les tableaux de bord.
# Rien d'autre n'est modifie sur le serveur.

set -Eeuo pipefail
umask 022

readonly PG_VERSION="1.0.0"
PG_REPO="${PG_REPO:-tom-lion38/proxmox-grafana}"
PG_BRANCH="${PG_BRANCH:-main}"
readonly PG_ID="proxmox-grafana"
readonly PG_ORG="proxmox"
readonly PG_BUCKET="proxmox"
readonly PG_ETC="/etc/proxmox-grafana"
readonly PG_LOG="/var/log/proxmox-grafana.log"
readonly PG_INFO="/root/proxmox-grafana.txt"
readonly PG_AGENT_BIN="/usr/local/bin/proxmox-grafana-agent"
readonly PG_AGENT_UNIT="/etc/systemd/system/proxmox-grafana-agent.service"
readonly PG_CT_DIR="/opt/proxmox-grafana"

if [[ "$(locale charmap 2>/dev/null || true)" != "UTF-8" ]]; then
  export LC_ALL=C.UTF-8
fi

ACTION=""
UNATTENDED="${PG_UNATTENDED:-0}"
UI_LANG="${PG_LANG:-}"
SRC=""
SRC_TMP=""
CURRENT_STEP=""
CT_CREATED=0
METRIC_CREATED=0
HAS_WT=0
BACKTITLE="proxmox-grafana ${PG_VERSION}"

# Valeurs de l'installation (modifiables par variables d'environnement)
CTID="${PG_CTID:-}"
CT_HOSTNAME="${PG_HOSTNAME:-proxmox-grafana}"
STORAGE="${PG_STORAGE:-}"
TSTORE="${PG_TEMPLATE_STORAGE:-}"
CT_DISK="${PG_DISK:-20}"
CT_RAM="${PG_RAM:-2048}"
CT_CORES="${PG_CORES:-2}"
BRIDGE="${PG_BRIDGE:-}"
VLAN="${PG_VLAN:-}"
NET_MODE="dhcp"
CT_IP=""
CT_CIDR=""
CT_GW="${PG_GW:-}"
RETENTION="${PG_RETENTION:-90}"
GRAFANA_PW="${PG_GRAFANA_PASSWORD:-}"
AGENT="${PG_AGENT:-1}"
AGENT_ALL="${PG_AGENT_ALL_NODES:-1}"
TEMPLATE_VOLID=""
TEMPLATE_NAME=""
WRITE_TOKEN=""
READ_TOKEN=""
INFLUX_PW=""
AGENT_NODES=""

if [[ -n "${PG_IP:-}" && "${PG_IP}" != "dhcp" ]]; then
  NET_MODE="static"
  CT_CIDR="$PG_IP"
fi

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
  C_B=$'\e[1m'; C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_C=$'\e[36m'; C_0=$'\e[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_C=""; C_0=""
fi

# L "texte francais" "english text"
L() {
  if [[ "$UI_LANG" == "fr" ]]; then printf '%s' "$1"; else printf '%s' "$2"; fi
}

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$PG_LOG" 2>/dev/null || true; }
step() { CURRENT_STEP="$1"; printf '%s[..]%s %s\n' "$C_C" "$C_0" "$1"; log "STEP $1"; }
ok() { printf '%s[OK]%s %s\n' "$C_G" "$C_0" "$1"; log "OK $1"; }
warn() { printf '%s[!!]%s %s\n' "$C_Y" "$C_0" "$1" >&2; log "WARN $1"; }
info() { printf '     %s\n' "$1"; }

# Lance une commande, sortie dans le journal seulement
run() {
  log "RUN $*"
  "$@" >>"$PG_LOG" 2>&1
}

die() {
  printf '\n%s[%s]%s %s\n' "$C_R" "$(L "ERREUR" "ERROR")" "$C_0" "$1" >&2
  log "DIE $1"
  rollback_offer
  exit 1
}

usage() {
  cat <<'EOF'
proxmox-grafana: Proxmox VE monitoring (InfluxDB 2 + Grafana) in one command.

Usage: install.sh [action] [options]

Actions (an interactive menu is shown when none is given):
  --install             Install monitoring (dedicated LXC container)
  --update-dashboards   Update dashboards and the node agent
  --agent               Install the agent on this node (cluster)
  --uninstall           Remove everything that was installed

Options:
  --lang fr|en          Language of the questions
  --unattended, -y      No questions, use defaults and PG_* variables
  -h, --help            This help
  --version             Print the version

Variables for --unattended (all optional):
  PG_CTID PG_HOSTNAME PG_STORAGE PG_TEMPLATE_STORAGE PG_DISK (GB) PG_RAM (MB)
  PG_CORES PG_BRIDGE PG_VLAN PG_IP (dhcp or a.b.c.d/nn) PG_GW
  PG_RETENTION (days, 0 = forever) PG_GRAFANA_PASSWORD PG_AGENT (1/0)
  PG_AGENT_ALL_NODES (1/0) PG_DESTROY_CT (1/0, uninstall)
EOF
}

# ---------------------------------------------------------------------------
# Questions (whiptail si possible, sinon questions en texte)
# ---------------------------------------------------------------------------

init_ui() {
  if [[ "$UNATTENDED" != "1" ]]; then
    UNATTENDED=0
    if [[ ! -t 0 || ! -t 1 ]]; then
      if [[ -r /dev/tty ]]; then
        exec </dev/tty
      else
        echo "No terminal available: use --unattended" >&2
        exit 1
      fi
    fi
    if command -v whiptail >/dev/null 2>&1 && [[ -t 0 && -t 1 ]]; then HAS_WT=1; fi
  else
    UNATTENDED=1
  fi
  TERM_LINES=$(tput lines 2>/dev/null || echo 24)
  TERM_COLS=$(tput cols 2>/dev/null || echo 80)
  [[ "$TERM_LINES" =~ ^[0-9]+$ ]] || TERM_LINES=24
  [[ "$TERM_COLS" =~ ^[0-9]+$ ]] || TERM_COLS=80
}

ui_cancel() {
  printf '\n%s\n' "$(L "Annulé. Rien n'a été modifié par cette étape." "Cancelled. Nothing was changed by this step.")"
  rollback_offer
  exit 0
}

# Calcule hauteur et largeur d'une boite : texte [lignes en plus]
wt_dims() {
  local text="$1" extra="${2:-7}" w h n
  w=$((TERM_COLS - 4)); ((w > 78)) && w=78; ((w < 40)) && w=40
  n=$(printf '%s\n' "$text" | fold -s -w $((w - 4)) | wc -l)
  h=$((n + extra)); ((h > TERM_LINES - 2)) && h=$((TERM_LINES - 2)); ((h < 8)) && h=8
  echo "$h $w"
}

ui_msg() { # titre texte
  local title="$1" text="$2" h w
  ((UNATTENDED)) && return 0
  if ((HAS_WT)); then
    read -r h w <<<"$(wt_dims "$text" 8)"
    local scroll=()
    # Barre de defilement seulement si le texte ne tient pas (sinon Entree ne valide pas)
    (($(printf '%s\n' "$text" | fold -s -w $((w - 4)) | wc -l) + 8 > h)) && scroll=(--scrolltext)
    whiptail --backtitle "$BACKTITLE" --title " $title " --ok-button "OK" "${scroll[@]}" --msgbox "$text" "$h" "$w" || true
  else
    printf '\n%s== %s ==%s\n%s\n' "$C_B" "$title" "$C_0" "$text"
    read -r -p "$(L "Entrée pour continuer..." "Press Enter to continue...")" _ || true
  fi
}

ui_yesno() { # titre texte [yes|no] -> 0 = oui
  local title="$1" text="$2" def="${3:-yes}" h w rc=0 ans
  if ((UNATTENDED)); then [[ "$def" == "yes" ]]; return; fi
  if ((HAS_WT)); then
    read -r h w <<<"$(wt_dims "$text" 8)"
    local extra=()
    [[ "$def" == "no" ]] && extra=(--defaultno)
    whiptail --backtitle "$BACKTITLE" --title " $title " --yes-button "$(L "Oui" "Yes")" \
      --no-button "$(L "Non" "No")" "${extra[@]}" --yesno "$text" "$h" "$w" || rc=$?
    ((rc == 255)) && ui_cancel
    return "$rc"
  fi
  printf '\n%s== %s ==%s\n%s\n' "$C_B" "$title" "$C_0" "$text"
  local hint="[O/n]"; [[ "$def" == "no" ]] && hint="[o/N]"
  [[ "$UI_LANG" == "en" ]] && { hint="[Y/n]"; [[ "$def" == "no" ]] && hint="[y/N]"; }
  while :; do
    read -r -p "$hint " ans || ui_cancel
    ans="${ans,,}"
    [[ -z "$ans" ]] && { [[ "$def" == "yes" ]]; return; }
    case "$ans" in o|oui|y|yes) return 0 ;; n|non|no) return 1 ;; esac
  done
}

ui_input() { # variable titre texte defaut
  local __var="$1" title="$2" text="$3" def="${4-}" val h w
  if ((UNATTENDED)); then printf -v "$__var" '%s' "$def"; return; fi
  if ((HAS_WT)); then
    read -r h w <<<"$(wt_dims "$text" 9)"
    val=$(whiptail --backtitle "$BACKTITLE" --title " $title " --ok-button "$(L "Valider" "OK")" \
      --cancel-button "$(L "Annuler" "Cancel")" --inputbox "$text" "$h" "$w" "$def" 3>&1 1>&2 2>&3) || ui_cancel
  else
    printf '\n%s== %s ==%s\n%s\n' "$C_B" "$title" "$C_0" "$text"
    read -r -p "[${def}] > " val || ui_cancel
    val="${val:-$def}"
  fi
  printf -v "$__var" '%s' "$val"
}

ui_password() { # variable titre texte
  local __var="$1" title="$2" text="$3" val h w
  if ((HAS_WT)); then
    read -r h w <<<"$(wt_dims "$text" 9)"
    val=$(whiptail --backtitle "$BACKTITLE" --title " $title " --ok-button "$(L "Valider" "OK")" \
      --cancel-button "$(L "Annuler" "Cancel")" --passwordbox "$text" "$h" "$w" 3>&1 1>&2 2>&3) || ui_cancel
  else
    printf '\n%s== %s ==%s\n%s\n' "$C_B" "$title" "$C_0" "$text"
    read -r -s -p "> " val || ui_cancel
    echo
  fi
  printf -v "$__var" '%s' "$val"
}

ui_menu() { # variable titre texte defaut tag1 libelle1 tag2 libelle2 ...
  local __var="$1" title="$2" text="$3" def="$4"
  shift 4
  local -a items=("$@")
  local n=$((${#items[@]} / 2)) val h w lh i num=1 ans
  if ((UNATTENDED)); then printf -v "$__var" '%s' "$def"; return; fi
  if ((HAS_WT)); then
    read -r h w <<<"$(wt_dims "$text" $((n + 8)))"
    lh=$((h - 8)); ((lh > n)) && lh=$n; ((lh < 1)) && lh=1
    val=$(whiptail --backtitle "$BACKTITLE" --title " $title " --ok-button "$(L "Valider" "OK")" \
      --cancel-button "$(L "Annuler" "Cancel")" --default-item "$def" \
      --menu "$text" "$h" "$w" "$lh" "${items[@]}" 3>&1 1>&2 2>&3) || ui_cancel
  else
    printf '\n%s== %s ==%s\n%s\n' "$C_B" "$title" "$C_0" "$text"
    for ((i = 0; i < n; i++)); do
      printf '  %d) %s  %s\n' $((i + 1)) "${items[i * 2]}" "${items[i * 2 + 1]}"
      [[ "${items[i * 2]}" == "$def" ]] && num=$((i + 1))
    done
    while :; do
      read -r -p "$(L "Choix" "Choice") [$num] > " ans || ui_cancel
      ans="${ans:-$num}"
      if [[ "$ans" =~ ^[0-9]+$ ]] && ((ans >= 1 && ans <= n)); then
        val="${items[(ans - 1) * 2]}"
        break
      fi
    done
  fi
  printf -v "$__var" '%s' "$val"
}

# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

randpw() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-"${1:-20}"; }

is_int() { [[ "$1" =~ ^[0-9]+$ ]]; }

is_ip() {
  local ip="$1" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do ((10#$o <= 255)) || return 1; done
}

is_cidr() {
  [[ "$1" == */* ]] || return 1
  local ip="${1%/*}" m="${1#*/}"
  is_ip "$ip" && is_int "$m" && ((m >= 1 && m <= 32))
}

# Lit une cle dans un objet JSON : json_get "$json" cle
json_get() {
  perl -MJSON::PP -e 'my $d = eval { decode_json($ARGV[0]) } || {}; my $v = $d->{$ARGV[1]}; print defined $v ? $v : ""' "$1" "$2"
}

# Lit une valeur KEY=valeur dans un texte
env_get() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -n1; }

node_name() {
  perl -MPVE::INotify -e 'print PVE::INotify::nodename()' 2>/dev/null || hostname -s
}

# Noeuds du cluster : "nom ip en_ligne local"
cluster_nodes() {
  pvesh get /cluster/status --output-format json 2>/dev/null | perl -MJSON::PP -0777 -ne '
    my $d = eval { decode_json($_) } || [];
    for my $r (@$d) {
      next unless ($r->{type} // "") eq "node";
      printf "%s %s %d %d\n", $r->{name}, ($r->{ip} // "-"), ($r->{online} // 0), ($r->{local} // 0);
    }'
}

# Ponts reseau du noeud : "nom<TAB>cidr<TAB>passerelle<TAB>vlan_aware"
list_bridges() {
  local out
  out=$(pvesh get "/nodes/$NODE/network" --type any_bridge --output-format json 2>/dev/null | perl -MJSON::PP -0777 -ne '
    my $d = eval { decode_json($_) } || [];
    for my $r (sort { $a->{iface} cmp $b->{iface} } @$d) {
      printf "%s\t%s\t%s\t%d\n", $r->{iface}, ($r->{cidr} // "-"), ($r->{gateway} // "-"), ($r->{bridge_vlan_aware} ? 1 : 0);
    }') || true
  if [[ -z "$out" ]]; then
    out=$(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}' | sed 's/@.*//' |
      grep -Ev '^(fwbr|fwpr|fwln)' | awk '{printf "%s\t-\t-\t0\n", $1}') || true
  fi
  printf '%s\n' "$out" | sed '/^$/d'
}

# Stockages actifs pour un type de contenu : "nom type libre_Go"
list_storages() {
  pvesm status -content "$1" 2>/dev/null | awk 'NR > 1 && $3 == "active" { printf "%s %s %.0f\n", $1, $2, $6 / 1048576 }'
}

# CT de la supervision : "vmid noeud" (cherche par tag puis par fichier d'etat)
find_pg_ct() {
  local r=""
  r=$(pvesh get /cluster/resources --type vm --output-format json 2>/dev/null | perl -MJSON::PP -0777 -ne '
    my $d = eval { decode_json($_) } || [];
    for my $r (@$d) {
      next unless ($r->{type} // "") eq "lxc";
      my $t = $r->{tags} // "";
      if ($t =~ /(^|[;, ])proxmox-grafana($|[;, ])/) { print "$r->{vmid} $r->{node}\n"; last; }
    }') || true
  if [[ -z "$r" && -f "$PG_ETC/install.env" ]]; then
    local id
    id=$(sed -n 's/^PG_CTID=//p' "$PG_ETC/install.env" | head -n1)
    if [[ -n "$id" ]] && pct status "$id" >/dev/null 2>&1; then r="$id $NODE"; fi
  fi
  printf '%s' "$r"
}

metric_server_json() {
  pvesh get "/cluster/metrics/server/$PG_ID" --output-format json 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Recuperation des fichiers (clone local ou archive GitHub)
# ---------------------------------------------------------------------------

fetch_sources() {
  local here=""
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  fi
  if [[ -n "$here" && -f "$here/ct/ct-setup.sh" && -f "$here/agent/proxmox-grafana-agent" ]]; then
    SRC="$here"
    return 0
  fi
  step "$(L "Téléchargement des fichiers depuis GitHub" "Downloading files from GitHub")"
  SRC_TMP=$(mktemp -d /tmp/proxmox-grafana.XXXXXX)
  if ! curl -fsSL --retry 3 --connect-timeout 15 \
    "https://codeload.github.com/${PG_REPO}/tar.gz/refs/heads/${PG_BRANCH}" |
    tar -xz --no-same-owner -C "$SRC_TMP" --strip-components=1; then
    die "$(L "Impossible de télécharger ${PG_REPO} depuis GitHub. Vérifiez l'accès Internet du nœud." \
      "Cannot download ${PG_REPO} from GitHub. Check the node Internet access.")"
  fi
  [[ -f "$SRC_TMP/ct/ct-setup.sh" ]] || die "$(L "Archive incomplète." "Incomplete archive.")"
  SRC="$SRC_TMP"
  ok "$(L "Fichiers téléchargés" "Files downloaded")"
}

cleanup_tmp() {
  if [[ -n "$SRC_TMP" && -d "$SRC_TMP" ]]; then rm -rf "$SRC_TMP"; fi
}

# ---------------------------------------------------------------------------
# Erreurs et retour arriere
# ---------------------------------------------------------------------------

ROLLBACK_DONE=0
rollback_offer() {
  trap - ERR
  ((ROLLBACK_DONE)) && return 0
  ROLLBACK_DONE=1
  if ((METRIC_CREATED)); then
    pvesh delete "/cluster/metrics/server/$PG_ID" >>"$PG_LOG" 2>&1 || true
    METRIC_CREATED=0
    info "$(L "Envoi des métriques retiré." "Metric server entry removed.")"
  fi
  if ((CT_CREATED)); then
    local keep=0
    if [[ "${PG_KEEP_ON_ERROR:-0}" == "1" ]]; then keep=1; fi
    if ((!keep)) && ! ui_yesno "$(L "Nettoyage" "Cleanup")" \
      "$(L "Supprimer le conteneur ${CTID} créé pendant cette installation ?

C'est conseillé avant de relancer le script." \
        "Delete container ${CTID} created during this installation?

Recommended before running the script again.")" yes; then
      keep=1
    fi
    if ((keep)); then
      info "$(L "Conteneur ${CTID} conservé pour analyse." "Container ${CTID} kept for troubleshooting.")"
    else
      pct stop "$CTID" >>"$PG_LOG" 2>&1 || true
      pct destroy "$CTID" --purge 1 >>"$PG_LOG" 2>&1 || pct destroy "$CTID" >>"$PG_LOG" 2>&1 || true
      info "$(L "Conteneur ${CTID} supprimé." "Container ${CTID} deleted.")"
    fi
    CT_CREATED=0
  fi
}

on_error() {
  local rc="$1" line="$2"
  # Dans un sous-shell, on laisse le shell principal decider
  if ((BASH_SUBSHELL > 0)); then exit "$rc"; fi
  trap - ERR
  log "ERR rc=$rc line=$line step=$CURRENT_STEP"
  printf '\n%s[%s]%s %s: %s (code %s, %s %s)\n' "$C_R" "$(L "ERREUR" "ERROR")" "$C_0" \
    "$(L "Échec pendant" "Failed during")" "${CURRENT_STEP:-?}" "$rc" "$(L "ligne" "line")" "$line" >&2
  printf '%s %s\n' "$(L "Dernières lignes du journal" "Last lines of the log")" "$PG_LOG" >&2
  tail -n 15 "$PG_LOG" 2>/dev/null | sed 's/^/   /' >&2 || true
  rollback_offer
  exit "$rc"
}

on_interrupt() {
  trap - INT TERM HUP
  printf '\n%s\n' "$(L "Interrompu." "Interrupted.")" >&2
  rollback_offer
  exit 130
}

# Connexion perdue (fenetre SSH fermee) : plus personne pour repondre,
# on retire ce qui a ete cree pour pouvoir relancer proprement.
on_hangup() {
  trap - INT TERM HUP
  exec </dev/null >>"$PG_LOG" 2>&1
  log "HUP: connection lost, cleaning up"
  UNATTENDED=1
  HAS_WT=0
  PG_KEEP_ON_ERROR=0
  rollback_offer
  exit 129
}

trap 'on_error $? $LINENO' ERR
trap on_interrupt INT TERM
trap on_hangup HUP
trap cleanup_tmp EXIT

# ---------------------------------------------------------------------------
# Demarrage
# ---------------------------------------------------------------------------

parse_args() {
  while (($#)); do
    case "$1" in
      --install) ACTION="install" ;;
      --update-dashboards | --update) ACTION="dashboards" ;;
      --agent) ACTION="agent" ;;
      --uninstall) ACTION="uninstall" ;;
      --unattended | -y | --yes) UNATTENDED=1 ;;
      --lang) UI_LANG="${2:-}"; shift ;;
      --lang=*) UI_LANG="${1#*=}" ;;
      -h | --help) usage; exit 0 ;;
      --version) echo "$PG_VERSION"; exit 0 ;;
      *) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
  done
}

choose_language() {
  local def="en"
  case "${LANG:-}${LC_ALL:-}${LC_MESSAGES:-}" in *fr*) def="fr" ;; esac
  if [[ -z "$UI_LANG" ]]; then
    UI_LANG="$def"
    ((UNATTENDED)) || ui_menu UI_LANG "Langue / Language" "Choisissez la langue / Choose your language" "$def" \
      fr "Français" en "English"
  fi
  [[ "$UI_LANG" == "fr" || "$UI_LANG" == "en" ]] || UI_LANG="en"
}

main_menu() {
  local def="install" state=""
  local ct j
  ct=$(find_pg_ct)
  j=$(metric_server_json)
  if [[ -n "$ct" || -n "$j" ]]; then
    def="dashboards"
    state="

$(L "Une installation existe déjà" "An installation already exists")${ct:+ (CT ${ct%% *})}."
  fi
  ui_menu ACTION "proxmox-grafana ${PG_VERSION}" \
    "$(L "Supervision de Proxmox VE avec Grafana et InfluxDB.

Que voulez-vous faire ?" "Proxmox VE monitoring with Grafana and InfluxDB.

What do you want to do?")${state}" "$def" \
    install "$(L "Installer la supervision" "Install monitoring")" \
    dashboards "$(L "Mettre à jour les tableaux de bord et l'agent" "Update dashboards and agent")" \
    agent "$(L "Ajouter l'agent sur ce nœud (cluster)" "Add the agent on this node (cluster)")" \
    uninstall "$(L "Tout désinstaller" "Uninstall everything")"
}

preflight() {
  [[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 1; }
  if ! command -v pveversion >/dev/null 2>&1 || ! command -v pct >/dev/null 2>&1; then
    echo "This script must run on a Proxmox VE node (pveversion and pct not found)." >&2
    exit 1
  fi
  touch "$PG_LOG" && chmod 600 "$PG_LOG"
  log "===== proxmox-grafana $PG_VERSION ($*) ====="
  PVE_VER=$(pveversion | sed -n 's#^pve-manager/\([0-9][0-9.]*\)/.*#\1#p')
  PVE_MAJOR="${PVE_VER%%.*}"
  is_int "${PVE_MAJOR:-x}" || PVE_MAJOR=0
  NODE=$(node_name)
}

main() {
  parse_args "$@"
  preflight "$@"
  init_ui
  choose_language
  if ((PVE_MAJOR < 7)); then
    echo "$(L "Proxmox VE 7 ou plus récent est nécessaire (version trouvée : ${PVE_VER:-?})." \
      "Proxmox VE 7 or newer is required (found: ${PVE_VER:-?}).")" >&2
    exit 1
  fi
  if [[ -z "$ACTION" ]]; then
    if ((UNATTENDED)); then ACTION="install"; else main_menu; fi
  fi
  case "$ACTION" in
    install) do_install ;;
    dashboards) do_update ;;
    agent) do_agent_only ;;
    uninstall) do_uninstall ;;
  esac
}

# ---------------------------------------------------------------------------
# Installation : questions
# ---------------------------------------------------------------------------

ask_settings() {
  local mode="simple" line name type avail def_storage="" best=-1 n
  local -a items

  ui_msg "proxmox-grafana" "$(L "Ce script va :

 - créer un conteneur Debian dédié avec InfluxDB 2 et Grafana ;
 - demander à Proxmox d'y envoyer ses métriques (nœuds, VM,
   conteneurs, stockages) ;
 - installer un petit agent sur le nœud pour les disques,
   températures, SMART et ZFS ;
 - ajouter des tableaux de bord prêts à l'emploi.

Rien d'autre n'est modifié. Les envois de métriques déjà configurés
sur ce Proxmox ne sont pas touchés." "This script will:

 - create a dedicated Debian container with InfluxDB 2 and Grafana;
 - ask Proxmox to send its metrics there (nodes, VMs, containers,
   storages);
 - install a small agent on the node for disks, temperatures,
   SMART and ZFS;
 - add ready-to-use dashboards.

Nothing else is changed. Metric servers already configured on this
Proxmox are left untouched.")"

  ui_menu mode "$(L "Mode" "Mode")" "$(L "Le mode simple utilise des réglages recommandés et ne pose que l'essentiel." \
    "Simple mode uses recommended settings and only asks the essentials.")" simple \
    simple "$(L "Simple (recommandé)" "Simple (recommended)")" \
    advanced "$(L "Avancé (je règle tout)" "Advanced (I choose everything)")"

  # Numero du conteneur
  [[ -n "$CTID" ]] || CTID=$(pvesh get /cluster/nextid 2>/dev/null || echo 100)
  if [[ "$mode" == "advanced" ]]; then
    while :; do
      ui_input CTID "$(L "Numéro du conteneur" "Container ID")" \
        "$(L "Numéro (VMID) du nouveau conteneur :" "ID (VMID) of the new container:")" "$CTID"
      if is_int "$CTID" && pvesh get /cluster/nextid --vmid "$CTID" >/dev/null 2>&1; then break; fi
      ui_msg "$(L "Numéro du conteneur" "Container ID")" "$(L "Le numéro ${CTID} est invalide ou déjà utilisé." "ID ${CTID} is invalid or already used.")"
      CTID=$(pvesh get /cluster/nextid 2>/dev/null || echo 100)
    done
    while :; do
      ui_input CT_HOSTNAME "$(L "Nom du conteneur" "Container name")" \
        "$(L "Nom d'hôte du conteneur :" "Container hostname:")" "$CT_HOSTNAME"
      [[ "$CT_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] && break
      ui_msg "$(L "Nom du conteneur" "Container name")" "$(L "Lettres, chiffres et tirets seulement." "Letters, digits and hyphens only.")"
    done
  fi
  if ! is_int "$CTID" || ! pvesh get /cluster/nextid --vmid "$CTID" >/dev/null 2>&1; then
    die "$(L "Le numéro de conteneur ${CTID} est déjà utilisé." "Container ID ${CTID} is already used.")"
  fi

  # Stockage du conteneur : local-lvm ou local-zfs par defaut, sinon le plus libre
  items=()
  local preferred="" biggest=""
  while read -r name type avail; do
    [[ -n "$name" ]] || continue
    items+=("$name" "$(printf '%-9s %s %s' "$type" "$avail" "$(L "Go libres" "GB free")")")
    if [[ -z "$preferred" && ("$name" == "local-lvm" || "$name" == "local-zfs") ]]; then preferred="$name"; fi
    if ((avail > best)); then best=$avail; biggest="$name"; fi
  done < <(list_storages rootdir)
  ((${#items[@]})) || die "$(L "Aucun stockage actif n'accepte les conteneurs sur ce nœud." "No active storage accepts containers on this node.")"
  def_storage="${preferred:-$biggest}"
  [[ -n "$STORAGE" ]] || STORAGE="$def_storage"
  if ((${#items[@]} > 2)); then
    ui_menu STORAGE "$(L "Stockage" "Storage")" "$(L "Où placer le disque du conteneur ?" "Where should the container disk go?")" "$STORAGE" "${items[@]}"
  fi

  if [[ "$mode" == "advanced" ]]; then
    while :; do
      ui_input CT_CORES "$(L "Processeur" "CPU")" "$(L "Nombre de cœurs :" "Number of cores:")" "$CT_CORES"
      is_int "$CT_CORES" && ((CT_CORES >= 1)) && break
    done
    while :; do
      ui_input CT_RAM "$(L "Mémoire" "Memory")" "$(L "Mémoire en Mo (2048 conseillé, 1024 minimum) :" "Memory in MB (2048 recommended, 1024 minimum):")" "$CT_RAM"
      is_int "$CT_RAM" && ((CT_RAM >= 1024)) && break
    done
    while :; do
      ui_input CT_DISK "$(L "Disque" "Disk")" "$(L "Taille du disque en Go (8 minimum). Compter environ 1 Go par mois pour 30 VM ou conteneurs :" \
        "Disk size in GB (8 minimum). Count about 1 GB per month for 30 VMs or containers:")" "$CT_DISK"
      is_int "$CT_DISK" && ((CT_DISK >= 8)) && break
    done
    ui_menu RETENTION "$(L "Historique" "History")" "$(L "Combien de temps garder les mesures ?" "How long should measurements be kept?")" "$RETENTION" \
      30 "$(L "30 jours" "30 days")" 90 "$(L "90 jours (recommandé)" "90 days (recommended)")" \
      180 "$(L "180 jours" "180 days")" 365 "$(L "1 an" "1 year")" 0 "$(L "Pour toujours" "Forever")"
  fi

  # Reseau
  local -a bitems=() blines=()
  local bname bcidr bgw bvlan def_bridge=""
  while IFS=$'\t' read -r bname bcidr bgw bvlan; do
    [[ -n "$bname" ]] || continue
    blines+=("$bname"$'\t'"$bcidr"$'\t'"$bgw")
    local desc="$bcidr"
    [[ "$desc" == "-" ]] && desc="$(L "sans adresse" "no address")"
    ((bvlan)) && desc="$desc, VLAN aware"
    bitems+=("$bname" "$desc")
    if [[ -z "$def_bridge" || "$bname" == "vmbr0" ]]; then def_bridge="$bname"; fi
  done < <(list_bridges)
  ((${#bitems[@]})) || die "$(L "Aucun pont réseau (vmbrX) trouvé sur ce nœud." "No network bridge (vmbrX) found on this node.")"
  [[ -n "$BRIDGE" ]] || BRIDGE="$def_bridge"
  if ((${#bitems[@]} > 2)); then
    ui_menu BRIDGE "$(L "Réseau" "Network")" "$(L "Sur quel pont réseau brancher le conteneur ?" "Which network bridge should the container use?")" "$BRIDGE" "${bitems[@]}"
  fi
  local host_cidr="-" host_gw="-" l
  for l in "${blines[@]}"; do
    if [[ "${l%%$'\t'*}" == "$BRIDGE" ]]; then
      host_cidr=$(cut -f2 <<<"$l"); host_gw=$(cut -f3 <<<"$l")
    fi
  done
  if [[ "$host_gw" == "-" ]]; then
    host_gw=$(ip -4 route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit }}') || true
    [[ -n "$host_gw" ]] || host_gw="-"
  fi

  if [[ "$mode" == "advanced" ]]; then
    while :; do
      ui_input VLAN "VLAN" "$(L "Numéro de VLAN (laisser vide si aucun) :" "VLAN tag (leave empty for none):")" "$VLAN"
      [[ -z "$VLAN" ]] && break
      is_int "$VLAN" && ((VLAN >= 1 && VLAN <= 4094)) && break
    done
  fi

  ui_menu NET_MODE "$(L "Adresse IP" "IP address")" "$(L "Comment le conteneur obtient son adresse IP ?

Avec le DHCP, pensez à réserver l'adresse dans votre box ou votre routeur : si elle change, Proxmox ne pourra plus envoyer ses mesures." \
    "How does the container get its IP address?

With DHCP, reserve the address in your router: if it changes, Proxmox can no longer send its metrics.")" "$NET_MODE" \
    dhcp "$(L "Automatique (DHCP)" "Automatic (DHCP)")" \
    static "$(L "Adresse fixe" "Static address")"

  if [[ "$NET_MODE" == "static" ]]; then
    local hint=""
    [[ "$host_cidr" != "-" ]] && hint="$(L "Le nœud est en ${host_cidr} sur ${BRIDGE}." "The node is ${host_cidr} on ${BRIDGE}.")

"
    while :; do
      ui_input CT_CIDR "$(L "Adresse IP" "IP address")" "${hint}$(L "Adresse IP du conteneur avec son masque, par exemple 192.168.0.240/24 :" \
        "Container IP address with its prefix, for example 192.168.0.240/24:")" "$CT_CIDR"
      if ! is_cidr "$CT_CIDR"; then
        ((UNATTENDED)) && die "PG_IP: $(L "format attendu a.b.c.d/nn" "expected format a.b.c.d/nn")"
        ui_msg "$(L "Adresse IP" "IP address")" "$(L "Format attendu : a.b.c.d/nn" "Expected format: a.b.c.d/nn")"
        continue
      fi
      if ping -c 1 -W 1 "${CT_CIDR%/*}" >/dev/null 2>&1; then
        ((UNATTENDED)) && die "PG_IP: $(L "l'adresse ${CT_CIDR%/*} répond déjà sur le réseau" "address ${CT_CIDR%/*} already answers on the network")"
        ui_yesno "$(L "Adresse IP" "IP address")" "$(L "L'adresse ${CT_CIDR%/*} répond déjà sur le réseau. Elle est sans doute utilisée.

En choisir une autre ?" "Address ${CT_CIDR%/*} already answers on the network. It is probably in use.

Choose another one?")" yes && continue
      fi
      break
    done
    [[ -n "$CT_GW" ]] || { [[ "$host_gw" != "-" ]] && CT_GW="$host_gw"; }
    while :; do
      ui_input CT_GW "$(L "Passerelle" "Gateway")" "$(L "Passerelle (routeur) du réseau :" "Network gateway (router):")" "$CT_GW"
      is_ip "$CT_GW" && break
      ((UNATTENDED)) && die "PG_GW: $(L "passerelle invalide ou absente" "invalid or missing gateway")"
    done
  fi

  # Mot de passe Grafana
  if [[ -z "$GRAFANA_PW" ]]; then
    local pwmode="auto"
    ui_menu pwmode "Grafana" "$(L "Mot de passe du compte admin de Grafana :" "Password for the Grafana admin account:")" auto \
      auto "$(L "En générer un solide (affiché à la fin)" "Generate a strong one (shown at the end)")" \
      manual "$(L "Je choisis mon mot de passe" "I choose my password")"
    if [[ "$pwmode" == "manual" ]]; then
      local p1 p2
      while :; do
        ui_password p1 "Grafana" "$(L "Mot de passe (8 caractères minimum) :" "Password (8 characters minimum):")"
        ui_password p2 "Grafana" "$(L "Encore une fois :" "Once again:")"
        if [[ "$p1" != "$p2" ]]; then ui_msg "Grafana" "$(L "Les deux mots de passe sont différents." "The two passwords differ.")"; continue; fi
        if ((${#p1} < 8)); then ui_msg "Grafana" "$(L "Trop court." "Too short.")"; continue; fi
        GRAFANA_PW="$p1"
        break
      done
    else
      GRAFANA_PW=$(randpw 20)
    fi
  fi

  # Agent
  if ui_yesno "$(L "Agent du nœud" "Node agent")" "$(L "Proxmox envoie déjà lui-même la charge et l'état du nœud, des VM, des conteneurs et des stockages.

L'agent ajoute ce que Proxmox ne mesure pas : activité de chaque disque physique, températures, ventilateurs, santé SMART et pools ZFS.

C'est un petit script lancé par systemd, sans paquet à installer.
L'installer sur ce nœud ?" "Proxmox already sends the load and state of the node, VMs, containers and storages by itself.

The agent adds what Proxmox does not measure: activity of each physical disk, temperatures, fans, SMART health and ZFS pools.

It is a small script run by systemd, no package to install.
Install it on this node?")" "$([[ "$AGENT" == "1" ]] && echo yes || echo no)"; then
    AGENT=1
  else
    AGENT=0
  fi

  OTHER_NODES=()
  local nname nip nonline nlocal
  while read -r nname nip nonline nlocal; do
    [[ -n "$nname" ]] || continue
    ((nlocal)) && continue
    ((nonline)) || continue
    OTHER_NODES+=("$nname:$nip")
  done < <(cluster_nodes)
  if ((AGENT)) && ((${#OTHER_NODES[@]})); then
    if ui_yesno "$(L "Cluster" "Cluster")" "$(L "Ce nœud fait partie d'un cluster (${#OTHER_NODES[@]} autre(s) nœud(s) en ligne).

Installer aussi l'agent sur les autres nœuds, par SSH entre nœuds ?" \
      "This node is part of a cluster (${#OTHER_NODES[@]} other node(s) online).

Also install the agent on the other nodes, using SSH between nodes?")" "$([[ "$AGENT_ALL" == "1" ]] && echo yes || echo no)"; then
      AGENT_ALL=1
    else
      AGENT_ALL=0
    fi
  else
    AGENT_ALL=0
  fi
  n=0
  ((AGENT)) && n=1
  ((AGENT_ALL)) && n=$((n + ${#OTHER_NODES[@]}))
  AGENT_COUNT=$n
}

confirm_settings() {
  local net ret agent
  if [[ "$NET_MODE" == "static" ]]; then net="$BRIDGE, ${CT_CIDR}, $(L "passerelle" "gateway") ${CT_GW}"; else net="$BRIDGE, DHCP"; fi
  [[ -n "$VLAN" ]] && net="$net, VLAN $VLAN"
  if [[ "$RETENTION" == "0" ]]; then ret="$(L "pour toujours" "forever")"; else ret="$RETENTION $(L "jours" "days")"; fi
  if ((AGENT_COUNT == 0)); then agent="$(L "non" "no")"; else agent="$AGENT_COUNT $(L "nœud(s)" "node(s)")"; fi
  local text
  text="$(L "Conteneur" "Container")   : ${CTID} (${CT_HOSTNAME})
$(L "Stockage" "Storage")    : ${STORAGE}, ${CT_DISK} $(L "Go" "GB")
$(L "Ressources" "Resources")  : ${CT_CORES} vCPU, ${CT_RAM} $(L "Mo" "MB")
$(L "Réseau" "Network")      : ${net}
$(L "Historique" "History")  : ${ret}
Agent       : ${agent}

$(L "Sur Proxmox, seuls changent : le nouveau conteneur, un envoi de métriques nommé « proxmox-grafana » et l'agent.

Lancer l'installation ?" "On Proxmox, only these change: the new container, a metric server named \"proxmox-grafana\" and the agent.

Start the installation?")"
  ui_yesno "$(L "Récapitulatif" "Summary")" "$text" yes || ui_cancel
}

# ---------------------------------------------------------------------------
# Installation : actions
# ---------------------------------------------------------------------------

ensure_template() {
  local -a items=() wants
  local name type avail t file

  if [[ -z "$TSTORE" ]]; then
    while read -r name type avail; do
      [[ -n "$name" ]] || continue
      [[ -z "$TSTORE" || "$name" == "local" ]] && TSTORE="$name"
    done < <(list_storages vztmpl)
  fi
  [[ -n "$TSTORE" ]] || die "$(L "Aucun stockage n'accepte les modèles de conteneurs (contenu « vztmpl »)." \
    "No storage accepts container templates (\"vztmpl\" content).")"

  if ((PVE_MAJOR >= 9)); then wants=(debian-13 debian-12); elif ((PVE_MAJOR == 8)); then wants=(debian-12); else wants=(debian-12 debian-11); fi

  local existing
  existing=$(pveam list "$TSTORE" 2>/dev/null | awk 'NR > 1 {print $1}' | sed 's#.*/##') || true
  for t in "${wants[@]}"; do
    file=$(printf '%s\n' "$existing" | grep -E "^${t}-standard_.*_amd64\.tar\.(zst|gz|xz)$" | sort -V | tail -n1) || true
    if [[ -n "$file" ]]; then
      TEMPLATE_VOLID="$TSTORE:vztmpl/$file"
      TEMPLATE_NAME="$file"
      ok "$(L "Modèle déjà présent" "Template already present"): $file"
      return 0
    fi
  done

  step "$(L "Téléchargement du modèle Debian" "Downloading the Debian template")"
  run pveam update || warn "$(L "pveam update a échoué, on continue avec la liste connue." "pveam update failed, using the known list.")"
  local available
  available=$(pveam available --section system 2>/dev/null | awk '{print $2}') || true
  for t in "${wants[@]}"; do
    file=$(printf '%s\n' "$available" | grep -E "^${t}-standard_.*_amd64\.tar\.(zst|gz|xz)$" | sort -V | tail -n1) || true
    if [[ -n "$file" ]]; then
      run pveam download "$TSTORE" "$file" || die "$(L "Échec du téléchargement de $file" "Failed to download $file")"
      TEMPLATE_VOLID="$TSTORE:vztmpl/$file"
      TEMPLATE_NAME="$file"
      ok "$(L "Modèle téléchargé" "Template downloaded"): $file"
      return 0
    fi
  done
  die "$(L "Aucun modèle Debian disponible (pveam available)." "No Debian template available (pveam available).")"
}

create_ct() {
  local net="name=eth0,bridge=${BRIDGE}"
  [[ -n "$VLAN" ]] && net="${net},tag=${VLAN}"
  if [[ "$NET_MODE" == "static" ]]; then net="${net},ip=${CT_CIDR},gw=${CT_GW}"; else net="${net},ip=dhcp"; fi
  local desc="proxmox-grafana: InfluxDB 2 + Grafana. https://github.com/${PG_REPO}"
  local -a args=(pct create "$CTID" "$TEMPLATE_VOLID"
    --hostname "$CT_HOSTNAME" --cores "$CT_CORES" --memory "$CT_RAM" --swap 512
    --rootfs "${STORAGE}:${CT_DISK}" --net0 "$net"
    --unprivileged 1 --features nesting=1 --onboot 1 --ostype debian
    --description "$desc")
  ((PVE_MAJOR >= 8)) && args+=(--tags "$PG_ID")
  step "$(L "Création du conteneur" "Creating the container") ${CTID}"
  run "${args[@]}" || die "$(L "La création du conteneur a échoué (détails dans ${PG_LOG})." "Container creation failed (details in ${PG_LOG}).")"
  CT_CREATED=1
  ok "$(L "Conteneur créé" "Container created"): ${CTID}"
  step "$(L "Démarrage du conteneur" "Starting the container")"
  run pct start "$CTID"
  local i ip=""
  for ((i = 0; i < 90; i++)); do
    ip=$(pct exec "$CTID" -- ip -4 -o addr show dev eth0 scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1) || true
    if [[ -n "$ip" ]] && pct exec "$CTID" -- getent hosts deb.debian.org >/dev/null 2>&1; then
      CT_IP="$ip"
      break
    fi
    sleep 2
  done
  if [[ -z "$CT_IP" ]]; then
    if [[ -z "$ip" ]]; then
      die "$(L "Le conteneur n'a pas obtenu d'adresse IP. Sans serveur DHCP sur ce réseau, relancez avec une adresse fixe." \
        "The container got no IP address. Without a DHCP server on this network, run again with a static address.")"
    fi
    die "$(L "Le conteneur (${ip}) n'arrive pas à joindre Internet (DNS ou passerelle)." "The container (${ip}) cannot reach the Internet (DNS or gateway).")"
  fi
  ok "$(L "Conteneur démarré, adresse" "Container started, address") ${CT_IP}"
}

setup_ct() {
  local pkg retention_h
  if [[ "$RETENTION" == "0" ]]; then retention_h="0"; else retention_h="$((RETENTION * 24))h"; fi
  pkg=$(mktemp -d /tmp/proxmox-grafana-pkg.XXXXXX)
  mkdir -p "$pkg/proxmox-grafana/dashboards"
  cp "$SRC/ct/ct-setup.sh" "$pkg/proxmox-grafana/"
  cp "$SRC/dashboards/$UI_LANG/"*.json "$pkg/proxmox-grafana/dashboards/"
  (
    umask 077
    {
      printf 'PG_LANG=%q\n' "$UI_LANG"
      printf 'PG_ORG=%q\n' "$PG_ORG"
      printf 'PG_BUCKET=%q\n' "$PG_BUCKET"
      printf 'PG_RETENTION=%q\n' "$retention_h"
      printf 'PG_GRAFANA_PASSWORD=%q\n' "$GRAFANA_PW"
    } >"$pkg/proxmox-grafana/setup.env"
  )
  tar --owner=0 --group=0 -C "$pkg" -czf "$pkg/pg.tgz" proxmox-grafana
  run pct push "$CTID" "$pkg/pg.tgz" /root/proxmox-grafana.tgz
  rm -rf "$pkg"
  run pct exec "$CTID" -- bash -c "mkdir -p /opt && tar --no-same-owner -C /opt -xzf /root/proxmox-grafana.tgz && rm -f /root/proxmox-grafana.tgz && chmod 700 $PG_CT_DIR"

  step "$(L "Installation d'InfluxDB et Grafana dans le conteneur (2 à 5 minutes)" "Installing InfluxDB and Grafana in the container (2 to 5 minutes)")"
  log "RUN pct exec $CTID -- bash $PG_CT_DIR/ct-setup.sh"
  if ! pct exec "$CTID" -- env LC_ALL=C.UTF-8 bash "$PG_CT_DIR/ct-setup.sh" </dev/null 2>&1 | tee -a "$PG_LOG" |
    { grep --line-buffered '^==> ' || true; } | sed -u 's/^==> /     /'; then
    die "$(L "L'installation dans le conteneur a échoué (détails dans ${PG_LOG})." "Installation inside the container failed (details in ${PG_LOG}).")"
  fi
  local res
  res=$(pct exec "$CTID" -- cat "$PG_CT_DIR/result.env" 2>/dev/null) || die "$(L "Résultat de l'installation introuvable." "Installation result not found.")"
  WRITE_TOKEN=$(env_get "$res" PG_WRITE_TOKEN)
  READ_TOKEN=$(env_get "$res" PG_READ_TOKEN)
  INFLUX_PW=$(env_get "$res" PG_INFLUX_PASSWORD)
  GRAFANA_VER=$(env_get "$res" PG_GRAFANA_VERSION)
  INFLUX_VER=$(env_get "$res" PG_INFLUX_VERSION)
  pct exec "$CTID" -- rm -f "$PG_CT_DIR/result.env" >>"$PG_LOG" 2>&1 || true
  [[ -n "$WRITE_TOKEN" && -n "$READ_TOKEN" ]] || die "$(L "Jetons InfluxDB manquants." "Missing InfluxDB tokens.")"
  ok "$(L "InfluxDB et Grafana installés" "InfluxDB and Grafana installed") (Grafana ${GRAFANA_VER:-?}, InfluxDB ${INFLUX_VER:-?})"
}

configure_metric_server() { # ip
  local ip="$1"
  local -a args=(--server "$ip" --port 8086 --influxdbproto http --organization "$PG_ORG" --bucket "$PG_BUCKET" --token "$WRITE_TOKEN")
  step "$(L "Branchement de l'envoi des métriques de Proxmox" "Connecting the Proxmox metric server")"
  if [[ -n "$(metric_server_json)" ]]; then
    log "RUN pvesh set /cluster/metrics/server/$PG_ID (server $ip)"
    pvesh set "/cluster/metrics/server/$PG_ID" "${args[@]}" --disable 0 >>"$PG_LOG" 2>&1 ||
      die "$(L "Impossible de modifier l'envoi de métriques." "Cannot update the metric server.")"
  else
    log "RUN pvesh create /cluster/metrics/server/$PG_ID (server $ip)"
    pvesh create "/cluster/metrics/server/$PG_ID" --type influxdb "${args[@]}" >>"$PG_LOG" 2>&1 ||
      die "$(L "Impossible de créer l'envoi de métriques." "Cannot create the metric server.")"
    METRIC_CREATED=1
  fi
  ok "$(L "Proxmox envoie ses métriques vers" "Proxmox sends its metrics to") ${ip}:8086"
}

agent_conf() { # url token
  cat <<EOF
# proxmox-grafana agent
PG_URL=$1
PG_ORG=$PG_ORG
PG_BUCKET=$PG_BUCKET
PG_TOKEN=$2
PG_INTERVAL=15
PG_SMART_INTERVAL=600
EOF
}

install_agent_local() { # url token
  install -d -m 0755 /usr/local/bin
  install -m 0755 "$SRC/agent/proxmox-grafana-agent" "$PG_AGENT_BIN"
  install -d -m 0700 "$PG_ETC"
  (umask 077 && agent_conf "$1" "$2" >"$PG_ETC/agent.conf")
  install -m 0644 "$SRC/agent/proxmox-grafana-agent.service" "$PG_AGENT_UNIT"
  run systemctl daemon-reload
  run systemctl enable proxmox-grafana-agent.service
  run systemctl restart proxmox-grafana-agent.service
}

SSH_OPTS=(-e none -o BatchMode=yes -o ConnectTimeout=8)

install_agent_remote() { # nom ip url token
  local name="$1" ip="$2" target="root@$2"
  local -a opts=("${SSH_OPTS[@]}" -o "HostKeyAlias=$name")
  log "RUN install agent on $name ($ip)"
  tar --owner=0 --group=0 -C "$SRC/agent" -cf - proxmox-grafana-agent proxmox-grafana-agent.service |
    ssh "${opts[@]}" "$target" "set -e; t=\$(mktemp -d); tar --no-same-owner -C \"\$t\" -xf -; install -m 0755 \"\$t/proxmox-grafana-agent\" $PG_AGENT_BIN; install -m 0644 \"\$t/proxmox-grafana-agent.service\" $PG_AGENT_UNIT; rm -rf \"\$t\"; install -d -m 0700 $PG_ETC" >>"$PG_LOG" 2>&1 || return 1
  agent_conf "$3" "$4" | ssh "${opts[@]}" "$target" "umask 077; cat > $PG_ETC/agent.conf" >>"$PG_LOG" 2>&1 || return 1
  ssh "${opts[@]}" "$target" "systemctl daemon-reload && systemctl enable proxmox-grafana-agent.service && systemctl restart proxmox-grafana-agent.service" >>"$PG_LOG" 2>&1 || return 1
}

install_agents() {
  local url="http://${CT_IP}:8086" entry
  AGENT_NODES=""
  if ((AGENT)); then
    step "$(L "Installation de l'agent sur" "Installing the agent on") ${NODE}"
    install_agent_local "$url" "$WRITE_TOKEN"
    AGENT_NODES="$NODE"
    ok "$(L "Agent actif sur" "Agent running on") ${NODE}"
  fi
  if ((AGENT_ALL)); then
    for entry in "${OTHER_NODES[@]}"; do
      step "$(L "Installation de l'agent sur" "Installing the agent on") ${entry%%:*}"
      if install_agent_remote "${entry%%:*}" "${entry#*:}" "$url" "$WRITE_TOKEN"; then
        AGENT_NODES="${AGENT_NODES:+$AGENT_NODES }${entry%%:*}"
        ok "$(L "Agent actif sur" "Agent running on") ${entry%%:*}"
      else
        warn "$(L "Agent non installé sur ${entry%%:*} (SSH). Relancez ce script sur ce nœud et choisissez « Ajouter l'agent »." \
          "Agent not installed on ${entry%%:*} (SSH). Run this script on that node and choose \"Add the agent\".")"
      fi
    done
  fi
}

influx_count() { # mesure -> nombre de lignes recues dans les 2 dernieres minutes
  curl -sS --max-time 15 -X POST "http://${CT_IP}:8086/api/v2/query?org=${PG_ORG}" \
    -H "Authorization: Token ${READ_TOKEN}" -H 'Accept: application/csv' -H 'Content-Type: application/vnd.flux' \
    --data "from(bucket: \"${PG_BUCKET}\") |> range(start: -2m) |> filter(fn: (r) => r._measurement == \"$1\") |> limit(n: 1)" \
    2>>"$PG_LOG" | grep -c '^,_result,' || true
}

verify_install() {
  local i n=0
  step "$(L "Vérification de l'arrivée des mesures" "Checking that measurements arrive")"
  for ((i = 0; i < 24; i++)); do
    n=$(influx_count system)
    ((n > 0)) && break
    if ((i == 8)); then
      log "no data after 40 s, restarting pvestatd"
      run systemctl restart pvestatd || true
    fi
    sleep 5
  done
  if ((n > 0)); then
    ok "$(L "Proxmox envoie bien ses mesures" "Proxmox measurements are arriving")"
  else
    warn "$(L "Aucune mesure reçue pour l'instant. Vérifiez que le nœud peut joindre ${CT_IP}:8086 (pare-feu, VLAN)." \
      "No measurement received yet. Check that the node can reach ${CT_IP}:8086 (firewall, VLAN).")"
  fi
  if [[ -n "$AGENT_NODES" ]]; then
    for ((i = 0; i < 6; i++)); do
      n=$(influx_count pg_agent)
      ((n > 0)) && break
      sleep 5
    done
    if ((n > 0)); then
      ok "$(L "L'agent envoie bien ses mesures" "Agent measurements are arriving")"
    else
      warn "$(L "L'agent n'a rien envoyé pour l'instant (journalctl -u proxmox-grafana-agent)." "The agent sent nothing yet (journalctl -u proxmox-grafana-agent).")"
    fi
  fi
  local dash
  dash=$(curl -sS --max-time 10 -u "admin:${GRAFANA_PW}" "http://${CT_IP}:3000/api/search?tag=proxmox-grafana" 2>>"$PG_LOG" | grep -o '"uid"' | wc -l) || dash=0
  if ((dash >= 4)); then
    ok "$(L "Grafana répond, tableaux de bord en place" "Grafana is up, dashboards are in place") (${dash})"
  else
    warn "$(L "Grafana ne liste pas encore les tableaux de bord (ils arrivent en moins d'une minute)." "Grafana does not list the dashboards yet (they appear within a minute).")"
  fi
}

save_info() {
  install -d -m 0700 "$PG_ETC"
  (
    umask 077
    cat >"$PG_ETC/install.env" <<EOF
PG_VERSION=$PG_VERSION
PG_CTID=$CTID
PG_CT_IP=$CT_IP
PG_LANG=$UI_LANG
PG_NODE=$NODE
PG_AGENT_NODES="$AGENT_NODES"
EOF
    cat >"$PG_INFO" <<EOF
proxmox-grafana ${PG_VERSION} - $(date '+%F %T')

Grafana     : http://${CT_IP}:3000
$(L "Utilisateur" "User")  : admin
$(L "Mot de passe" "Password") : ${GRAFANA_PW}

InfluxDB    : http://${CT_IP}:8086
$(L "Utilisateur" "User")  : admin
$(L "Mot de passe" "Password") : ${INFLUX_PW}
$(L "Organisation" "Organization") : ${PG_ORG}, bucket : ${PG_BUCKET}

$(L "Conteneur" "Container")   : ${CTID} (${CT_HOSTNAME}) $(L "sur le nœud" "on node") ${NODE}
Agent       : ${AGENT_NODES:-$(L "non installé" "not installed")}

$(L "Mettre à jour les tableaux de bord" "Update the dashboards") :
  bash -c "\$(curl -fsSL https://raw.githubusercontent.com/${PG_REPO}/main/install.sh)" -- --update-dashboards
$(L "Tout désinstaller" "Uninstall everything") :
  bash -c "\$(curl -fsSL https://raw.githubusercontent.com/${PG_REPO}/main/install.sh)" -- --uninstall
EOF
  )
  run pct set "$CTID" --description "proxmox-grafana: InfluxDB 2 + Grafana.
Grafana: http://${CT_IP}:3000
https://github.com/${PG_REPO}" || true
}

do_install() {
  local existing_ct existing_ms
  existing_ct=$(find_pg_ct)
  existing_ms=$(metric_server_json)
  if [[ -n "$existing_ct" || -n "$existing_ms" ]]; then
    ui_yesno "$(L "Déjà installé" "Already installed")" "$(L "Une installation existe déjà${existing_ct:+ (conteneur ${existing_ct%% *})}.

Continuer va créer un nouveau conteneur et rediriger l'envoi des métriques vers lui. L'ancien conteneur n'est pas supprimé.

Continuer ?" "An installation already exists${existing_ct:+ (container ${existing_ct%% *})}.

Continuing creates a new container and points the metric server to it. The old container is not deleted.

Continue?")" no || ui_cancel
  fi

  ask_settings
  confirm_settings
  fetch_sources
  [[ -d "$SRC/dashboards/$UI_LANG" ]] || die "$(L "Tableaux de bord introuvables." "Dashboards not found.")"
  ensure_template
  create_ct
  setup_ct
  configure_metric_server "$CT_IP"
  install_agents
  verify_install
  save_info
  CT_CREATED=0
  METRIC_CREATED=0

  local msg
  msg="$(L "La supervision est installée." "Monitoring is installed.")

Grafana : http://${CT_IP}:3000
$(L "Utilisateur" "User") : admin
$(L "Mot de passe" "Password") : ${GRAFANA_PW}

$(L "Les graphiques se remplissent dès la première minute.
Ces informations sont aussi dans ${PG_INFO} (lisible par root seulement)." \
    "Graphs start filling within the first minute.
These details are also in ${PG_INFO} (readable by root only).")"
  ui_msg "$(L "Terminé" "Done")" "$msg"
  printf '\n%s%s%s\n\n' "$C_G" "$(L "Installation terminée." "Installation complete.")" "$C_0"
  printf '  Grafana       : %shttp://%s:3000%s\n' "$C_B" "$CT_IP" "$C_0"
  printf '  %-13s : admin\n' "$(L "Utilisateur" "User")"
  printf '  %-13s : %s\n' "$(L "Mot de passe" "Password")" "$GRAFANA_PW"
  printf '\n  %s %s\n\n' "$(L "Détails :" "Details:")" "$PG_INFO"
}

# ---------------------------------------------------------------------------
# Mise a jour des tableaux de bord et de l'agent
# ---------------------------------------------------------------------------

do_update() {
  local ct id node lang="$UI_LANG"
  ct=$(find_pg_ct)
  [[ -n "$ct" ]] || die "$(L "Aucune installation proxmox-grafana trouvée." "No proxmox-grafana installation found.")"
  id="${ct%% *}"
  node="${ct#* }"
  if [[ -f "$PG_ETC/install.env" ]]; then
    local l
    l=$(sed -n 's/^PG_LANG=//p' "$PG_ETC/install.env" | head -n1)
    [[ "$l" == "fr" || "$l" == "en" ]] && lang="$l"
  fi
  fetch_sources
  if [[ "$node" == "$NODE" ]]; then
    step "$(L "Mise à jour des tableaux de bord dans le conteneur" "Updating dashboards in the container") ${id}"
    local tmp
    tmp=$(mktemp -d /tmp/proxmox-grafana-dash.XXXXXX)
    tar --owner=0 --group=0 -C "$SRC/dashboards/$lang" -czf "$tmp/d.tgz" .
    run pct push "$id" "$tmp/d.tgz" /root/proxmox-grafana-dashboards.tgz
    rm -rf "$tmp"
    run pct exec "$id" -- bash -c 'd=/var/lib/grafana/dashboards/proxmox-grafana; mkdir -p "$d" && rm -f "$d"/*.json && tar --no-same-owner -C "$d" -xzf /root/proxmox-grafana-dashboards.tgz && rm -f /root/proxmox-grafana-dashboards.tgz && chown -R grafana:grafana "$d"'
    ok "$(L "Tableaux de bord mis à jour (Grafana les recharge sous 30 secondes)" "Dashboards updated (Grafana reloads them within 30 seconds)")"
  else
    warn "$(L "Le conteneur ${id} est sur le nœud ${node} : lancez la mise à jour sur ce nœud pour les tableaux de bord." \
      "Container ${id} is on node ${node}: run the update on that node for the dashboards.")"
  fi
  if [[ -f "$PG_AGENT_BIN" ]]; then
    step "$(L "Mise à jour de l'agent" "Updating the agent")"
    install -m 0755 "$SRC/agent/proxmox-grafana-agent" "$PG_AGENT_BIN"
    install -m 0644 "$SRC/agent/proxmox-grafana-agent.service" "$PG_AGENT_UNIT"
    run systemctl daemon-reload
    run systemctl restart proxmox-grafana-agent.service
    ok "$(L "Agent mis à jour sur" "Agent updated on") ${NODE}"
  fi
}

# ---------------------------------------------------------------------------
# Agent seul (autre noeud d'un cluster)
# ---------------------------------------------------------------------------

do_agent_only() {
  local j server port token
  j=$(metric_server_json)
  [[ -n "$j" ]] || die "$(L "Aucun envoi de métriques « proxmox-grafana » dans ce cluster. Faites d'abord l'installation complète sur un nœud." \
    "No \"proxmox-grafana\" metric server in this cluster. Run the full installation on one node first.")"
  server=$(json_get "$j" server)
  port=$(json_get "$j" port)
  token=$(cat "/etc/pve/priv/metricserver/${PG_ID}.pw" 2>/dev/null || true)
  [[ -n "$server" && -n "$token" ]] || die "$(L "Configuration incomplète (serveur ou jeton)." "Incomplete configuration (server or token).")"
  fetch_sources
  step "$(L "Installation de l'agent sur" "Installing the agent on") ${NODE}"
  install_agent_local "http://${server}:${port:-8086}" "$token"
  ok "$(L "Agent actif sur" "Agent running on") ${NODE}"
}

# ---------------------------------------------------------------------------
# Desinstallation
# ---------------------------------------------------------------------------

guest_exists() { # vmid
  pvesh get /cluster/resources --type vm --output-format json 2>/dev/null |
    perl -MJSON::PP -0777 -ne 'my $d = eval { decode_json($_) } || []; exit((grep { ($_->{vmid} // 0) == $ARGV[0] } @$d) ? 0 : 1)' "$1"
}

destroy_ct() { # vmid noeud
  local id="$1" node="$2" i
  if [[ "$node" == "$NODE" ]]; then
    run pct stop "$id" || true
    run pct destroy "$id" --purge 1 || run pct destroy "$id" || return 1
    return 0
  fi
  run pvesh create "/nodes/${node}/lxc/${id}/status/stop" || true
  for ((i = 0; i < 60; i++)); do
    pvesh get "/nodes/${node}/lxc/${id}/status/current" --output-format json 2>/dev/null | grep -q '"status":"stopped"' && break
    sleep 2
  done
  run pvesh delete "/nodes/${node}/lxc/${id}" --purge 1 || run pvesh delete "/nodes/${node}/lxc/${id}" || return 1
  for ((i = 0; i < 60; i++)); do
    guest_exists "$id" || return 0
    sleep 2
  done
  return 1
}

remove_agent_local() {
  systemctl disable --now proxmox-grafana-agent.service >>"$PG_LOG" 2>&1 || true
  rm -f "$PG_AGENT_UNIT" "$PG_AGENT_BIN" "$PG_ETC/agent.conf"
  systemctl daemon-reload >>"$PG_LOG" 2>&1 || true
}

do_uninstall() {
  local ct id="" node="" j text destroy="no"
  ct=$(find_pg_ct)
  j=$(metric_server_json)
  if [[ -n "$ct" ]]; then id="${ct%% *}"; node="${ct#* }"; fi
  if [[ -z "$ct" && -z "$j" && ! -f "$PG_AGENT_BIN" ]]; then
    ui_msg "proxmox-grafana" "$(L "Rien à désinstaller." "Nothing to uninstall.")"
    echo "$(L "Rien à désinstaller." "Nothing to uninstall.")"
    return 0
  fi
  text="$(L "Seront retirés :" "Will be removed:")
 - $(L "l'envoi de métriques « proxmox-grafana »" "the \"proxmox-grafana\" metric server")
 - $(L "l'agent sur les nœuds où il est installé" "the agent on the nodes where it is installed")"
  # Sans questions (--unattended), --uninstall vaut confirmation
  local confirm="no"
  ((UNATTENDED)) && confirm="yes"
  ui_yesno "$(L "Désinstaller" "Uninstall")" "$text

$(L "Continuer ?" "Continue?")" "$confirm" || ui_cancel

  if [[ -n "$id" ]]; then
    local def="no"
    [[ "${PG_DESTROY_CT:-0}" == "1" ]] && def="yes"
    if ui_yesno "$(L "Conteneur" "Container")" "$(L "Supprimer aussi le conteneur ${id} (sur ${node}) et tout l'historique des mesures ?

Cette suppression est définitive." "Also delete container ${id} (on ${node}) and all measurement history?

This cannot be undone.")" "$def"; then
      destroy="yes"
    fi
  fi

  if [[ -n "$j" ]]; then
    step "$(L "Retrait de l'envoi de métriques" "Removing the metric server")"
    run pvesh delete "/cluster/metrics/server/$PG_ID" || warn "pvesh delete"
    ok "$(L "Envoi de métriques retiré" "Metric server removed")"
  fi

  step "$(L "Retrait de l'agent" "Removing the agent")"
  remove_agent_local
  local nname nip nonline nlocal
  while read -r nname nip nonline nlocal; do
    [[ -n "$nname" ]] || continue
    ((nlocal)) && continue
    ((nonline)) || continue
    ssh "${SSH_OPTS[@]}" -o "HostKeyAlias=$nname" "root@$nip" \
      "if [ -f $PG_AGENT_UNIT ]; then systemctl disable --now proxmox-grafana-agent.service; rm -f $PG_AGENT_UNIT $PG_AGENT_BIN $PG_ETC/agent.conf; systemctl daemon-reload; fi" \
      >>"$PG_LOG" 2>&1 || warn "$(L "Nœud ${nname} injoignable, agent à retirer à la main." "Node ${nname} unreachable, remove the agent by hand.")"
  done < <(cluster_nodes)
  ok "$(L "Agent retiré" "Agent removed")"

  if [[ "$destroy" == "yes" ]]; then
    step "$(L "Suppression du conteneur" "Deleting the container") ${id}"
    if destroy_ct "$id" "$node"; then
      rm -f "$PG_INFO"
      ok "$(L "Conteneur supprimé" "Container deleted")"
    else
      warn "$(L "Suppression du conteneur impossible, à faire depuis l'interface." "Could not delete the container, do it from the web interface.")"
    fi
  elif [[ -n "$id" ]]; then
    info "$(L "Conteneur ${id} conservé (vous pouvez le supprimer plus tard depuis l'interface)." "Container ${id} kept (you can delete it later from the web interface).")"
  fi
  rm -f "$PG_ETC/install.env"
  rmdir "$PG_ETC" 2>/dev/null || true
  printf '\n%s%s%s\n' "$C_G" "$(L "Désinstallation terminée." "Uninstall complete.")" "$C_0"
}

# Sur une seule ligne : fonctionne aussi avec "curl ... | bash"
main "$@"; exit $?
