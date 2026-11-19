#!/usr/bin/env python3
"""Genere les tableaux de bord Grafana dans dashboards/fr et dashboards/en.

Une seule definition pour les deux langues : modifier ce fichier puis lancer
    python3 tools/build-dashboards.py

Les requetes sont en Flux (InfluxDB 2). Elles lisent :
- ce que Proxmox VE envoie lui-meme (mesures system, cpustat, memory,
  blockstat, nics, tags object/host/nodename/vmid) ;
- ce que l'agent envoie (mesures pg_disk, pg_temp, pg_fan, pg_smart, pg_zfs).
"""

import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS = {"type": "influxdb", "uid": "${ds}"}
TAG = "proxmox-grafana"
LANG = "fr"

# ---------------------------------------------------------------------------
# Textes
# ---------------------------------------------------------------------------

S = {
    "t_overview": ("Proxmox - Vue d'ensemble", "Proxmox - Overview"),
    "t_node": ("Proxmox - Nœud", "Proxmox - Node"),
    "t_guest": ("Proxmox - VM et conteneurs", "Proxmox - VMs and containers"),
    "t_avail": ("Proxmox - Disponibilité", "Proxmox - Availability"),
    "d_overview": ("État de tout le serveur ou du cluster : nœuds, VM, conteneurs et stockages.",
                   "State of the whole server or cluster: nodes, VMs, containers and storages."),
    "d_node": ("Détail d'un nœud : processeur, mémoire, réseau, stockages, disques physiques, températures, SMART et ZFS.",
               "Node details: CPU, memory, network, storages, physical disks, temperatures, SMART and ZFS."),
    "d_guest": ("Détail d'une VM ou d'un conteneur.", "Details of a VM or container."),
    "d_avail": ("Historique marche / arrêt des nœuds, VM et conteneurs.",
                "On / off history of nodes, VMs and containers."),
    "v_node": ("Nœud", "Node"),
    "v_guest": ("VM / CT", "VM / CT"),
    "nodes": ("Nœuds", "Nodes"),
    "vms": ("VM", "VMs"),
    "cts": ("Conteneurs", "Containers"),
    "online": ("En ligne", "Online"),
    "offline": ("Hors ligne", "Offline"),
    "running": ("En marche", "Running"),
    "stopped": ("Arrêté", "Stopped"),
    "stopped_pl": ("Arrêtés", "Stopped"),
    "unknown": ("Sans nouvelles", "No data"),
    "cpu_total": ("Processeur (total)", "CPU (total)"),
    "ram_total": ("Mémoire (total)", "Memory (total)"),
    "storage_max": ("Stockage le plus rempli", "Fullest storage"),
    "nodes_table": ("Nœuds", "Nodes"),
    "cpu_by_node": ("Processeur par nœud", "CPU per node"),
    "ram_by_node": ("Mémoire par nœud", "Memory per node"),
    "net_by_node": ("Réseau par nœud (cartes physiques)", "Network per node (physical NICs)"),
    "guests": ("VM et conteneurs", "VMs and containers"),
    "guests_table": ("Toutes les VM et tous les conteneurs", "All VMs and containers"),
    "guests_desc": ("Cliquez sur un nom pour ouvrir son détail. « Sans nouvelles » : plus de mesure depuis 90 secondes (nœud éteint ou invité supprimé).",
                    "Click a name to open its details. \"No data\": no measurement for 90 seconds (node down or guest deleted)."),
    "top_cpu": ("Les plus chargés (processeur)", "Busiest (CPU)"),
    "top_cpu_desc": ("Moyenne des 5 dernières minutes, en % des cœurs donnés à chaque invité.",
                     "Average over the last 5 minutes, as a % of the cores given to each guest."),
    "top_ram": ("Les plus gourmands (mémoire)", "Biggest (memory)"),
    "storage": ("Stockage", "Storage"),
    "storage_usage": ("Remplissage des stockages", "Storage usage"),
    "storage_table": ("Détail des stockages", "Storage details"),
    "storage_trend": ("Évolution du remplissage", "Usage over time"),
    "col_state": ("État", "State"),
    "col_type": ("Type", "Type"),
    "col_id": ("ID", "ID"),
    "col_name": ("Nom", "Name"),
    "col_node": ("Nœud", "Node"),
    "col_cpu": ("Processeur", "CPU"),
    "col_vcpu": ("vCPU", "vCPU"),
    "col_cores": ("Cœurs", "Cores"),
    "col_load": ("Charge 1 min", "Load 1 min"),
    "col_ram": ("Mémoire", "Memory"),
    "col_ram_used": ("Mémoire utilisée", "Memory used"),
    "col_ram_max": ("Mémoire allouée", "Memory allocated"),
    "col_ram_total": ("Mémoire totale", "Total memory"),
    "col_swap": ("Swap", "Swap"),
    "col_rootfs": ("Disque système", "System disk"),
    "col_disk": ("Disque", "Disk"),
    "col_disk_max": ("Taille disque", "Disk size"),
    "col_uptime": ("Allumé depuis", "Uptime"),
    "col_storage": ("Stockage", "Storage"),
    "col_used": ("Utilisé", "Used"),
    "col_total": ("Total", "Total"),
    "col_free": ("Libre", "Free"),
    "col_pct": ("Remplissage", "Usage"),
    "col_avail": ("Disponibilité", "Availability"),
    "col_model": ("Modèle", "Model"),
    "col_health": ("Santé", "Health"),
    "col_temp": ("Température", "Temperature"),
    "col_hours": ("Heures de marche", "Power-on hours"),
    "col_wear": ("Usure", "Wear"),
    "col_realloc": ("Secteurs réalloués", "Reallocated sectors"),
    "col_pending": ("Secteurs en attente", "Pending sectors"),
    "col_uncorr": ("Erreurs non corrigées", "Uncorrectable errors"),
    "col_crc": ("Erreurs CRC (câble)", "CRC errors (cable)"),
    "col_media": ("Erreurs média", "Media errors"),
    "col_spare": ("Réserve", "Spare"),
    "col_unsafe": ("Coupures brutales", "Unsafe shutdowns"),
    "col_pool": ("Pool", "Pool"),
    "col_size": ("Taille", "Size"),
    "col_frag": ("Fragmentation", "Fragmentation"),
    "ok": ("OK", "OK"),
    "fail": ("PANNE", "FAILING"),
    "rx": ("reçu", "received"),
    "tx": ("émis", "sent"),
    "read": ("lecture", "read"),
    "write": ("écriture", "write"),
    "na": ("-", "-"),
    "state": ("État", "State"),
    "uptime": ("Allumé depuis", "Uptime"),
    "cpu": ("Processeur", "CPU"),
    "ram": ("Mémoire", "Memory"),
    "swap": ("Swap", "Swap"),
    "rootfs": ("Disque système", "System disk"),
    "load": ("Charge moyenne", "Load average"),
    "cpu_usage": ("Utilisation", "Usage"),
    "iowait": ("Attente des disques", "Disk wait (iowait)"),
    "cores_line": ("Nombre de cœurs", "Number of cores"),
    "mem_used": ("Utilisée", "Used"),
    "mem_total": ("Totale", "Total"),
    "mem_alloc": ("Allouée", "Allocated"),
    "mem_host": ("Occupée sur l'hôte", "Used on host"),
    "arc": ("Cache ZFS (ARC)", "ZFS cache (ARC)"),
    "swap_used": ("Swap utilisé", "Swap used"),
    "cpu_mem": ("Processeur et mémoire", "CPU and memory"),
    "network": ("Réseau", "Network"),
    "net_ifaces": ("Trafic par interface", "Traffic per interface"),
    "node_storage": ("Stockages du nœud", "Node storages"),
    "agent_disks": ("Disques physiques (agent)", "Physical disks (agent)"),
    "agent_desc": ("Ces graphiques viennent de l'agent proxmox-grafana installé sur le nœud.",
                   "These graphs come from the proxmox-grafana agent installed on the node."),
    "no_agent": ("Pas de données : agent non installé sur ce nœud ?", "No data: agent not installed on this node?"),
    "disk_tp": ("Débit par disque", "Throughput per disk"),
    "disk_busy": ("Occupation des disques", "Disk busy time"),
    "disk_busy_desc": ("Part du temps où le disque travaille. Proche de 100 % : le disque est saturé.",
                       "Share of time the disk is working. Close to 100%: the disk is saturated."),
    "disk_iops": ("Opérations par seconde", "Operations per second"),
    "disk_lat": ("Temps de réponse moyen", "Average response time"),
    "smart": ("Santé des disques (SMART)", "Disk health (SMART)"),
    "smart_desc": ("Relevé toutes les 10 minutes. Les disques en veille ne sont pas réveillés.",
                   "Read every 10 minutes. Sleeping disks are not woken up."),
    "temps": ("Températures", "Temperatures"),
    "fans": ("Ventilateurs", "Fans"),
    "zfs": ("Pools ZFS", "ZFS pools"),
    "zfs_desc": ("Vide si le nœud n'a pas de pool ZFS ou si l'agent n'est pas installé.",
                 "Empty if the node has no ZFS pool or if the agent is not installed."),
    "guests_on_node": ("VM et conteneurs du nœud", "VMs and containers on this node"),
    "type_node": ("Type / nœud", "Type / node"),
    "vcpu": ("vCPU", "vCPU"),
    "disk": ("Disque", "Disk"),
    "vm_na": ("VM : non mesuré", "VM: not measured"),
    "disk_io": ("Lectures et écritures disque", "Disk reads and writes"),
    "net_io": ("Trafic réseau", "Network traffic"),
    "pressure": ("Pression (attente de ressources)", "Pressure (waiting for resources)"),
    "pressure_desc": ("Part du temps où l'invité attend le processeur, les disques ou la mémoire. Proxmox VE 9 ou plus récent.",
                      "Share of time the guest waits for CPU, disks or memory. Proxmox VE 9 or newer."),
    "pressure_na": ("Pas de données (Proxmox VE 9 requis)", "No data (Proxmox VE 9 required)"),
    "p_cpu": ("processeur", "CPU"),
    "p_io": ("disques", "disks"),
    "p_mem": ("mémoire", "memory"),
    "drives": ("Disques de la VM", "VM drives"),
    "drives_na": ("Pas de données (VM uniquement)", "No data (VMs only)"),
    "state_history": ("Historique marche / arrêt", "On / off history"),
    "nodes_history": ("Nœuds en ligne", "Nodes online"),
    "guests_history": ("VM et conteneurs en marche", "Running VMs and containers"),
    "avail_table": ("Disponibilité sur la période", "Availability over the period"),
    "avail_desc": ("Part du temps passé en marche sur la période choisie en haut à droite.",
                   "Share of time spent running over the period selected at the top right."),
    "links": ("Proxmox", "Proxmox"),
}


