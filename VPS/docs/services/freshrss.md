# FreshRSS

## Fichiers

- Modèle : `install/services/freshrss/docker-compose.yml`
- Installation : `/opt/selfhosted/freshrss`
- Port : `127.0.0.1:3003`
- Domaine : `freshrss.example.fr`

## Premier démarrage

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock freshrss
sudo vps-compose freshrss config --quiet
sudo vps-compose freshrss up -d
sudo vps-compose freshrss logs --tail=100
curl -fsSI http://127.0.0.1:3003
```

Dans l'assistant web, utiliser :

```text
Type     : PostgreSQL
Hôte     : postgres
Port     : 5432
Base     : freshrss
Compte   : freshrss
Mot passe: valeur FRESHRSS_DB_PASSWORD du fichier de secrets
```

Ne pas afficher le fichier de secrets dans une capture ou un journal.

## Données

```text
/opt/selfhosted/freshrss/data
/opt/selfhosted/freshrss/extensions
/opt/selfhosted/databases/postgres
```
