# proxmox-grafana

Supervision complète d'un serveur Proxmox VE avec Grafana et InfluxDB, installée en une seule commande.

English version: [README.en.md](README.en.md)

Le script crée un conteneur Debian dédié, y installe InfluxDB 2 et Grafana, demande à Proxmox d'y envoyer ses mesures et ajoute des tableaux de bord prêts à l'emploi. Il pose quelques questions simples pendant l'installation, avec une réponse par défaut à chaque fois : on peut tout valider avec Entrée.

## Ce qui est surveillé

- les nœuds : processeur, charge, mémoire, swap, cache ZFS, disque système, réseau par interface, temps depuis le démarrage, en ligne ou non ;
- chaque VM et chaque conteneur : en marche ou arrêté, processeur, mémoire, disque, lectures et écritures, trafic réseau, pression (attente de ressources), disques de chaque VM ;
- les stockages : remplissage actuel et évolution, stockages partagés comptés une seule fois ;
- les disques physiques (avec l'agent) : débit, occupation, opérations par seconde, temps de réponse ;
- la santé des disques (avec l'agent) : état SMART, température, usure des SSD et NVMe, secteurs réalloués ou en attente, erreurs ;
- les températures et ventilateurs (avec l'agent) ;
- les pools ZFS (avec l'agent) : état, remplissage, fragmentation ;
- l'historique marche / arrêt de tout ce qui précède et la disponibilité sur la période choisie.

Tout s'adapte tout seul : nombre de nœuds, de VM, de conteneurs, de disques, noms des interfaces et des stockages.

## Installation

Dans le shell d'un nœud Proxmox (interface web, nœud, Shell, ou SSH en root) :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tom-lion38/proxmox-grafana/main/install.sh)"
```

Ou avec git :

```bash
git clone https://github.com/tom-lion38/proxmox-grafana.git
cd proxmox-grafana
bash install.sh
```

Il faut :

- Proxmox VE 7, 8 ou 9 ;
- un accès à Internet depuis le nœud et depuis le conteneur (téléchargement du modèle Debian et des paquets officiels InfluxDB et Grafana) ;
- environ 2 Go de mémoire et 20 Go de disque libres.

L'installation dure 3 à 6 minutes.

## Les questions posées

En mode simple (par défaut) :

1. la langue (français ou anglais) ;
2. le stockage du conteneur, s'il y a plusieurs choix ;
3. le pont réseau, s'il y en a plusieurs ;
4. l'adresse IP du conteneur : automatique (DHCP) ou fixe ;
5. le mot de passe de Grafana : généré ou choisi ;
6. l'installation de l'agent sur le nœud (et sur les autres nœuds d'un cluster) ;
7. un récapitulatif avant de lancer.

Le mode avancé permet aussi de choisir le numéro du conteneur, son nom, ses cœurs, sa mémoire, la taille du disque, le VLAN et la durée de conservation des mesures (30 jours, 90 jours, 180 jours, 1 an ou pour toujours).

Avec le DHCP, pensez à réserver l'adresse du conteneur dans votre box ou votre routeur. Si elle change, Proxmox ne peut plus envoyer ses mesures.

## Après l'installation

Le script affiche l'adresse de Grafana, l'utilisateur `admin` et le mot de passe. Ces informations sont aussi écrites dans `/root/proxmox-grafana.txt` sur le nœud (lisible par root seulement).

Les tableaux de bord sont dans le dossier « Proxmox » de Grafana. La vue d'ensemble s'ouvre directement à la connexion. Les graphiques se remplissent dès la première minute.

## Les tableaux de bord

| Tableau | Contenu |
| --- | --- |
| Proxmox - Vue d'ensemble | Nœuds en ligne, VM et conteneurs en marche ou arrêtés, processeur et mémoire du cluster, liste de tous les invités, les plus chargés, stockages |
| Proxmox - Nœud | Détail d'un nœud : processeur, charge, mémoire, réseau, stockages, disques physiques, SMART, températures, ventilateurs, ZFS, invités du nœud |
| Proxmox - VM et conteneurs | Détail d'une VM ou d'un conteneur, historique marche / arrêt |
| Proxmox - Disponibilité | Frise marche / arrêt des nœuds et des invités, pourcentage de disponibilité |

Un clic sur le nom d'une VM, d'un conteneur ou d'un nœud ouvre son détail.

Les tableaux installés sont protégés contre les modifications (ils sont remplacés à chaque mise à jour). Pour les personnaliser, utilisez « Enregistrer sous » dans Grafana : la copie vous appartient.

## L'agent

Proxmox envoie lui-même l'état et la charge des nœuds, des VM, des conteneurs et des stockages. Il ne mesure pas les disques physiques, les températures, l'état SMART ni les pools ZFS : c'est le rôle de l'agent.

L'agent est un script bash (`/usr/local/bin/proxmox-grafana-agent`) lancé par systemd. Il n'installe aucun paquet et lit seulement `/proc`, `/sys`, `smartctl` et `zpool`, déjà présents sur Proxmox. Il envoie ses mesures toutes les 15 secondes, et l'état SMART toutes les 10 minutes sans réveiller les disques en veille.

Pour voir ce qu'il envoie, sans rien envoyer :

```bash
proxmox-grafana-agent --print
```

## Cluster

L'envoi des mesures de Proxmox est réglé pour tout le cluster : tous les nœuds envoient leurs mesures dès l'installation. Pour l'agent, le script propose de l'installer aussi sur les autres nœuds (par SSH entre nœuds). Pour l'ajouter plus tard sur un nœud, lancez le script sur ce nœud et choisissez « Ajouter l'agent sur ce nœud ».

## Mettre à jour, désinstaller

Relancez la même commande : un menu propose l'installation, la mise à jour des tableaux de bord et de l'agent, l'ajout de l'agent et la désinstallation. Ou directement :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tom-lion38/proxmox-grafana/main/install.sh)" -- --update-dashboards
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tom-lion38/proxmox-grafana/main/install.sh)" -- --uninstall
```

La désinstallation retire l'envoi des mesures et l'agent. Elle demande avant de supprimer le conteneur et son historique.

## Installation sans questions

Pour un déploiement automatique, ajoutez `--unattended` et réglez ce qu'il faut avec des variables (toutes facultatives) :

```bash
PG_LANG=fr PG_IP=192.168.0.240/24 PG_GW=192.168.0.1 PG_RETENTION=180 \
  bash install.sh --install --unattended
```

| Variable | Rôle | Défaut |
| --- | --- | --- |
| `PG_LANG` | `fr` ou `en` | selon la langue du système |
| `PG_CTID` | numéro du conteneur | premier libre |
| `PG_HOSTNAME` | nom du conteneur | `proxmox-grafana` |
| `PG_STORAGE` | stockage du conteneur | `local-lvm` ou `local-zfs`, sinon le plus libre |
| `PG_TEMPLATE_STORAGE` | stockage des modèles | `local` |
| `PG_DISK` | disque en Go | `20` |
| `PG_RAM` | mémoire en Mo | `2048` |
| `PG_CORES` | cœurs | `2` |
| `PG_BRIDGE` | pont réseau | `vmbr0` |
| `PG_VLAN` | numéro de VLAN | aucun |
| `PG_IP` | `dhcp` ou `a.b.c.d/nn` | `dhcp` |
| `PG_GW` | passerelle (adresse fixe) | celle du nœud |
| `PG_RETENTION` | conservation en jours, `0` pour toujours | `90` |
| `PG_GRAFANA_PASSWORD` | mot de passe de Grafana | généré |
| `PG_AGENT` | installer l'agent (`1` ou `0`) | `1` |
| `PG_AGENT_ALL_NODES` | agent sur tous les nœuds du cluster | `1` |
| `PG_DESTROY_CT` | supprimer le conteneur à la désinstallation | `0` |

## Ce que le script modifie sur Proxmox

- un conteneur LXC non privilégié, avec le tag `proxmox-grafana` ;
- un serveur de mesures nommé `proxmox-grafana` (Centre de données, Serveur de métriques). Ceux qui existent déjà ne sont pas touchés ;
- l'agent : `/usr/local/bin/proxmox-grafana-agent`, le service `proxmox-grafana-agent` et `/etc/proxmox-grafana/` ;
- `/root/proxmox-grafana.txt` et le journal `/var/log/proxmox-grafana.log`.

Rien d'autre. En cas d'erreur pendant l'installation, le script propose de supprimer ce qu'il a créé. Si la connexion est coupée, il le supprime tout seul : il suffit de relancer.

## Sécurité

- Grafana (port 3000) et InfluxDB (port 8086) sont faits pour rester sur le réseau local. Ne les ouvrez pas sur Internet.
- Proxmox et l'agent écrivent avec un jeton qui ne peut qu'écrire dans le bucket `proxmox`. Grafana lit avec un jeton qui ne peut que lire.
- Les mots de passe sont tirés au hasard. Celui d'InfluxDB est dans `/root/proxmox-grafana.txt`.
- Les paquets viennent des dépôts officiels d'InfluxData (clé vérifiée) et de Grafana. Les statistiques d'usage envoyées par InfluxDB et Grafana sont désactivées.

## En cas de problème

- Le journal complet est dans `/var/log/proxmox-grafana.log`.
- « Pas de données » partout : vérifiez que le nœud peut joindre le conteneur sur le port 8086 (pare-feu, VLAN, adresse changée par le DHCP).
- Rien dans les parties « agent » : `systemctl status proxmox-grafana-agent` et `journalctl -u proxmox-grafana-agent`.
- Pas de températures : certaines machines virtuelles ou certaines cartes mères n'exposent aucun capteur.
- Le conteneur n'obtient pas d'adresse : sans serveur DHCP sur ce réseau, choisissez une adresse fixe.

## Modifier les tableaux de bord

Les fichiers de `dashboards/fr` et `dashboards/en` sont générés par `tools/build-dashboards.py` (une seule définition pour les deux langues) :

```bash
python3 tools/build-dashboards.py
```

`tools/check-dashboards.py` exécute chaque requête via l'API de Grafana et signale les erreurs et les panneaux vides.

## Licence

MIT, voir [LICENSE](LICENSE).