def t(key):
    return S[key][0 if LANG == "fr" else 1]


# ---------------------------------------------------------------------------
# Briques Grafana
# ---------------------------------------------------------------------------

GREEN, ORANGE, RED, BLUE, GREY, PURPLE = "green", "orange", "red", "blue", "#8e8e8e", "purple"


def th(*steps):
    """th((None, 'green'), (0.8, 'orange'))"""
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for v, c in steps]}


TH_PCT = th((None, GREEN), (0.75, ORANGE), (0.9, RED))
TH_BLUE = th((None, BLUE))


def vmap(values):
    """values: liste (valeur, texte, couleur)"""
    opts = {}
    for i, (v, text, color) in enumerate(values):
        opts[str(v)] = {"text": text, "color": color, "index": i}
    return [{"type": "value", "options": opts}]


def map_state():
    return vmap([(1, t("running"), GREEN), (0, t("stopped"), RED), (2, t("unknown"), GREY)])


def map_online():
    return vmap([(1, t("online"), GREEN), (0, t("offline"), RED)])


def tgt(query, ref="A"):
    return {"refId": ref, "datasource": DS, "query": query.strip()}


def ov(matcher, props, kind="byName"):
    return {"matcher": {"id": kind, "options": matcher},
            "properties": [{"id": k, "value": v} for k, v in props]}


def panel(ptype, title, targets, defaults=None, overrides=None, options=None, desc="", **extra):
    p = {
        "type": ptype,
        "title": title,
        "description": desc,
        "datasource": DS,
        "targets": targets if isinstance(targets, list) else [targets],
        "fieldConfig": {"defaults": defaults or {}, "overrides": overrides or []},
        "options": options or {},
    }
    p.update(extra)
    return p


def stat(title, targets, unit="none", thresholds=None, mappings=None, color_mode="value",
         text_mode="auto", fields="", overrides=None, desc="", decimals=None, no_value=None,
         orientation="auto", order=None):
    d = {"unit": unit, "color": {"mode": "thresholds"}, "thresholds": thresholds or TH_BLUE,
         "mappings": mappings or []}
    if decimals is not None:
        d["decimals"] = decimals
    if no_value is not None:
        d["noValue"] = no_value
    return panel("stat", title, targets, d, overrides, {
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": fields, "values": False},
        "orientation": orientation, "textMode": text_mode, "colorMode": color_mode,
        "graphMode": "none", "justifyMode": "center", "wideLayout": True,
        "showPercentChange": False,
    }, desc, transformations=[{"id": "organize", "options": {
        "excludeByName": {}, "renameByName": {},
        "indexByName": {name: i for i, name in enumerate(order)}}}] if order else [])


def gauge(title, targets, unit="percentunit", thresholds=None, desc="", no_value=None,
          display_name=None, vmax=1):
    d = {"unit": unit, "min": 0, "max": vmax, "decimals": 1, "color": {"mode": "thresholds"},
         "thresholds": thresholds or TH_PCT, "mappings": []}
    if no_value is not None:
        d["noValue"] = no_value
    if display_name:
        d["displayName"] = display_name
    return panel("gauge", title, targets, d, [], {
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        "showThresholdLabels": False, "showThresholdMarkers": True, "orientation": "auto",
        "minVizHeight": 75, "minVizWidth": 75, "sizing": "auto",
    }, desc)


def timeseries(title, targets, unit="none", overrides=None, desc="", display_name=None,
               legend="list", calcs=None, soft_max=None, fill=12, no_value=None, vmin=0,
               decimals=None, interval=None):
    custom = {"drawStyle": "line", "lineInterpolation": "linear", "lineWidth": 1,
              "fillOpacity": fill, "gradientMode": "opacity", "showPoints": "never",
              "pointSize": 4, "spanNulls": False, "axisBorderShow": False,
              "stacking": {"mode": "none", "group": "A"}, "thresholdsStyle": {"mode": "off"}}
    if soft_max is not None:
        custom["axisSoftMax"] = soft_max
    d = {"unit": unit, "custom": custom, "color": {"mode": "palette-classic"},
         "thresholds": TH_BLUE, "mappings": []}
    if vmin is not None:
        custom["axisSoftMin"] = vmin
    if display_name:
        d["displayName"] = display_name
    if no_value is not None:
        d["noValue"] = no_value
    if decimals is not None:
        d["decimals"] = decimals
    extra = {}
    if interval:
        extra["interval"] = interval
    return panel("timeseries", title, targets, d, overrides, {
        "legend": {"showLegend": True, "displayMode": legend, "placement": "bottom",
                   "calcs": calcs if calcs is not None else (["mean", "max", "lastNotNull"] if legend == "table" else [])},
        "tooltip": {"mode": "multi", "sort": "desc"},
    }, desc, **extra)


def table(title, targets, overrides=None, order=None, desc="", sort_by=None, no_value=None, height_mode="sm"):
    d = {"custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False,
                    "filterable": False}, "color": {"mode": "thresholds"}, "thresholds": TH_BLUE,
         "mappings": []}
    if no_value is not None:
        d["noValue"] = no_value
    transformations = []
    if order:
        transformations.append({"id": "organize", "options": {
            "excludeByName": {}, "renameByName": {},
            "indexByName": {name: i for i, name in enumerate(order)}}})
    return panel("table", title, targets, d, overrides, {
        "showHeader": True, "cellHeight": height_mode,
        "footer": {"show": False, "reducer": ["sum"], "fields": "", "countRows": False},
        "sortBy": sort_by or [],
    }, desc, transformations=transformations)


