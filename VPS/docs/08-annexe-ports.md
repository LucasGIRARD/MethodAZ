# Annexe : référentiel des ports réseau

## Objectif

Fournir un aide-mémoire des ports standards ou couramment utilisés, puis
documenter séparément la stratégie d'exposition retenue pour ce VPS.

Un port associé à un service indique une valeur habituelle, pas une garantie :
la configuration réelle du service et les règles du pare-feu restent la source
de vérité.

## Périmètre

Cette annexe se veut exhaustive pour les besoins courants d'un administrateur
système : administration, réseau, web, messagerie, transfert, annuaires,
supervision, bases de données, conteneurs, virtualisation, VPN, voix et outils
de développement.

Elle ne recopie pas les milliers d'attributions du registre IANA. Pour un port
rare, propriétaire ou inconnu, le registre IANA reste la référence exhaustive.

Un port absent des tableaux de cette annexe ne doit jamais être considéré
automatiquement comme libre.

## Plages de ports

| Plage | Désignation IANA | Disponibilité |
| ---: | --- | --- |
| `0` | Réservé | Non libre |
| `1-1023` | Ports système | Attribués, non attribués ou réservés selon le port ; ne pas les supposer libres |
| `1024-49151` | Ports utilisateur ou enregistrés | Attribués, non attribués ou réservés selon le port ; vérifier le registre IANA |
| `49152-65535` | Ports dynamiques ou privés | Jamais attribués par l'IANA ; utilisables localement lorsqu'ils sont disponibles |

Le registre officiel est maintenu par l'[IANA](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.xhtml).

La version exploitable par un programme est disponible au
[format CSV](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.csv).

## Signification de « libre »

Le mot « libre » peut désigner trois situations différentes :

| État | Signification | Peut être utilisé ? |
| --- | --- | --- |
| **Non attribué par l'IANA** | Le port système ou utilisateur est disponible pour une future attribution officielle | Usage local possible, mais l'IANA peut l'attribuer ultérieurement |
| **Dynamique ou privé** | Le port appartient à `49152-65535` et ne sera pas attribué par l'IANA | Oui, pour un usage local ou temporaire, sans garantie qu'un numéro précis soit disponible |
| **Libre sur la machine** | Aucun processus n'écoute actuellement sur ce port et le système ne l'a pas réservé | Oui à cet instant, sous réserve du pare-feu, de Docker et des plages éphémères |

Un port peut donc être non attribué par l'IANA mais déjà occupé localement. À
l'inverse, un port attribué à un autre service peut être techniquement libre
sur la machine, mais son détournement crée de la confusion et des risques de
compatibilité.

Les ports `49152-65535` sont les seuls que ce référentiel puisse marquer
globalement comme **privés et non attribués par l'IANA**. Ils ne sont cependant
pas tous libres à chaque instant : le système d'exploitation les utilise aussi
comme ports sources éphémères pour les connexions sortantes.

## Choisir un port privé

Pour un service local ou expérimental :

1. Privilégier un port de la plage privée `49152-65535`.
2. Vérifier la plage éphémère réellement configurée sur le système.
3. Vérifier que le port n'est pas déjà en écoute.
4. Vérifier les publications Docker et les règles du pare-feu.
5. Documenter l'usage local sans présenter ce numéro comme un standard.

La RFC 6335 précise qu'un logiciel ne doit pas supposer qu'un numéro précis de
la plage dynamique sera toujours disponible. Pour un service permanent partagé
publiquement, une attribution IANA ou un port standard existant reste
préférable.

### Vérification sous Debian/Linux

Plage de ports éphémères configurée :

```bash
cat /proc/sys/net/ipv4/ip_local_port_range
```

Ports actuellement en écoute :

```bash
sudo ss -lntup
```

Vérification ciblée, en remplaçant `PORT` :

```bash
sudo ss -lntup | grep -E ":PORT\\b"
sudo lsof -nP -iTCP:PORT -sTCP:LISTEN
sudo lsof -nP -iUDP:PORT
```

