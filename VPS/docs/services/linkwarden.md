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

Pour créer automatiquement le premier compte pendant l'installation, renseigner
dans `install/config/vps.env` :

```bash
LINKWARDEN_DISABLE_REGISTRATION=true
LINKWARDEN_BOOTSTRAP_USER=lucas
LINKWARDEN_BOOTSTRAP_NAME=Lucas
```

Et dans `install/config/secrets.env` :

```bash
LINKWARDEN_BOOTSTRAP_PASSWORD=mot_de_passe_long
```

Quand `LINKWARDEN_DISABLE_REGISTRATION=true` et que
`LINKWARDEN_BOOTSTRAP_USER` est non vide, l'installateur démarre temporairement
Linkwarden avec les inscriptions ouvertes, crée ce compte via l'API locale,
puis réapplique la configuration finale avec les inscriptions fermées. Si le
compte existe déjà, la phase reste rejouable.

`LINKWARDEN_BOOTSTRAP_USER` doit contenir uniquement des minuscules, chiffres,
`_` ou `-`, avec 3 à 50 caractères. `LINKWARDEN_BOOTSTRAP_PASSWORD` doit faire
au moins 8 caractères.

Sans bootstrap, créer le premier compte depuis l'interface HTTPS, puis fermer
les inscriptions dans `install/config/vps.env` et réappliquer :

```bash
sudo sh install/scripts/vps-install.sh --phase services
sudo vps-compose linkwarden up -d
```

## Données

```text
/opt/selfhosted/linkwarden/data
/opt/selfhosted/databases/postgres
```

## Dépannage

### Prisma `P1013` sur `DATABASE_URL`

Si Linkwarden redémarre en boucle avec :

```text
Error: P1013: The provided database string is invalid. invalid port number in database URL.
```

le mot de passe PostgreSQL contient probablement un caractère réservé dans une
URL (`#`, `@`, `:`, `/`, `%`, etc.). L'installateur encode désormais le mot de
passe dans `LINKWARDEN_DATABASE_URL`.

Reprendre dans cet ordre :

```bash
sudo vps-install --phase databases
sudo vps-install --phase services
sudo vps-compose linkwarden up -d --force-recreate
sudo vps-compose linkwarden logs --tail=100 app
```

Ne pas écrire soi-même `DATABASE_URL` avec le mot de passe brut. La base
PostgreSQL reçoit le mot de passe réel, tandis que l'application reçoit une URL
avec le mot de passe percent-encodé.