def bargauge(title, targets, unit="percentunit", thresholds=None, vmax=1, desc="", no_value=None, decimals=1):
    d = {"unit": unit, "min": 0, "color": {"mode": "thresholds"},
         "thresholds": thresholds or TH_PCT, "mappings": [], "decimals": decimals}
    if vmax is not None:
        d["max"] = vmax
    if no_value is not None:
        d["noValue"] = no_value
    return panel("bargauge", title, targets, d, [], {
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "/^_value$/", "values": True},
        "orientation": "horizontal", "displayMode": "gradient", "valueMode": "color",
        "namePlacement": "left", "showUnfilled": True, "sizing": "auto",
        "minVizWidth": 8, "minVizHeight": 16, "maxVizHeight": 300,
    }, desc)


def timeline(title, targets, mappings, desc="", interval="30s"):
    d = {"color": {"mode": "thresholds"}, "thresholds": th((None, RED), (1, GREEN)), "mappings": mappings,
         "custom": {"fillOpacity": 80, "lineWidth": 0, "spanNulls": False, "insertNulls": False,
                    "hideFrom": {"legend": False, "tooltip": False, "viz": False}}}
    return panel("state-timeline", title, targets, d, [], {
        "showValue": "never", "mergeValues": True, "alignValue": "left", "rowHeight": 0.85,
        "legend": {"showLegend": False, "displayMode": "list", "placement": "bottom"},
        "tooltip": {"mode": "single", "sort": "none"},
    }, desc, interval=interval)


