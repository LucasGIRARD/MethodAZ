# Conventions des services Docker

## Règles communes

- Un projet Compose indépendant par application.
- Aucun `container_name`, afin de conserver la gestion native de Compose.
- Ports HTTP publiés uniquement sur `127.0.0.1`.
- Deux moteurs SQL partagés, sans port publié.
- Un réseau SQL interne distinct par application.
- Un utilisateur et une base distincts par application.
- Versions d'images définies dans `.env`.
- Secrets distincts, générés aléatoirement et stockés dans un `.env` en mode
  `0600`.
- Journaux applicatifs écrits dans stdout/stderr et collectés par journald.
- Données applicatives sous le répertoire du service et données SQL sous
  `/opt/selfhosted/databases`.
- Mise à jour service par service après sauvegarde.

## Contrôle avant démarrage

```bash
cd /opt/selfhosted/NOM_DU_SERVICE
sudo test "$(stat -c '%a' .env)" = 600
sudo docker compose config --quiet
sudo vps-image-lock NOM_DU_SERVICE
```

La sortie de `docker compose config` contient les variables interpolées. Ne
pas la copier dans un ticket ou un journal public, car elle peut révéler les
secrets.

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-compose NOM_DU_SERVICE up -d
sudo docker compose ps
sudo docker compose logs --tail=100
```

Ne passer au service suivant qu'après validation de son état et de son port
local.

## Sauvegarde

Sauvegarder ensemble :

- le fichier Compose ;
- le `.env` secret par un canal chiffré ;
- les répertoires de données ;
- les dumps cohérents MariaDB et PostgreSQL produits par `vps-backup`.

Une copie brute d'une base active n'est pas automatiquement une sauvegarde
cohérente.
