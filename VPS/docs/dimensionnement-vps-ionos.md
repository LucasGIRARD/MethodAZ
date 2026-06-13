# Dimensionnement du VPS IONOS

## Recommandation

Pour la sélection complète du dépôt, retenir **au minimum 4 Go de RAM** avec
2 Go de swap. Un VPS de 2 Go convient seulement à une sélection réduite de
services.

Au 7 juin 2026, l'offre VPS+ française d'IONOS présente notamment :

| Offre | Ressources | Usage conseillé ici |
| --- | --- | --- |
| VPS S+ | 2 vCores, 2 Go RAM, 80 Go NVMe | Debian, Nginx, Grafana léger et un ou deux services |
| VPS M+ | 4 vCores, 4 Go RAM, 120 Go NVMe | Minimum pour les cinq services prévus, trafic personnel |
| VPS L+ | 6 vCores, 8 Go RAM, 240 Go NVMe | Tous les services avec marge, Loki ou cAdvisor ponctuels |

Le VPS XS de 1 Go encore visible sur certaines anciennes pages IONOS n'est
pas adapté à cette architecture.

## Pourquoi 2 Go ne suffisent pas

La sélection complète contient :

- cinq applications ;
- une instance PostgreSQL partagée ;
- Nginx et Certbot ;
- Grafana, Prometheus et Node Exporter ;
- Debian, Docker, SSH et Fail2ban.

Même avec une faible fréquentation, les pointes produites par Linkwarden, les
applications, une sauvegarde ou une mise à jour peuvent saturer 2 Go. Le swap évite
certains arrêts brutaux, mais ne remplace pas la RAM et dégrade fortement la
réactivité lorsqu'il est utilisé durablement.

## Profil léger retenu

Le profil par défaut conserve le confort utile :

- Grafana, Prometheus et Node Exporter restent actifs ;
- collecte Prometheus toutes les 30 secondes ;
- rétention Prometheus de 7 jours et 512 Mio maximum ;
- Loki, Alloy et cAdvisor désactivés par défaut ;
- journald limité à 250 Mio et 14 jours ;
- connexions et caches des bases adaptés à un usage personnel ;
- sauvegarde locale limitée à 7 jours ;
- travaux lourds exécutés avec une priorité CPU et disque réduite.

## Profils de limites mémoire

La variable suivante sélectionne les limites maximales par conteneur :

```bash
RESOURCE_PROFILE=VPS_4G
```

Deux profils sont disponibles :

| Profil | Usage | Exemples de limites |
| --- | --- | --- |
| `VPS_2G` | Un ou deux services applicatifs | SQL `320m`, Linkwarden `384m`, Grafana et Prometheus `256m` |
| `VPS_4G` | Sélection complète à faible trafic | SQL `512m`, Linkwarden `768m`, Grafana `384m`, Prometheus `512m` |

Les limites empêchent un processus isolé de consommer toute la RAM. Leur
somme peut dépasser la mémoire physique : elles ne rendent pas la sélection
complète compatible avec 2 Go et ne remplacent pas la surveillance du swap et
des événements OOM.

Chaque variable peut être surchargée dans `vps.env`, par exemple :

```bash
LINKWARDEN_MEMORY_LIMIT=640m
POSTGRES_MEMORY_LIMIT=448m
```

Ce qui n'est pas sacrifié :

- HTTPS et renouvellement automatique ;
- tableaux de bord système ;
- dumps cohérents des bases ;
- Fail2ban, pare-feu et rotation des journaux ;
- verrouillage et audit des images Docker.

## Choix pratique

### VPS S+ avec 2 Go

Limiter `SERVICES` à un ou deux services. Conserver :

```bash
ENABLE_LOGS=false
ENABLE_CONTAINER_METRICS=false
SWAP_SIZE=2G
RESOURCE_PROFILE=VPS_2G
```

Linkwarden est généralement le service applicatif le plus exigeant de cette
liste. Sur 2 Go, éviter de le cumuler avec les cinq applications.

### VPS M+ avec 4 Go

La sélection complète peut fonctionner pour un usage personnel à faible
trafic avec le profil léger. Surveiller pendant les premières semaines :

```bash
RESOURCE_PROFILE=VPS_4G
```

```bash
free -h
docker stats --no-stream
vmstat 1 10
```

Une utilisation régulière du swap ou des événements OOM impose de passer à
8 Go ou de retirer un service. IONOS indique qu'une montée en gamme est
possible, mais qu'un retour vers une offre plus petite nécessite une migration
manuelle.

### VPS L+ avec 8 Go

C'est le choix sans compromis pour faire tourner tous les services et activer
ponctuellement Loki ou cAdvisor. Il n'est pas nécessaire pour une pile réduite.

## Stockage et sauvegarde

Une sauvegarde conservée uniquement sur le VPS ne protège pas contre la perte
du serveur. Les sept sauvegardes locales servent aux restaurations rapides ;
au moins une copie chiffrée doit sortir du VPS.

IONOS propose des images de serveur et un Cloud Backup optionnel. Une image
facilite un retour arrière, mais ne remplace pas les dumps applicatifs ni une
copie externe indépendante.

## Références

- [IONOS France : offres VPS](https://www.ionos.fr/serveurs/vps)
- [IONOS : mise à niveau d'un VPS](https://www.ionos.com/help/server-cloud-infrastructure/general-information-vps/important-information-on-upgrading-your-vps/)