# Proprietes de colonnes de tableau
def col(name, title, unit=None, width=None, gauge_cell=False, mappings=None, thresholds=None,
        vmin=None, vmax=None, decimals=None, links=None, cell=None):
    props = [("displayName", title)]
    if unit:
        props.append(("unit", unit))
    if width:
        props.append(("custom.width", width))
    if gauge_cell:
        props.append(("custom.cellOptions", {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"}))
    if cell:
        props.append(("custom.cellOptions", cell))
    if mappings:
        props.append(("mappings", mappings))
    if thresholds:
        props.append(("thresholds", thresholds))
        props.append(("color", {"mode": "thresholds"}))
    if vmin is not None:
        props.append(("min", vmin))
    if vmax is not None:
        props.append(("max", vmax))
    if decimals is not None:
        props.append(("decimals", decimals))
    if links:
        props.append(("links", links))
    return ov(name, props)


def guest_link(field="id"):
    return [{"title": t("t_guest"), "url": "/d/pg-guest?var-guest=${__data.fields.%s}&${__url_time_range}" % field}]


def node_link(field="node"):
    return [{"title": t("t_node"), "url": "/d/pg-node?var-node=${__data.fields.%s}&${__url_time_range}" % field}]


def by_ref(ref, props):
    return ov(ref, props, kind="byFrameRefID")


def dash_line(color):
    return [("custom.lineStyle", {"fill": "dash", "dash": [10, 10]}), ("custom.fillOpacity", 0),
            ("color", {"mode": "fixed", "fixedColor": color})]


def neg_y():
    return [("custom.transform", "negative-Y")]


# ---------------------------------------------------------------------------
# Mise en page
# ---------------------------------------------------------------------------

class Dash:
    def __init__(self, uid, title_key, desc_key, variables, time_from="now-6h"):
        self.uid = uid
        self.title = t(title_key)
        self.desc = t(desc_key)
        self.variables = variables
        self.time_from = time_from
        self.panels = []
        self.x = 0
        self.y = 0
        self.rowh = 0
        self.next_id = 1

    def _newline(self):
        if self.x > 0:
            self.y += self.rowh
            self.x = 0
            self.rowh = 0

    def row(self, title):
        self._newline()
        self.panels.append({"type": "row", "title": title, "collapsed": False, "id": self.next_id,
                            "gridPos": {"h": 1, "w": 24, "x": 0, "y": self.y}, "panels": []})
        self.next_id += 1
        self.y += 1

    def add(self, p, w, h):
        if self.x + w > 24:
            self._newline()
        p["gridPos"] = {"h": h, "w": w, "x": self.x, "y": self.y}
        p["id"] = self.next_id
        self.next_id += 1
        self.panels.append(p)
        self.x += w
        self.rowh = max(self.rowh, h)

    def build(self):
        return {
            "uid": self.uid,
            "title": self.title,
            "description": self.desc,
            "tags": ["proxmox", TAG],
            "timezone": "browser",
            "editable": True,
            "graphTooltip": 1,
            "refresh": "30s",
            "schemaVersion": 39,
            "version": 1,
            "time": {"from": self.time_from, "to": "now"},
            "timepicker": {"refresh_intervals": ["10s", "30s", "1m", "5m", "15m", "1h"]},
            "fiscalYearStartMonth": 0,
            "liveNow": False,
            "weekStart": "",
            "annotations": {"list": [{
                "builtIn": 1, "datasource": {"type": "grafana", "uid": "-- Grafana --"},
                "enable": True, "hide": True, "iconColor": "rgba(0, 211, 255, 1)",
                "name": "Annotations & Alerts", "type": "dashboard"}]},
            "links": [{"type": "dashboards", "tags": [TAG], "asDropdown": False, "includeVars": False,
                       "keepTime": True, "title": t("links"), "icon": "external link",
                       "targetBlank": False, "tooltip": ""}],
            "templating": {"list": self.variables},
            "panels": self.panels,
        }


# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

def var_ds():
    return {"type": "datasource", "name": "ds", "label": "InfluxDB", "query": "influxdb",
            "hide": 2, "refresh": 1, "regex": "", "current": {}, "options": [], "skipUrlSync": False}


def var_bucket():
    return {"type": "constant", "name": "bucket", "label": "bucket", "query": "proxmox", "hide": 2,
            "skipUrlSync": False, "current": {"text": "proxmox", "value": "proxmox"},
            "options": [{"selected": True, "text": "proxmox", "value": "proxmox"}]}


Q_NODES_VAR = '''
import "influxdata/influxdb/schema"
schema.tagValues(bucket: "${bucket}", tag: "host", predicate: (r) => r._measurement == "cpustat" and r.object == "nodes", start: -7d)
'''


def var_node(multi):
    v = {"type": "query", "name": "node", "label": t("v_node"), "datasource": DS,
         "query": Q_NODES_VAR.strip(), "definition": Q_NODES_VAR.strip(), "refresh": 1, "regex": "",
         "sort": 1, "hide": 0, "multi": multi, "includeAll": multi, "options": [],
         "skipUrlSync": False}
    if multi:
        v["allValue"] = ".*"
        v["current"] = {"selected": True, "text": ["All"], "value": ["$__all"]}
    else:
        v["current"] = {}
    return v


Q_GUESTS_VAR = '''
from(bucket: "${bucket}")
  |> range(start: -7d)
  |> filter(fn: (r) => r._measurement == "system" and (r.object == "qemu" or r.object == "lxc") and r._field == "uptime")
  |> last()
  |> group()
  |> map(fn: (r) => ({_value: r.vmid + " " + (if exists r.host then r.host else "")}))
'''


def var_guest():
    return {"type": "query", "name": "guest", "label": t("v_guest"), "datasource": DS,
            "query": Q_GUESTS_VAR.strip(), "definition": Q_GUESTS_VAR.strip(), "refresh": 1,
            "regex": "/(?<text>(?<value>[0-9]+) ?.*)/", "sort": 3, "hide": 0, "multi": False,
            "includeAll": False, "options": [], "current": {}, "skipUrlSync": False}


# ---------------------------------------------------------------------------
# Requetes Flux
# ---------------------------------------------------------------------------

NOW_STALE = "int(v: r._time) < int(v: now()) - 90000000000"
F_NODES = 'r.host =~ /^${node:regex}$/'          # filtre noeud (variable multiple)
F_GNODES = 'r.nodename =~ /^${node:regex}$/'     # idem pour les invites et stockages
F_NODE = 'r.host == "${node}"'                   # noeud unique
F_GNODE = 'r.nodename == "${node}"'
RANGE = 'range(start: v.timeRangeStart, stop: v.timeRangeStop)'
NAME = '(if exists r.host then r.host else "")'


def q_count_nodes():
    return '''
from(bucket: "${bucket}")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "system" and r.object == "nodes" and r._field == "uptime")
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> reduce(identity: {online: 0, offline: 0}, fn: (r, accumulator) => ({
      online: accumulator.online + (if %s then 0 else 1),
      offline: accumulator.offline + (if %s then 1 else 0)}))
''' % (F_NODES, NOW_STALE, NOW_STALE)


def q_count_guests(obj):
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "system" and r.object == "%s" and r._field == "status")
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> reduce(identity: {running: 0, stopped: 0}, fn: (r, accumulator) => ({
      running: accumulator.running + (if r._value == "running" and not (%s) then 1 else 0),
      stopped: accumulator.stopped + (if r._value == "running" and not (%s) then 0 else 1)}))
''' % (obj, F_GNODES, NOW_STALE, NOW_STALE)


def q_cluster_cpu():
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "cpustat" and r.object == "nodes" and (r._field == "cpu" or r._field == "cpus"))
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> pivot(rowKey: ["host"], columnKey: ["_field"], valueColumn: "_value")
  |> reduce(identity: {used: 0.0, total: 0.0}, fn: (r, accumulator) => ({used: accumulator.used + r.cpu * r.cpus, total: accumulator.total + r.cpus}))
  |> map(fn: (r) => ({_value: if r.total > 0.0 then r.used / r.total else 0.0}))
''' % F_NODES


def q_cluster_ram():
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "memory" and r.object == "nodes" and (r._field == "memused" or r._field == "memtotal"))
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> pivot(rowKey: ["host"], columnKey: ["_field"], valueColumn: "_value")
  |> reduce(identity: {used: 0.0, total: 0.0}, fn: (r, accumulator) => ({used: accumulator.used + r.memused, total: accumulator.total + r.memtotal}))
  |> map(fn: (r) => ({_value: if r.total > 0.0 then r.used / r.total else 0.0}))
''' % F_NODES


def q_storages_rows(node_filter, label_expr):
    """Une ligne par stockage (les stockages partages ne sont comptes qu'une fois)."""
    return '''
from(bucket: "${bucket}")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "system" and r.object == "storages" and (r._field == "used" or r._field == "total" or r._field == "avail" or r._field == "shared"))
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> pivot(rowKey: ["nodename", "host", "type"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => exists r.total and r.total > 0.0)
  |> map(fn: (r) => ({storage: %s, type: r.type, used: r.used, total: r.total, avail: r.avail, _value: r.used / r.total}))
  |> unique(column: "storage")
  |> sort(columns: ["_value"], desc: true)
''' % (node_filter, label_expr)


STORAGE_LABEL_MULTI = 'if r.shared == 1.0 then r.host else r.nodename + " / " + r.host'
STORAGE_LABEL_SINGLE = 'r.host'
STORAGE_LABEL_TREND = 'r.nodename + " / " + r.host'


def q_storage_max():
    return q_storages_rows(F_GNODES, STORAGE_LABEL_MULTI) + '''  |> limit(n: 1)
  |> map(fn: (r) => ({_value: r._value, storage: r.storage}))
  |> group(columns: ["storage"])
'''


def q_storage_trend(node_filter, label_expr):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and r.object == "storages" and (r._field == "used" or r._field == "total"))
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["nodename", "host"])
  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> filter(fn: (r) => exists r.total and r.total > 0.0)
  |> map(fn: (r) => ({_time: r._time, _value: r.used / r.total, storage: %s}))
  |> group(columns: ["storage"])
''' % (RANGE, node_filter, label_expr)


def q_nodes_table():
    return '''
data = from(bucket: "${bucket}")
  |> range(start: -24h)
  |> filter(fn: (r) => r.object == "nodes")
  |> filter(fn: (r) => %s)
  |> filter(fn: (r) =>
      (r._measurement == "cpustat" and (r._field == "cpu" or r._field == "cpus" or r._field == "avg1")) or
      (r._measurement == "memory" and (r._field == "memused" or r._field == "memtotal" or r._field == "swapused" or r._field == "swaptotal")) or
      (r._measurement == "blockstat" and (r._field == "used" or r._field == "blocks")) or
      (r._measurement == "system" and r._field == "uptime"))
  |> last()
  |> toFloat()
  |> group()
online = data
  |> filter(fn: (r) => r._field == "uptime")
  |> map(fn: (r) => ({r with _field: "online", _value: if %s then 0.0 else 1.0}))
union(tables: [data, online])
  |> group()
  |> pivot(rowKey: ["host"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({
      node: r.host,
      online: r.online,
      cpu: r.cpu,
      cpus: r.cpus,
      load: r.avg1,
      ram: if r.memtotal > 0.0 then r.memused / r.memtotal else 0.0,
      ram_total: r.memtotal,
      swap: if r.swaptotal > 0.0 then r.swapused / r.swaptotal else 0.0,
      rootfs: if r.blocks > 0.0 then r.used / r.blocks else 0.0,
      uptime: if r.online > 0.0 then r.uptime else 0.0}))
  |> sort(columns: ["node"])
''' % (F_NODES, NOW_STALE)


def q_guests_table(node_filter):
    return '''
base = from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "system" and (r.object == "qemu" or r.object == "lxc"))
  |> filter(fn: (r) => %s)
st = base
  |> filter(fn: (r) => r._field == "status")
  |> last()
  |> group()
  |> map(fn: (r) => ({r with _value: if %s then 2.0 else if r._value == "running" then 1.0 else 0.0}))
num = base
  |> filter(fn: (r) => r._field == "cpu" or r._field == "cpus" or r._field == "mem" or r._field == "maxmem" or r._field == "disk" or r._field == "maxdisk" or r._field == "uptime")
  |> last()
  |> toFloat()
  |> group()
union(tables: [st, num])
  |> group()
  |> pivot(rowKey: ["object", "vmid", "nodename", "host"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({
      state: r.status,
      type: if r.object == "qemu" then "VM" else "CT",
      id: int(v: r.vmid),
      name: r.host,
      node: r.nodename,
      cpu: r.cpu,
      cpus: r.cpus,
      ram: if r.maxmem > 0.0 then r.mem / r.maxmem else 0.0,
      ram_used: r.mem,
      ram_max: r.maxmem,
      disk: if r.object == "lxc" and r.maxdisk > 0.0 then r.disk / r.maxdisk else -1.0,
      disk_max: r.maxdisk,
      uptime: if r.status == 1.0 then r.uptime else 0.0}))
  |> sort(columns: ["id"])
''' % (node_filter, NOW_STALE)


def q_top(field, fn):
    return '''
from(bucket: "${bucket}")
  |> range(start: -5m)
  |> filter(fn: (r) => r._measurement == "system" and (r.object == "qemu" or r.object == "lxc") and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> %s()
  |> group()
  |> map(fn: (r) => ({guest: r.vmid + " " + %s, _value: float(v: r._value)}))
  |> filter(fn: (r) => r._value > 0.0)
  |> sort(columns: ["_value"], desc: true)
  |> limit(n: 10)
''' % (field, F_GNODES, fn, NAME)


def q_node_series(measurement, field, node_filter, fn="mean", label="node"):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "%s" and r.object == "nodes" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: %s, createEmpty: false)
  |> map(fn: (r) => ({_time: r._time, _value: r._value, %s: r.host}))
  |> group(columns: ["%s"])
''' % (RANGE, measurement, field, node_filter, fn, label, label)


def q_node_ram_pct():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "memory" and r.object == "nodes" and (r._field == "memused" or r._field == "memtotal"))
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> group(columns: ["host"])
  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({_time: r._time, _value: if r.memtotal > 0.0 then r.memused / r.memtotal else 0.0, node: r.host}))
  |> group(columns: ["node"])
''' % (RANGE, F_NODES)


