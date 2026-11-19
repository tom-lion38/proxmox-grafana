#!/usr/bin/env python3
"""Execute chaque requete des tableaux de bord via l'API de Grafana et signale
les erreurs et les panneaux vides. Outil de developpement.

    GRAFANA_URL=http://<ip>:3000 GRAFANA_PASSWORD=... python3 tools/check-dashboards.py [fr|en] [periode]

La periode vaut now-1h par defaut. Les variables sont remplacees ainsi :
node = premier noeud trouve, guest = une VM et un conteneur en marche.
"""

import base64
import glob
import json
import os
import re
import sys
import urllib.request

URL = os.environ.get("GRAFANA_URL", "http://127.0.0.1:3000").rstrip("/")
PASSWORD = os.environ["GRAFANA_PASSWORD"]
LANG = sys.argv[1] if len(sys.argv) > 1 else "fr"
FROM = sys.argv[2] if len(sys.argv) > 2 else "now-1h"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS = {"type": "influxdb", "uid": "proxmox-grafana-influxdb"}
AUTH = "Basic " + base64.b64encode(("admin:" + PASSWORD).encode()).decode()


def ds_query(query, frm=FROM, interval_ms=30000):
    body = {"from": frm, "to": "now", "queries": [
        {"refId": "A", "datasource": DS, "query": query, "intervalMs": interval_ms, "maxDataPoints": 1000}]}
    req = urllib.request.Request(URL + "/api/ds/query", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": AUTH})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        try:
            res = json.load(e)
        except Exception:
            return None, "HTTP %s" % e.code
    a = res.get("results", {}).get("A", {})
    if a.get("error"):
        return None, a["error"]
    return a.get("frames", []), None


def values_of(frames):
    out = []
    for f in frames:
        for col in f.get("data", {}).get("values", []):
            out.extend(col)
    return out


def first_values(query):
    frames, err = ds_query(query, "now-24h")
    if err:
        raise SystemExit("variable query failed: " + err)
    return [v for v in values_of(frames) if isinstance(v, str)]


def interpolate(q, var):
    q = q.replace("${bucket}", "proxmox")
    q = q.replace("${node:regex}", ".*")
    q = q.replace("${node}", var.get("node", ""))
    q = q.replace("${guest}", var.get("guest", ""))
    return q


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "dashboards", LANG, "*.json")))
    node_dash = json.load(open(files[1], encoding="utf-8"))
    guest_dash = json.load(open(files[2], encoding="utf-8"))
    node_q = [v for v in node_dash["templating"]["list"] if v["name"] == "node"][0]["query"]
    guest_q = [v for v in guest_dash["templating"]["list"] if v["name"] == "guest"][0]["query"]
    nodes = first_values(interpolate(node_q, {}))
    guests = first_values(interpolate(guest_q, {}))
    print("nodes:", nodes)
    print("guests:", len(guests), guests[:5])
    if not nodes or not guests:
        raise SystemExit("no node or guest found")
    # une VM et un conteneur
    probe = ('from(bucket: "proxmox") |> range(start: -5m) |> filter(fn: (r) => r._measurement == "system" '
             'and r._field == "uptime" and r._value > 0.0) |> last() |> group() '
             '|> map(fn: (r) => ({_value: r.object + ":" + r.vmid}))')
    frames, _ = ds_query(probe)
    running = values_of(frames or [])
    picks = {}
    for item in running:
        if isinstance(item, str) and ":" in item:
            obj, vmid = item.split(":", 1)
            picks.setdefault(obj, vmid)
    print("probe guests:", picks)

    problems = 0
    for f in files:
        dash = json.load(open(f, encoding="utf-8"))
        runs = [{"node": nodes[0]}]
        if "guest" in [v["name"] for v in dash["templating"]["list"]]:
            runs = [{"guest": vmid, "label": obj} for obj, vmid in picks.items()]
        for var in runs:
            for p in dash["panels"]:
                if p["type"] == "row":
                    continue
                for tg in p.get("targets", []):
                    q = interpolate(tg["query"], var)
                    frames, err = ds_query(q)
                    tag = "%s / %s [%s]%s" % (dash["uid"], p["title"], tg["refId"],
                                             (" (" + var.get("label", "") + ")") if var.get("label") else "")
                    if err:
                        problems += 1
                        print("ERROR  ", tag, "->", err[:300])
                        continue
                    rows = 0
                    for fr in frames:
                        vals = fr.get("data", {}).get("values", [])
                        if vals:
                            rows += len(vals[0])
                    status = "ok    " if rows else "EMPTY "
                    if not rows:
                        problems += 1
                    names = []
                    for fr in frames[:4]:
                        fields = fr.get("schema", {}).get("fields", [])
                        names.append(",".join(
                            (fd.get("name", "") + ("" if not fd.get("labels") else str(fd["labels"])))
                            for fd in fields if fd.get("name") not in ("_time", "Time")))
                    print(status, tag, "frames=%d rows=%d" % (len(frames), rows), "|", " ; ".join(names)[:220])
    print("problems:", problems)


if __name__ == "__main__":
    main()