Publications Docker :

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

### Vérification sous Windows

Plages dynamiques :

```powershell
netsh int ipv4 show dynamicport tcp
netsh int ipv4 show dynamicport udp
netsh int ipv6 show dynamicport tcp
netsh int ipv6 show dynamicport udp
```

Ports en écoute :

```powershell
Get-NetTCPConnection -State Listen
Get-NetUDPEndpoint
```

ICMP, utilisé notamment par `ping`, ne repose ni sur TCP ni sur UDP et
n'utilise donc pas de numéro de port.

## Services historiques et diagnostic

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `1` | TCP/UDP | TCPMUX | Multiplexeur historique de services TCP |
| `7` | TCP/UDP | Echo | Renvoie les données reçues, à désactiver |
| `9` | TCP/UDP | Discard | Ignore les données reçues |
| `13` | TCP/UDP | Daytime | Service historique de date et heure |
| `17` | TCP/UDP | Quote of the Day | Service historique |
| `19` | TCP/UDP | Chargen | Générateur de caractères, risque d'amplification |
| `37` | TCP/UDP | Time | Ancien protocole de temps |
| `43` | TCP | WHOIS | Consultation d'informations d'enregistrement |
| `70` | TCP | Gopher | Protocole documentaire historique |
| `79` | TCP | Finger | Informations sur les utilisateurs, déconseillé |
| `113` | TCP | Ident | Identification historique d'une connexion |
| `194` | TCP | IRC | Messagerie instantanée IRC |

Les services Echo, Chargen, Finger et Ident ne doivent normalement pas être
activés sur un serveur moderne exposé à Internet.

## Administration et accès distant

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `22` | TCP | SSH | Administration distante sécurisée |
| `22` | TCP | SFTP / SCP | Transfert de fichiers à travers SSH |
| `23` | TCP | Telnet | Non chiffré, à ne pas exposer |
| `49` | TCP/UDP | TACACS | Authentification d'équipements réseau |
| `512` | TCP | rexec | Ancienne exécution distante non chiffrée |
| `513` | TCP | rlogin | Ancienne connexion distante non chiffrée |
| `514` | TCP | rsh | Ancien shell distant non chiffré |
| `623` | UDP | IPMI / RMCP | Administration hors bande de serveurs |
| `992` | TCP | Telnet sur TLS | Variante chiffrée historique |
| `3389` | TCP/UDP | RDP | Bureau à distance Windows |
| `5900` | TCP | VNC | Bureau à distance, souvent à protéger par VPN ou tunnel SSH |
| `5985` | TCP | WinRM HTTP | Administration distante Windows |
| `5986` | TCP | WinRM HTTPS | Administration distante Windows sur TLS |
| `8006` | TCP | Proxmox VE | Interface web par défaut |
| `9090` | TCP | Cockpit | Port par défaut de l'interface d'administration Cockpit |
| `10000` | TCP | Webmin | Interface web par défaut |
| `16509` | TCP | libvirt | Administration distante de machines virtuelles |

Telnet, rexec, rlogin et rsh transmettent les échanges sans protection
moderne. SSH doit être préféré pour toute administration distante.

## Transfert de fichiers

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `20` | TCP | FTP-data | Canal de données FTP actif |
| `21` | TCP | FTP | Canal de commande FTP |
| `22` | TCP | SFTP / SCP | Transfert chiffré via SSH |
| `69` | UDP | TFTP | Protocole simple sans authentification |
| `115` | TCP | SFTP historique | Simple File Transfer Protocol, différent du SFTP sur SSH |
| `445` | TCP | SMB/CIFS | Partage de fichiers Windows |
| `515` | TCP | LPD/LPR | Impression réseau historique |
| `548` | TCP | AFP | Partage de fichiers Apple historique |
| `631` | TCP/UDP | IPP | Impression réseau |
| `989` | TCP | FTPS-data | Données FTP sur TLS implicite |
| `990` | TCP | FTPS | Commandes FTP sur TLS implicite |
| `873` | TCP | rsync | Synchronisation de fichiers |
| `2049` | TCP/UDP | NFS | Partage de fichiers Unix/Linux |
| `3260` | TCP | iSCSI | Accès réseau à un stockage bloc |