PHYS_NIC = 'r.instance =~ /^(eth|en|nic|wl|ib)/'
VIRT_NIC = 'r.instance !~ /^(fwbr|fwpr|fwln|tap|veth|lo$)/'


def q_node_net_sum(field):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "nics" and r.object == "nodes" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> group(columns: ["host", "_time"])
  |> sum()
  |> group(columns: ["host"])
  |> sort(columns: ["_time"])
  |> map(fn: (r) => ({_time: r._time, _value: r._value * 8.0, node: r.host}))
  |> group(columns: ["node"])
''' % (RANGE, field, F_NODES, PHYS_NIC)


def q_node_ifaces(field):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "nics" and r.object == "nodes" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value * 8.0, iface: r.instance}))
  |> group(columns: ["iface"])
''' % (RANGE, field, F_NODE, VIRT_NIC)


def q_node_last(measurement, fields, extra_map, rng="-10m"):
    cond = " or ".join('r._field == "%s"' % f for f in fields)
    return '''
from(bucket: "${bucket}")
  |> range(start: %s)
  |> filter(fn: (r) => r._measurement == "%s" and r.object == "nodes" and (%s))
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> pivot(rowKey: ["host"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({%s}))
''' % (rng, measurement, cond, F_NODE, extra_map)


def q_node_online():
    return '''
from(bucket: "${bucket}")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "system" and r.object == "nodes" and r._field == "uptime")
  |> filter(fn: (r) => %s)
  |> last()
  |> map(fn: (r) => ({_time: r._time, _value: if %s then 0.0 else 1.0}))
''' % (F_NODE, NOW_STALE)


def q_node_field_ts(measurement, field, fn="mean", scale=None):
    sc = ""
    if scale:
        sc = '\n  |> map(fn: (r) => ({r with _value: r._value %s}))' % scale
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "%s" and r.object == "nodes" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: %s, createEmpty: false)%s
  |> map(fn: (r) => ({_time: r._time, _value: r._value}))
''' % (RANGE, measurement, field, F_NODE, fn, sc)


def q_node_rootfs_ts():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "blockstat" and r.object == "nodes" and (r._field == "used" or r._field == "blocks"))
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> group(columns: ["host"])
  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({_time: r._time, _value: if r.blocks > 0.0 then r.used / r.blocks else 0.0}))
''' % (RANGE, F_NODE)


def q_agent_rate(measurement, field, label_expr, label, factor=None):
    sc = ""
    if factor:
        sc = " %s" % factor
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "%s" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value%s, %s: %s}))
  |> group(columns: ["%s"])
''' % (RANGE, measurement, field, F_NODE, sc, label, label_expr, label)


def q_disk_busy():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "pg_disk" and r._field == "io_time_ms")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: if r._value > 1000.0 then 1.0 else r._value / 1000.0, disk: r.disk}))
  |> group(columns: ["disk"])
''' % (RANGE, F_NODE)


def q_disk_latency():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "pg_disk" and (r._field == "reads" or r._field == "writes" or r._field == "read_time_ms" or r._field == "write_time_ms"))
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> group(columns: ["disk"])
  |> pivot(rowKey: ["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({_time: r._time, disk: r.disk,
      _value: if r.reads + r.writes > 0.0 then (r.read_time_ms + r.write_time_ms) / (r.reads + r.writes) else 0.0}))
  |> group(columns: ["disk"])
''' % (RANGE, F_NODE)


def q_smart():
    return '''
from(bucket: "${bucket}")
  |> range(start: -24h)
  |> filter(fn: (r) => r._measurement == "pg_smart")
  |> filter(fn: (r) => %s)
  |> last()
  |> toFloat()
  |> group()
  |> pivot(rowKey: ["disk", "model", "type"], columnKey: ["_field"], valueColumn: "_value")
  |> sort(columns: ["disk"])
''' % F_NODE


def q_sensors(measurement, field):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "%s" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: mean, createEmpty: false)
  |> map(fn: (r) => ({_time: r._time, _value: r._value, sensor: r.device + " " + r.sensor}))
  |> group(columns: ["sensor"])
''' % (RANGE, measurement, field, F_NODE)


def q_zfs():
    return '''
from(bucket: "${bucket}")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "pg_zfs" and r._field != "health")
  |> filter(fn: (r) => %s)
  |> last()
  |> toFloat()
  |> group()
  |> pivot(rowKey: ["pool"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({pool: r.pool, healthy: r.healthy, size: r.size, alloc: r.alloc, free: r.free, cap: r.cap / 100.0, frag: r.frag / 100.0}))
''' % F_NODE


# Invite unique (variable guest = vmid)
F_GUEST = 'r.vmid == "${guest}"'


def q_guest_state():
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "system" and r._field == "status")
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> map(fn: (r) => ({_time: r._time, _value: if %s then 2.0 else if r._value == "running" then 1.0 else 0.0}))
''' % (F_GUEST, NOW_STALE)


def q_guest_info():
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "system" and r._field == "uptime")
  |> filter(fn: (r) => %s)
  |> last()
  |> group()
  |> map(fn: (r) => ({_value: (if r.object == "qemu" then "VM" else "CT") + " / " + r.nodename}))
''' % F_GUEST


def q_guest_last(fields, expr, extra_filter=""):
    cond = " or ".join('r._field == "%s"' % f for f in fields)
    return '''
from(bucket: "${bucket}")
  |> range(start: -10m)
  |> filter(fn: (r) => r._measurement == "system" and (%s))
  |> filter(fn: (r) => %s%s)
  |> last()
  |> toFloat()
  |> group()
  |> pivot(rowKey: ["vmid"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({%s}))
''' % (cond, F_GUEST, extra_filter, expr)


def q_guest_ts(field, fn="mean", scale=None):
    sc = ""
    if scale:
        sc = " %s" % scale
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: %s, createEmpty: false)
  |> map(fn: (r) => ({_time: r._time, _value: float(v: r._value)%s}))
''' % (RANGE, field, F_GUEST, fn, sc)


def q_guest_rate(field, scale=None):
    sc = ""
    if scale:
        sc = " %s" % scale
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value%s}))
''' % (RANGE, field, F_GUEST, sc)


def q_guest_drives(field):
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "blockstat" and r.object == "qemu" and r._field == "%s")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: last, createEmpty: false)
  |> derivative(unit: 1s, nonNegative: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value, drive: r.instance}))
  |> group(columns: ["drive"])
''' % (RANGE, field, F_GUEST)


def q_guest_timeline():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and r._field == "status")
  |> filter(fn: (r) => %s)
  |> map(fn: (r) => ({r with _value: if r._value == "running" then 1.0 else 0.0}))
  |> aggregateWindow(every: v.windowPeriod, fn: min, createEmpty: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value}))
''' % (RANGE, F_GUEST)


def q_all_guests_timeline():
    return '''
import "strings"
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and (r.object == "qemu" or r.object == "lxc") and r._field == "status")
  |> filter(fn: (r) => %s)
  |> map(fn: (r) => ({r with _value: if r._value == "running" then 1.0 else 0.0}))
  |> aggregateWindow(every: v.windowPeriod, fn: min, createEmpty: true)
  |> map(fn: (r) => ({_time: r._time, _value: r._value,
      guest: strings.repeat(v: " ", i: 10 - strings.strlen(v: r.vmid)) + r.vmid + " " + %s}))
  |> group(columns: ["guest"])
  |> sort(columns: ["_time"])
''' % (RANGE, F_GNODES, NAME)


def q_nodes_timeline():
    return '''
from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and r.object == "nodes" and r._field == "uptime")
  |> filter(fn: (r) => %s)
  |> aggregateWindow(every: v.windowPeriod, fn: count, createEmpty: true)
  |> duplicate(column: "_value", as: "seen")
  |> cumulativeSum(columns: ["seen"])
  |> filter(fn: (r) => r.seen > 0)
  |> map(fn: (r) => ({_time: r._time, _value: if r._value > 0 then 1.0 else 0.0, node: r.host}))
  |> group(columns: ["node"])
''' % (RANGE, F_NODES)


