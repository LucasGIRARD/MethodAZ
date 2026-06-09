# Sécurité des images Docker

## Conclusion

Le socle est correctement cloisonné pour un petit VPS : les ports applicatifs
écoutent sur `127.0.0.1`, les bases utilisent des réseaux internes et
`no-new-privileges` est appliqué à tous les services.

Le niveau reste **bon avec réserves** tant que les digests sont verrouillés
avant démarrage et que cAdvisor reste désactivé. Sans ces deux mesures, le
risque devient significatif.

## Résultats de l'audit

| Niveau | Élément | Mesure retenue |
| --- | --- | --- |
| Élevé | cAdvisor accède à `/var/run/docker.sock`, dont l'API reste modifiable même avec un montage `:ro` | Profil `containers` et flag `ENABLE_CONTAINER_METRICS=false` par défaut |
| Élevé | Un tag Docker peut être remplacé dans un registre | Génération de `docker-compose.lock.yml` avec un digest `sha256` |
| Élevé | L'ancienne procédure exécutait `aquasec/trivy:latest` avec le socket Docker | Procédure retirée ; audit avec le binaire hôte Docker Scout |
| Moyen | Les secrets passés par variables sont visibles par root via `docker inspect` | Fichiers `.env` en mode `0600`, accès Docker limité aux administrateurs |
| Moyen | Un digest garantit l'immuabilité, pas l'identité de l'éditeur | Utiliser uniquement les registres officiels et contrôler les avis de publication |
| Moyen | La mutualisation SQL augmente l'impact d'une panne moteur | Deux moteurs seulement, comptes séparés, réseaux Docker distincts et dumps nocturnes |
| Moyen | Node Exporter lit la racine et utilise le PID de l'hôte | Port local, racine en lecture seule, capacités supprimées |
| Moyen | Alloy lit journald et les journaux Nginx | Désactivable avec `ENABLE_LOGS=false`, montages en lecture seule |
| Faible | Un emballement de processus peut épuiser le VPS | `pids_limit` et `mem_limit` appliqués aux conteneurs |
| Faible | Un processus actif peut ne plus répondre | Healthchecks applicatifs et métrique des conteneurs défaillants |

L'appartenance au groupe `docker` doit être considérée comme un accès root.
Ne jamais donner ce groupe à un compte applicatif ou SFTP.

## Versions vérifiées

Vérification effectuée le 7 juin 2026.

| Image | Version retenue |
| --- | --- |
| Linkwarden | `v2.14.1` |
| Davis | `4.4.0` |
| FreshRSS | `1.29.1` |
| Tiny Tiny RSS | digest multiarchitecture relevé le 9 juin 2026 |
| PostgreSQL | `16.14-alpine3.23` |
| MariaDB | `11.8.8-noble` |
| PHP Apache | base officielle `8.4.21-apache-trixie`, extensions MySQL et OPcache construites localement |
| Nginx | `1.30.2-alpine-slim` |
| Grafana | `13.0.1-security-01` |
| Prometheus | `v3.12.0-distroless` |
| Node Exporter | `v1.11.1-distroless` |
| cAdvisor | `v0.55.1` |
| Loki | `3.7.2` |
| Alloy | `v1.16.1` |
| Alpine | `3.22.4` |
| Certbot | `v5.6.0` |

Les images `distroless` réduisent les outils disponibles dans le conteneur.
Elles ne remplacent ni l'analyse des CVE ni la mise à jour régulière.

## Verrouiller les images

Avant le premier démarrage d'un service :

```bash
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden up -d
```

Pour tous les projets déjà installés :

```bash
sudo vps-image-lock all
```

Le verrou est écrit dans le projet :

```text
/opt/selfhosted/NOM_DU_SERVICE/docker-compose.lock.yml
```

Ce fichier contient les références `image@sha256:...`. Il doit être conservé
avec les sauvegardes. Une mise à jour nécessite de régénérer volontairement le
verrou, puis de recréer le service.

Pour `web`, le verrou fixe le digest de l'image PHP officielle utilisée par le
`Dockerfile`, puis l'image applicative locale est reconstruite. L'audit porte
sur cette image finale.

## Analyser les CVE

Installer manuellement une version précise de Docker Scout selon la procédure
officielle, puis lancer :

```bash
sudo vps-image-audit
less /var/log/server-checks/docker-images/cve-report.txt
```

Le script analyse uniquement les images présentes dans le stockage Docker
local. Il ne monte pas le socket Docker dans un autre conteneur. Son code de
sortie est `2` si une vulnérabilité critique ou élevée est trouvée et `1` en
cas d'erreur.

Éviter l'installation directe avec `curl | sh`. Télécharger une publication
précise, contrôler les informations de l'asset, puis installer le binaire
comme plugin Docker.

L'analyse ne prouve pas qu'une image est saine. Elle doit être complétée par :

- la lecture des avis de sécurité de l'éditeur ;
- la vérification de la provenance du registre ;
- la suppression des images et services inutilisés ;
- un test applicatif après chaque mise à jour.

## Références

- [Docker Compose : verrouillage des digests](https://docs.docker.com/reference/cli/docker/compose/config/)
- [Docker Scout : installation](https://docs.docker.com/scout/install/)
- [Docker Scout : commande cves](https://docs.docker.com/reference/cli/docker/scout/cves/)
- [Avis officiel sur l'incident Trivy](https://github.com/aquasecurity/trivy/discussions/10425)
- [Linkwarden : versions](https://github.com/linkwarden/linkwarden/releases)
- [Davis : versions](https://github.com/tchapi/davis/releases)
- [FreshRSS : versions](https://github.com/FreshRSS/FreshRSS/releases)
- [Prometheus : versions](https://github.com/prometheus/prometheus/releases)
- [Node Exporter : versions](https://github.com/prometheus/node_exporter/releases)
- [cAdvisor : versions](https://github.com/google/cadvisor/releases)
- [Grafana : versions](https://github.com/grafana/grafana/releases)
- [Loki : versions](https://github.com/grafana/loki/releases)
- [Alloy : versions](https://github.com/grafana/alloy/releases)
- [PostgreSQL : politique de versions](https://www.postgresql.org/support/versioning/)
- [Images officielles PostgreSQL](https://hub.docker.com/_/postgres)
- [Images officielles MariaDB](https://hub.docker.com/_/mariadb)
- [Images officielles PHP](https://hub.docker.com/_/php)
- [Images officielles Nginx](https://hub.docker.com/_/nginx)
