# Linkwarden

## Fichiers

- Modèle : `install/services/linkwarden/docker-compose.yml`
- Installation : `/opt/selfhosted/linkwarden`
- Port : `127.0.0.1:3001`
- Domaine : `links.example.fr`

Le projet contient uniquement l'application. Elle utilise la base
`linkwarden` de l'instance PostgreSQL partagée.

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock linkwarden
sudo vps-compose linkwarden config --quiet
sudo vps-compose linkwarden up -d
sudo vps-compose linkwarden logs --tail=100
curl -fsSI http://127.0.0.1:3001
```

Créer le premier compte depuis l'interface HTTPS, puis fermer les
inscriptions dans `install/config/vps.env` :

```bash
LINKWARDEN_DISABLE_REGISTRATION=true
```

Réappliquer et recréer l'application :

```bash
sudo sh install/scripts/vps-install.sh --phase services
sudo vps-compose linkwarden up -d
```

## Données

```text
/opt/selfhosted/linkwarden/data
/opt/selfhosted/databases/postgres
```