FTP et TFTP ne doivent pas être utilisés sur Internet sans protection
complémentaire. SFTP est généralement le choix le plus simple.

## Web et proxy

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `80` | TCP | HTTP | Trafic web non chiffré |
| `443` | TCP | HTTPS | HTTP sur TLS |
| `443` | UDP | HTTP/3 | HTTP sur QUIC |
| `1080` | TCP | SOCKS | Proxy générique |
| `3128` | TCP | Squid | Proxy HTTP courant |
| `8000` | TCP | HTTP alternatif | Fréquent pour les serveurs de développement |
| `8008` | TCP | HTTP alternatif | Fréquent pour les applications |
| `8080` | TCP | HTTP alternatif | Fréquent pour les applications et les proxys |
| `8081` | TCP | HTTP alternatif | Fréquent pour une seconde application |
| `8443` | TCP | HTTPS alternatif | Fréquent pour les consoles d'administration |
| `8888` | TCP | HTTP alternatif | Fréquent pour Jupyter et les outils de développement |
| `9000` | TCP | Application / FastCGI | Usage dépendant du produit |
| `9443` | TCP | HTTPS alternatif | Fréquent pour les consoles d'administration |

Les ports `8000`, `8008`, `8080`, `8081`, `8443`, `8888`, `9000` et `9443`
sont des conventions fréquentes. Plusieurs produits différents peuvent les
utiliser.

## Messagerie

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `25` | TCP | SMTP | Échange entre serveurs de messagerie |
| `110` | TCP | POP3 | Réception sans TLS implicite |
| `143` | TCP | IMAP | Réception sans TLS implicite |
| `4190` | TCP | ManageSieve | Gestion des filtres Sieve |
| `465` | TCP | Soumission SMTP TLS | TLS implicite |
| `563` | TCP | NNTPS | Usenet sur TLS |
| `587` | TCP | Soumission SMTP | Envoi authentifié par un client |
| `993` | TCP | IMAPS | IMAP sur TLS |
| `995` | TCP | POP3S | POP3 sur TLS |
| `119` | TCP | NNTP | Usenet sans TLS implicite |

Le port `25` sert principalement au transport entre serveurs. Un client de
messagerie utilise normalement `587` ou `465` pour envoyer un message.

## DNS, adressage et temps

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `53` | TCP/UDP | DNS | Résolution et transferts DNS |
| `67` | UDP | DHCP serveur | Attribution des adresses IPv4 |
| `68` | UDP | DHCP client | Réception des paramètres IPv4 |
| `88` | TCP/UDP | Kerberos | Authentification centralisée |
| `123` | UDP | NTP | Synchronisation de l'heure |
| `135` | TCP/UDP | Microsoft RPC | Localisation des services RPC Windows |
| `179` | TCP | BGP | Échange de routes entre systèmes autonomes |
| `427` | TCP/UDP | SLP | Découverte de services |
| `464` | TCP/UDP | Kerberos kpasswd | Changement de mot de passe Kerberos |
| `500` | UDP | IKE / ISAKMP | Négociation IPsec |
| `520` | UDP | RIP | Routage dynamique IPv4 |
| `521` | UDP | RIPng | Routage dynamique IPv6 |
| `546` | UDP | DHCPv6 client | Réception des paramètres IPv6 |
| `547` | UDP | DHCPv6 serveur | Attribution des paramètres IPv6 |
| `4500` | UDP | IPsec NAT-T | IPsec à travers la traduction d'adresses |
| `5353` | UDP | mDNS | Résolution locale multicast |
| `5355` | TCP/UDP | LLMNR | Résolution locale, surtout sous Windows |
| `853` | TCP | DNS sur TLS | Résolution DNS chiffrée |