def q_availability():
    return '''
base = from(bucket: "${bucket}")
  |> %s
  |> filter(fn: (r) => r._measurement == "system" and (r.object == "qemu" or r.object == "lxc") and r._field == "status")
  |> filter(fn: (r) => %s)
running = base
  |> filter(fn: (r) => r._value == "running")
  |> count()
  |> group()
  |> map(fn: (r) => ({r with _field: "running"}))
total = base
  |> count()
  |> group()
  |> map(fn: (r) => ({r with _field: "total"}))
union(tables: [running, total])
  |> group()
  |> pivot(rowKey: ["object", "vmid", "nodename", "host"], columnKey: ["_field"], valueColumn: "_value")
  |> map(fn: (r) => ({
      type: if r.object == "qemu" then "VM" else "CT",
      id: int(v: r.vmid),
      name: r.host,
      node: r.nodename,
      availability: if exists r.running and r.total > 0 then float(v: r.running) / float(v: r.total) else 0.0}))
  |> sort(columns: ["availability", "id"])
''' % (RANGE, F_GNODES)


# ---------------------------------------------------------------------------
# Elements reutilises
# ---------------------------------------------------------------------------

def guests_table_panel(title, node_filter, h_desc=True):
    query = q_guests_table(node_filter)
    order = ["state", "type", "id", "name", "node", "cpu", "cpus", "ram", "ram_used", "ram_max",
             "disk", "disk_max", "uptime"]
    overrides = [
        col("state", t("col_state"), width=125, mappings=map_state(),
            cell={"type": "color-background", "mode": "basic"}),
        col("type", t("col_type"), width=55),
        col("id", t("col_id"), unit="none", width=70, decimals=0, links=guest_link()),
        col("name", t("col_name"), links=guest_link()),
        col("node", t("col_node"), width=130, links=node_link()),
        col("cpu", t("col_cpu"), unit="percentunit", width=150, gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("cpus", t("col_vcpu"), unit="none", width=55, decimals=0),
        col("ram", t("col_ram"), unit="percentunit", width=150, gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("ram_used", t("col_ram_used"), unit="bytes", width=125, decimals=1),
        col("ram_max", t("col_ram_max"), unit="bytes", width=125, decimals=1),
        col("disk", t("col_disk"), unit="percentunit", width=150, gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1,
            mappings=vmap([(-1, t("na"), "transparent")])),
        col("disk_max", t("col_disk_max"), unit="bytes", width=100, decimals=0),
        col("uptime", t("col_uptime"), unit="s", width=115, decimals=1, mappings=vmap([(0, t("na"), "text")])),
    ]
    return table(title, tgt(query), overrides, order, desc=t("guests_desc") if h_desc else "")


def storage_panels(d, node_filter, label_expr, single):
    d.add(bargauge(t("storage_usage"), tgt(q_storages_rows(node_filter, label_expr) +
                                           '  |> map(fn: (r) => ({storage: r.storage, _value: r._value}))\n')), 12, 8)
    q_tab = q_storages_rows(node_filter, label_expr) + \
        '  |> map(fn: (r) => ({storage: r.storage, type: r.type, used: r.used, avail: r.avail, total: r.total, pct: r._value}))\n'
    d.add(table(t("storage_table"), tgt(q_tab), [
        col("storage", t("col_storage")),
        col("type", t("col_type"), width=80),
        col("used", t("col_used"), unit="bytes", width=95, decimals=1),
        col("avail", t("col_free"), unit="bytes", width=95, decimals=1),
        col("total", t("col_total"), unit="bytes", width=95, decimals=1),
        col("pct", t("col_pct"), unit="percentunit", width=150, gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
    ], ["storage", "type", "used", "avail", "total", "pct"]), 12, 8)
    trend_label = label_expr if single else STORAGE_LABEL_TREND
    d.add(timeseries(t("storage_trend"), tgt(q_storage_trend(node_filter, trend_label)), "percentunit",
                     display_name="${__field.labels.storage}", soft_max=1, legend="table",
                     calcs=["lastNotNull", "max"], fill=0), 24, 8)


# ---------------------------------------------------------------------------
# Tableaux de bord
# ---------------------------------------------------------------------------

def build_overview():
    d = Dash("pg-overview", "t_overview", "d_overview", [var_ds(), var_bucket(), var_node(True)], "now-6h")

    d.add(stat(t("nodes"), tgt(q_count_nodes()), text_mode="value_and_name", order=["online", "offline"], overrides=[
        ov("online", [("displayName", t("online")), ("thresholds", th((None, GREEN)))]),
        ov("offline", [("displayName", t("offline")), ("thresholds", th((None, GREEN), (1, RED)))]),
    ]), 4, 5)
    for obj, key in (("qemu", "vms"), ("lxc", "cts")):
        d.add(stat(t(key), tgt(q_count_guests(obj)), text_mode="value_and_name", overrides=[
            ov("running", [("displayName", t("running")), ("thresholds", th((None, GREEN)))]),
            ov("stopped", [("displayName", t("stopped_pl")), ("thresholds", th((None, GREY)))]),
        ]), 4, 5)
    d.add(gauge(t("cpu_total"), tgt(q_cluster_cpu())), 4, 5)
    d.add(gauge(t("ram_total"), tgt(q_cluster_ram())), 4, 5)
    d.add(gauge(t("storage_max"), tgt(q_storage_max()), display_name="${__field.labels.storage}"), 4, 5)

    d.row(t("nodes"))
    d.add(table(t("nodes_table"), tgt(q_nodes_table()), [
        col("node", t("col_node"), links=node_link()),
        col("online", t("col_state"), width=120, mappings=map_online(), cell={"type": "color-background", "mode": "basic"}),
        col("cpu", t("col_cpu"), unit="percentunit", gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("cpus", t("col_cores"), unit="none", width=70, decimals=0),
        col("load", t("col_load"), unit="none", width=110, decimals=2),
        col("ram", t("col_ram"), unit="percentunit", gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("ram_total", t("col_ram_total"), unit="bytes", decimals=0, width=120),
        col("swap", t("col_swap"), unit="percentunit", gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("rootfs", t("col_rootfs"), unit="percentunit", gauge_cell=True, thresholds=TH_PCT, vmin=0, vmax=1, decimals=1),
        col("uptime", t("col_uptime"), unit="s", decimals=1, width=120, mappings=vmap([(0, t("na"), "text")])),
    ], ["node", "online", "cpu", "cpus", "load", "ram", "ram_total", "swap", "rootfs", "uptime"]), 24, 5)
    d.add(timeseries(t("cpu_by_node"), tgt(q_node_series("cpustat", "cpu", F_NODES)), "percentunit",
                     display_name="${__field.labels.node}", soft_max=1), 8, 8)
    d.add(timeseries(t("ram_by_node"), tgt(q_node_ram_pct()), "percentunit",
                     display_name="${__field.labels.node}", soft_max=1), 8, 8)
    d.add(timeseries(t("net_by_node"), [tgt(q_node_net_sum("receive"), "A"), tgt(q_node_net_sum("transmit"), "B")],
                     "bps", overrides=[
                         by_ref("A", [("displayName", "${__field.labels.node} " + t("rx"))]),
                         by_ref("B", [("displayName", "${__field.labels.node} " + t("tx"))] + neg_y()),
                     ], vmin=None), 8, 8)

    d.row(t("guests"))
    d.add(guests_table_panel(t("guests_table"), F_GNODES), 24, 13)
    d.add(bargauge(t("top_cpu"), tgt(q_top("cpu", "mean")), desc=t("top_cpu_desc")), 12, 9)
    d.add(bargauge(t("top_ram"), tgt(q_top("mem", "last")), unit="bytes", vmax=None,
                   thresholds=th((None, BLUE))), 12, 9)

    d.row(t("storage"))
    storage_panels(d, F_GNODES, STORAGE_LABEL_MULTI, single=False)
    return d.build()


def build_node():
    d = Dash("pg-node", "t_node", "d_node", [var_ds(), var_bucket(), var_node(False)], "now-6h")

    d.add(stat(t("state"), tgt(q_node_online()), mappings=map_online(), color_mode="background",
               thresholds=th((None, RED), (1, GREEN)), no_value=t("unknown")), 3, 5)
    d.add(stat(t("uptime"), tgt(q_node_last("system", ["uptime"], "_value: r.uptime")), unit="s", decimals=1), 3, 5)
    d.add(gauge(t("cpu"), tgt(q_node_last("cpustat", ["cpu"], "_value: r.cpu"))), 3, 5)
    d.add(gauge(t("ram"), tgt(q_node_last("memory", ["memused", "memtotal"],
                                         "_value: if r.memtotal > 0.0 then r.memused / r.memtotal else 0.0"))), 3, 5)
    d.add(gauge(t("swap"), tgt(q_node_last("memory", ["swapused", "swaptotal"],
                                          "_value: if r.swaptotal > 0.0 then r.swapused / r.swaptotal else 0.0"))), 3, 5)
    d.add(gauge(t("rootfs"), tgt(q_node_last("blockstat", ["used", "blocks"],
                                            "_value: if r.blocks > 0.0 then r.used / r.blocks else 0.0"))), 3, 5)
    d.add(stat(t("load"), tgt(q_node_last("cpustat", ["avg1", "avg5", "avg15", "cpus"],
                                         "avg1: r.avg1, avg5: r.avg5, avg15: r.avg15, cpus: r.cpus")),
               text_mode="value_and_name", decimals=2, order=["avg1", "avg5", "avg15", "cpus"], overrides=[
                   ov("avg1", [("displayName", "1 min")]),
                   ov("avg5", [("displayName", "5 min")]),
                   ov("avg15", [("displayName", "15 min")]),
                   ov("cpus", [("displayName", t("col_cores")), ("decimals", 0), ("thresholds", th((None, GREY)))]),
               ]), 6, 5)

    d.row(t("cpu_mem"))
    d.add(timeseries(t("cpu"), [tgt(q_node_field_ts("cpustat", "cpu"), "A"), tgt(q_node_field_ts("cpustat", "wait"), "B")],
                     "percentunit", soft_max=1, overrides=[
                         by_ref("A", [("displayName", t("cpu_usage"))]),
                         by_ref("B", [("displayName", t("iowait")), ("color", {"mode": "fixed", "fixedColor": ORANGE})]),
                     ]), 12, 8)
    d.add(timeseries(t("load"), [tgt(q_node_field_ts("cpustat", "avg1"), "A"), tgt(q_node_field_ts("cpustat", "avg5"), "B"),
                                 tgt(q_node_field_ts("cpustat", "avg15"), "C"), tgt(q_node_field_ts("cpustat", "cpus", "last"), "D")],
                     "none", decimals=2, overrides=[
                         by_ref("A", [("displayName", "1 min")]),
                         by_ref("B", [("displayName", "5 min")]),
                         by_ref("C", [("displayName", "15 min")]),
                         by_ref("D", [("displayName", t("cores_line"))] + dash_line(RED)),
                     ]), 12, 8)
    d.add(timeseries(t("ram"), [tgt(q_node_field_ts("memory", "memused"), "A"), tgt(q_node_field_ts("memory", "memtotal", "last"), "B"),
                                tgt(q_node_field_ts("memory", "arcsize"), "C"), tgt(q_node_field_ts("memory", "swapused"), "D")],
                     "bytes", overrides=[
                         by_ref("A", [("displayName", t("mem_used"))]),
                         by_ref("B", [("displayName", t("mem_total"))] + dash_line(RED)),
                         by_ref("C", [("displayName", t("arc")), ("color", {"mode": "fixed", "fixedColor": PURPLE})]),
                         by_ref("D", [("displayName", t("swap_used")), ("color", {"mode": "fixed", "fixedColor": ORANGE})]),
                     ]), 12, 8)
    d.add(timeseries(t("rootfs"), tgt(q_node_rootfs_ts()), "percentunit", display_name=t("rootfs"), soft_max=1), 12, 8)

    d.row(t("network"))
    d.add(timeseries(t("net_ifaces"), [tgt(q_node_ifaces("receive"), "A"), tgt(q_node_ifaces("transmit"), "B")], "bps",
                     legend="table", calcs=["mean", "max", "lastNotNull"], vmin=None, overrides=[
                         by_ref("A", [("displayName", "${__field.labels.iface} " + t("rx"))]),
                         by_ref("B", [("displayName", "${__field.labels.iface} " + t("tx"))] + neg_y()),
                     ]), 24, 11)

    d.row(t("node_storage"))
    storage_panels(d, F_GNODE, STORAGE_LABEL_SINGLE, single=True)

    d.row(t("agent_disks"))
    na = t("no_agent")
    d.add(timeseries(t("disk_tp"), [tgt(q_agent_rate("pg_disk", "read_bytes", "r.disk", "disk"), "A"),
                                    tgt(q_agent_rate("pg_disk", "write_bytes", "r.disk", "disk"), "B")],
                     "Bps", desc=t("agent_desc"), no_value=na, vmin=None, overrides=[
                         by_ref("A", [("displayName", "${__field.labels.disk} " + t("read"))]),
                         by_ref("B", [("displayName", "${__field.labels.disk} " + t("write"))] + neg_y()),
                     ]), 12, 8)
    d.add(timeseries(t("disk_busy"), tgt(q_disk_busy()), "percentunit", desc=t("disk_busy_desc"), no_value=na,
                     display_name="${__field.labels.disk}", soft_max=1), 12, 8)
    d.add(timeseries(t("disk_iops"), [tgt(q_agent_rate("pg_disk", "reads", "r.disk", "disk"), "A"),
                                      tgt(q_agent_rate("pg_disk", "writes", "r.disk", "disk"), "B")],
                     "iops", no_value=na, vmin=None, decimals=0, overrides=[
                         by_ref("A", [("displayName", "${__field.labels.disk} " + t("read"))]),
                         by_ref("B", [("displayName", "${__field.labels.disk} " + t("write"))] + neg_y()),
                     ]), 12, 8)
    d.add(timeseries(t("disk_lat"), tgt(q_disk_latency()), "ms", no_value=na, display_name="${__field.labels.disk}"), 12, 8)

    th_zero = th((None, GREEN), (1, RED))
    smart_order = ["disk", "model", "type", "passed", "temperature", "wear_used_pct", "power_on_hours",
                   "reallocated_sectors", "pending_sectors", "offline_uncorrectable", "reported_uncorrect",
                   "media_errors", "available_spare_pct", "crc_errors", "unsafe_shutdowns", "power_cycles"]
    smart = table(t("smart"), tgt(q_smart()), [
        col("disk", t("col_disk"), width=90),
        col("model", t("col_model")),
        col("type", t("col_type"), width=70),
        col("passed", t("col_health"), width=90, mappings=vmap([(1, t("ok"), GREEN), (0, t("fail"), RED)]),
            cell={"type": "color-background", "mode": "basic"}),
        col("temperature", t("col_temp"), unit="celsius", decimals=0, width=110,
            thresholds=th((None, GREEN), (50, ORANGE), (60, RED)), cell={"type": "color-text"}),
        col("wear_used_pct", t("col_wear"), unit="percent", decimals=0, gauge_cell=True,
            thresholds=th((None, GREEN), (70, ORANGE), (90, RED)), vmin=0, vmax=100),
        col("power_on_hours", t("col_hours"), unit="none", decimals=0),
        col("reallocated_sectors", t("col_realloc"), decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("pending_sectors", t("col_pending"), decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("offline_uncorrectable", t("col_uncorr") + " (198)", decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("reported_uncorrect", t("col_uncorr") + " (187)", decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("media_errors", t("col_media"), decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("available_spare_pct", t("col_spare"), unit="percent", decimals=0),
        col("crc_errors", t("col_crc"), decimals=0, thresholds=th_zero, cell={"type": "color-text"}),
        col("unsafe_shutdowns", t("col_unsafe"), decimals=0),
        col("power_cycles", "Power cycles", decimals=0),
    ], smart_order, desc=t("smart_desc") + " " + t("agent_desc"))
    d.add(smart, 24, 8)

    d.row(t("temps"))
    d.add(timeseries(t("temps"), tgt(q_sensors("pg_temp", "celsius")), "celsius", no_value=na, legend="table",
                     calcs=["lastNotNull", "max"], display_name="${__field.labels.sensor}", fill=0, vmin=None), 16, 11)
    d.add(timeseries(t("fans"), tgt(q_sensors("pg_fan", "rpm")), "rotrpm", no_value=na,
                     display_name="${__field.labels.sensor}", fill=0), 8, 11)
    d.add(table(t("zfs"), tgt(q_zfs()), [
        col("pool", t("col_pool")),
        col("healthy", t("col_health"), width=110, mappings=vmap([(1, "ONLINE", GREEN), (0, t("fail"), RED)]),
            cell={"type": "color-background", "mode": "basic"}),
        col("cap", t("col_pct"), unit="percentunit", gauge_cell=True, thresholds=th((None, GREEN), (0.8, ORANGE), (0.9, RED)),
            vmin=0, vmax=1, decimals=1),
        col("size", t("col_size"), unit="bytes", decimals=1),
        col("alloc", t("col_used"), unit="bytes", decimals=1),
        col("free", t("col_free"), unit="bytes", decimals=1),
        col("frag", t("col_frag"), unit="percentunit", decimals=0),
    ], ["pool", "healthy", "cap", "size", "alloc", "free", "frag"], desc=t("zfs_desc")), 24, 5)

    d.row(t("guests_on_node"))
    d.add(guests_table_panel(t("guests_on_node"), F_GNODE, h_desc=False), 24, 12)
    return d.build()


def build_guest():
    d = Dash("pg-guest", "t_guest", "d_guest", [var_ds(), var_bucket(), var_guest()], "now-6h")
    d.add(stat(t("state"), tgt(q_guest_state()), mappings=map_state(), color_mode="background",
               thresholds=th((None, GREY)), no_value=t("unknown")), 3, 5)
    d.add(stat(t("type_node"), tgt(q_guest_info()), fields="/^_value$/", color_mode="none"), 4, 5)
    d.add(stat(t("uptime"), tgt(q_guest_last(["uptime"], "_value: r.uptime")), unit="s", decimals=1,
               mappings=vmap([(0, t("na"), "text")])), 3, 5)
    d.add(gauge(t("cpu"), tgt(q_guest_last(["cpu"], "_value: r.cpu"))), 3, 5)
    d.add(stat(t("vcpu"), tgt(q_guest_last(["cpus"], "_value: r.cpus")), decimals=0), 2, 5)
    d.add(gauge(t("ram"), tgt(q_guest_last(["mem", "maxmem"], "_value: if r.maxmem > 0.0 then r.mem / r.maxmem else 0.0"))), 3, 5)
    d.add(stat(t("ram"), tgt(q_guest_last(["mem", "maxmem"], "used: r.mem, max: r.maxmem")), unit="bytes",
               decimals=1, text_mode="value_and_name", overrides=[
                   ov("used", [("displayName", t("mem_used"))]),
                   ov("max", [("displayName", t("mem_alloc")), ("thresholds", th((None, GREY)))]),
               ]), 3, 5)
    d.add(gauge(t("disk"), tgt(q_guest_last(["disk", "maxdisk"], "_value: if r.maxdisk > 0.0 then r.disk / r.maxdisk else 0.0",
                                            ' and r.object == "lxc"')), no_value=t("vm_na")), 3, 5)

    d.add(timeseries(t("cpu"), tgt(q_guest_ts("cpu")), "percentunit", display_name=t("cpu_usage"), soft_max=1), 12, 8)
    d.add(timeseries(t("ram"), [tgt(q_guest_ts("mem"), "A"), tgt(q_guest_ts("maxmem", "last"), "B"),
                                tgt(q_guest_ts("memhost"), "C")], "bytes", overrides=[
        by_ref("A", [("displayName", t("mem_used"))]),
        by_ref("B", [("displayName", t("mem_alloc"))] + dash_line(RED)),
        by_ref("C", [("displayName", t("mem_host")), ("color", {"mode": "fixed", "fixedColor": PURPLE})]),
    ]), 12, 8)
    d.add(timeseries(t("disk_io"), [tgt(q_guest_rate("diskread"), "A"), tgt(q_guest_rate("diskwrite"), "B")], "Bps",
                     vmin=None, overrides=[
                         by_ref("A", [("displayName", t("read"))]),
                         by_ref("B", [("displayName", t("write"))] + neg_y()),
                     ]), 12, 8)
    d.add(timeseries(t("net_io"), [tgt(q_guest_rate("netin", "* 8.0"), "A"), tgt(q_guest_rate("netout", "* 8.0"), "B")], "bps",
                     vmin=None, overrides=[
                         by_ref("A", [("displayName", t("rx"))]),
                         by_ref("B", [("displayName", t("tx"))] + neg_y()),
                     ]), 12, 8)
    d.add(timeseries(t("pressure"), [tgt(q_guest_ts("pressurecpusome"), "A"), tgt(q_guest_ts("pressureiosome"), "B"),
                                     tgt(q_guest_ts("pressurememorysome"), "C")], "percent",
                     desc=t("pressure_desc"), no_value=t("pressure_na"), fill=0, overrides=[
                         by_ref("A", [("displayName", t("p_cpu"))]),
                         by_ref("B", [("displayName", t("p_io"))]),
                         by_ref("C", [("displayName", t("p_mem"))]),
                     ]), 12, 8)
    d.add(timeseries(t("drives"), [tgt(q_guest_drives("rd_bytes"), "A"), tgt(q_guest_drives("wr_bytes"), "B")], "Bps",
                     no_value=t("drives_na"), vmin=None, overrides=[
                         by_ref("A", [("displayName", "${__field.labels.drive} " + t("read"))]),
                         by_ref("B", [("displayName", "${__field.labels.drive} " + t("write"))] + neg_y()),
                     ]), 12, 8)
    p = timeline(t("state_history"), tgt(q_guest_timeline()), vmap([(1, t("running"), GREEN), (0, t("stopped"), RED)]))
    p["fieldConfig"]["defaults"]["displayName"] = t("state")
    d.add(p, 24, 4)
    return d.build()


def build_availability():
    d = Dash("pg-availability", "t_avail", "d_avail", [var_ds(), var_bucket(), var_node(True)], "now-7d")
    p = timeline(t("nodes_history"), tgt(q_nodes_timeline()), map_online(), interval="1m")
    p["fieldConfig"]["defaults"]["displayName"] = "${__field.labels.node}"
    d.add(p, 24, 5)
    p = timeline(t("guests_history"), tgt(q_all_guests_timeline()),
                 vmap([(1, t("running"), GREEN), (0, t("stopped"), RED)]), interval="1m")
    p["fieldConfig"]["defaults"]["displayName"] = "${__field.labels.guest}"
    d.add(p, 24, 16)
    q = q_availability()
    d.add(table(t("avail_table"), tgt(q), [
        col("type", t("col_type"), width=60),
        col("id", t("col_id"), unit="none", decimals=0, width=70, links=guest_link()),
        col("name", t("col_name"), links=guest_link()),
        col("node", t("col_node")),
        col("availability", t("col_avail"), unit="percentunit", decimals=2, gauge_cell=True, vmin=0, vmax=1,
            thresholds=th((None, RED), (0.95, ORANGE), (0.99, GREEN))),
    ], ["type", "id", "name", "node", "availability"], desc=t("avail_desc")), 24, 10)
    return d.build()


def main():
    global LANG
    builders = [("01-overview.json", build_overview), ("02-node.json", build_node),
                ("03-guest.json", build_guest), ("04-availability.json", build_availability)]
    for lang in ("fr", "en"):
        LANG = lang
        out = os.path.join(ROOT, "dashboards", lang)
        os.makedirs(out, exist_ok=True)
        for name, fn in builders:
            with open(os.path.join(out, name), "w", encoding="utf-8", newline="\n") as f:
                json.dump(fn(), f, ensure_ascii=False, indent=2)
                f.write("\n")
    print("OK: dashboards/fr and dashboards/en")


if __name__ == "__main__":
    main()