## Authentification et contrôle d'accès

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `49` | TCP/UDP | TACACS | Authentification des équipements réseau |
| `88` | TCP/UDP | Kerberos | Authentification centralisée |
| `389` | TCP/UDP | LDAP | Annuaire et authentification |
| `464` | TCP/UDP | Kerberos kpasswd | Changement de mot de passe |
| `636` | TCP | LDAPS | LDAP sur TLS |
| `1645` | UDP | RADIUS historique | Ancien port d'authentification |
| `1646` | UDP | RADIUS historique | Ancien port de comptabilité |
| `1812` | UDP | RADIUS Authentication | Authentification réseau |
| `1813` | UDP | RADIUS Accounting | Comptabilité réseau |

Les ports `1645` et `1646` sont encore rencontrés sur d'anciens équipements,
mais `1812` et `1813` sont les ports normalement utilisés.

## Supervision et journaux

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `161` | UDP | SNMP | Interrogation des équipements |
| `162` | UDP | SNMP Trap | Notifications SNMP |
| `514` | UDP | Syslog | Journaux réseau non chiffrés |
| `2055` | UDP | NetFlow | Export de flux réseau, valeur courante |
| `4739` | TCP/UDP | IPFIX | Export normalisé de flux réseau |
| `5666` | TCP | NRPE | Exécution distante de contrôles Nagios |
| `6514` | TCP | Syslog sur TLS | Journaux réseau chiffrés |
| `8125` | UDP | StatsD | Réception de métriques |
| `9090` | TCP | Prometheus | Interface et API par défaut, conflit possible avec Cockpit |
| `9093` | TCP | Alertmanager | Interface et API par défaut |
| `9100` | TCP | JetDirect / Node Exporter | Impression ou métriques Prometheus selon le produit |
| `9115` | TCP | Blackbox Exporter | Sonde Prometheus, valeur par défaut |
| `10050` | TCP | Agent Zabbix | Collecte de métriques |
| `10051` | TCP | Serveur Zabbix | Réception des métriques |

## Annuaires et partage de fichiers

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `111` | TCP/UDP | rpcbind | Correspondance des services RPC |
| `137` | UDP | NetBIOS Name Service | Ancien réseau Windows |
| `138` | UDP | NetBIOS Datagram | Ancien réseau Windows |
| `139` | TCP | NetBIOS Session | Ancien partage Windows |
| `389` | TCP/UDP | LDAP | Service d'annuaire |
| `445` | TCP | SMB/CIFS | Partage de fichiers Windows |
| `636` | TCP | LDAPS | LDAP sur TLS |
| `749` | TCP/UDP | Kerberos administration | Administration Kerberos |
| `2049` | TCP/UDP | NFS | Partage de fichiers Unix/Linux |
| `3268` | TCP | Catalogue global Active Directory | Requêtes LDAP globales |
| `3269` | TCP | Catalogue global Active Directory TLS | Requêtes globales chiffrées |

SMB, rpcbind et NFS ne doivent généralement pas être exposés directement à
Internet.

## Bases de données et caches

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `1433` | TCP | Microsoft SQL Server | Base de données |
| `1434` | UDP | SQL Server Browser | Découverte des instances |
| `1521` | TCP | Oracle Database | Base de données |
| `2483` | TCP | Oracle Database | Connexion Oracle sans TLS |
| `2484` | TCP | Oracle Database TLS | Connexion Oracle sur TLS |
| `3050` | TCP | Firebird | Base de données |
| `5432` | TCP | PostgreSQL | Base de données |
| `6379` | TCP | Redis | Cache et base clé-valeur |
| `7199` | TCP | Cassandra JMX | Administration et supervision |
| `7474` | TCP | Neo4j HTTP | Interface HTTP |
| `7687` | TCP | Neo4j Bolt | Protocole client |
| `9042` | TCP | Cassandra CQL | Connexions clientes |
| `9200` | TCP | Elasticsearch HTTP | API HTTP |
| `9300` | TCP | Elasticsearch transport | Communications internes du cluster |
| `11211` | TCP/UDP | Memcached | Cache distribué |
| `27017` | TCP | MongoDB | Base de données |

Ces ports doivent rester sur un réseau privé, un VPN ou un réseau Docker
interne. Ils ne doivent pas être publiés directement sur Internet.

## Messagerie applicative et objets connectés

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `1883` | TCP | MQTT | Messagerie pour objets connectés sans TLS |
| `4222` | TCP | NATS | Connexions clientes |
| `5671` | TCP | AMQP sur TLS | Messagerie AMQP chiffrée |
| `5672` | TCP | AMQP | RabbitMQ et autres courtiers AMQP |
| `8883` | TCP | MQTT sur TLS | Messagerie MQTT chiffrée |
| `9092` | TCP | Apache Kafka | Connexions clientes, valeur courante |
| `61613` | TCP | STOMP | Messagerie STOMP |
| `61616` | TCP | ActiveMQ OpenWire | Protocole natif courant |

## Conteneurs et orchestration

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `2375` | TCP | API Docker | Non chiffrée, ne jamais exposer publiquement |
| `2376` | TCP | API Docker TLS | À limiter strictement même avec TLS |
| `2379` | TCP | etcd client | API cliente etcd |
| `2380` | TCP | etcd pair | Réplication entre membres etcd |
| `4789` | UDP | VXLAN | Réseaux superposés de conteneurs |
| `5000` | TCP | Registre Docker | Port courant d'un registre privé |
| `6443` | TCP | API Kubernetes | API du plan de contrôle |
| `10250` | TCP | kubelet | API du kubelet |
| `10257` | TCP | kube-controller-manager | Point de contrôle sécurisé |
| `10259` | TCP | kube-scheduler | Point de contrôle sécurisé |
| `30000-32767` | TCP/UDP | Kubernetes NodePort | Plage par défaut des services NodePort |

Les API Docker, etcd, kubelet et Kubernetes sont des cibles sensibles. Elles
doivent rester sur un réseau d'administration privé et utiliser une
authentification forte.

## Virtualisation et gestion d'infrastructure

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `902` | TCP/UDP | VMware | Console et trafic d'administration selon le produit |
| `903` | TCP | VMware | Console distante historique |
| `8006` | TCP | Proxmox VE | Interface web |
| `9090` | TCP | Cockpit | Administration Linux |
| `10000` | TCP | Webmin | Administration web |
| `16509` | TCP | libvirt | API distante |
| `16992` | TCP | Intel AMT HTTP | Administration hors bande |
| `16993` | TCP | Intel AMT HTTPS | Administration hors bande sur TLS |
| `16994` | TCP | Intel AMT redirection | Redirection distante |
| `16995` | TCP | Intel AMT redirection TLS | Redirection distante chiffrée |

## VPN et tunnels

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `500` | UDP | IKE / IPsec | Négociation du tunnel |
| `1080` | TCP | SOCKS | Proxy ou tunnel applicatif |
| `1194` | TCP/UDP | OpenVPN | Port par défaut courant |
| `1701` | UDP | L2TP | Généralement combiné à IPsec |
| `1723` | TCP | PPTP | Ancien VPN, déconseillé |
| `4500` | UDP | IPsec NAT-T | IPsec derrière NAT |
| `51820` | UDP | WireGuard | Port par défaut courant |

## Voix, vidéo et temps réel

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `554` | TCP/UDP | RTSP | Contrôle de diffusion multimédia |
| `1720` | TCP | H.323 | Signalisation voix et vidéo |
| `3478` | TCP/UDP | STUN / TURN | Traversée de NAT |
| `5060` | TCP/UDP | SIP | Signalisation sans TLS |
| `5061` | TCP | SIP sur TLS | Signalisation chiffrée |
| `5349` | TCP/UDP | TURN sur TLS/DTLS | Relais multimédia chiffré |
| `16384-32767` | UDP | RTP / RTCP | Plage courante, dépend du produit |

La plage RTP n'est pas universelle. Elle doit être confirmée dans la
configuration du serveur de téléphonie ou de visioconférence.

## Gestion de code et outils de développement

| Port | Protocole | Service | Remarque |
| ---: | :---: | --- | --- |
| `3000` | TCP | Grafana / application web | Port Grafana par défaut et convention de développement |
| `3690` | TCP | Subversion | Protocole `svn://` |
| `4000` | TCP | Application web | Convention courante de développement |
| `5000` | TCP | Application web / registre | Convention utilisée par plusieurs produits |
| `8000` | TCP | Application web | Convention courante de développement |
| `8080` | TCP | Application web | Convention courante de développement |
| `8888` | TCP | Jupyter | Interface web courante |
| `9418` | TCP | Git | Protocole natif `git://` non chiffré |
| `29418` | TCP | Gerrit SSH | Accès Git par SSH à Gerrit |

Ces ports sont souvent choisis par convention et ne désignent pas un produit
unique. Une application de développement ne doit pas être exposée à Internet
sans authentification et proxy inverse.

## Protocoles IP sans numéro de port

Certains flux réseau ne passent pas par TCP ou UDP. Ils utilisent un numéro de
protocole IP et non un numéro de port.

| Protocole IP | Numéro | Usage |
| --- | ---: | --- |
| ICMP | `1` | Diagnostic IPv4, notamment `ping` |
| IGMP | `2` | Gestion des groupes multicast IPv4 |
| GRE | `47` | Tunnels GRE et certains VPN |
| ESP | `50` | Chiffrement IPsec |
| AH | `51` | Authentification IPsec |
| ICMPv6 | `58` | Diagnostic et fonctionnement essentiel d'IPv6 |

Bloquer ICMPv6 sans discernement peut casser IPv6, notamment la découverte des
voisins et la détection de la MTU du chemin.

## Convention privée de ce VPS

Les services d'administration qui doivent être joignables depuis Internet,
notamment SSH, utilisent une plage personnalisée commençant par `**000`.

```text
**000  Premier port d'administration personnalisé, utilisé pour SSH
**001  Port d'administration suivant, si nécessaire
**002  Port d'administration suivant, si nécessaire
```

Les étoiles font partie du masque documentaire. Ces valeurs ne sont pas des
numéros de ports valides et ne doivent jamais être exécutées telles quelles.
La valeur réelle est conservée hors du dépôt public.

Changer le port SSH réduit le bruit des robots automatisés, mais ne remplace
pas l'authentification par clé, le pare-feu, Fail2ban et la désactivation de la
connexion root.

## Exposition retenue pour ce VPS

| Port ou adresse | Service | Exposition |
| --- | --- | --- |
| `80/tcp` | Nginx en conteneur, réseau hôte | Public |
| `443/tcp` | Nginx en conteneur, réseau hôte | Public |
| `**000/tcp` | SSH | Public mais filtré, valeur réelle masquée |
| `127.0.0.1:3000` | Grafana en conteneur | Local, publié par Nginx en HTTPS |
| `127.0.0.1:9090` | Prometheus en conteneur | Local uniquement |
| `127.0.0.1:9100` | Node Exporter en conteneur | Local uniquement |
| `127.0.0.1:3001` | Linkwarden | Local uniquement |
| `127.0.0.1:3002` | Davis | Local uniquement |
| `127.0.0.1:3003` | FreshRSS | Local uniquement |
| `127.0.0.1:3004` | Tiny Tiny RSS | Local uniquement |
| `127.0.0.1:3005` | Kill the Newsletter | Local uniquement |
| `127.0.0.1:3006` | Apache/PHP | Local uniquement |

Les ports internes `5432`, `8000` et `9000` restent dans les réseaux
Docker et ne sont pas publiés sur l'hôte.

## Vérification

```bash
sudo ss -tulpn
sudo iptables -L INPUT -n -v --line-numbers
sudo ip6tables -L INPUT -n -v --line-numbers
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```
