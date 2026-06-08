# Services Docker

Chaque sous-répertoire correspond à un projet Docker Compose indépendant.
L'installateur copie uniquement les services listés dans `SERVICES`.

Les bases sont fournies par le projet partagé `install/databases` :

- MariaDB pour Davis, FreshRSS et l'hébergement web ;
- PostgreSQL pour Linkwarden et Tiny Tiny RSS.

Les fichiers `.env` réels sont générés depuis :

- `install/config/vps.env` pour les domaines et versions ;
- `install/config/secrets.env` pour les mots de passe et secrets.

Ils sont installés avec le mode `0600` et ne doivent jamais être ajoutés à
Git.

Commande commune après installation :

```bash
sudo vps-compose databases up -d --wait
sudo vps-image-lock NOM_DU_SERVICE
sudo vps-compose NOM_DU_SERVICE config
sudo vps-compose NOM_DU_SERVICE up -d
sudo vps-compose NOM_DU_SERVICE logs --tail=100
```

`vps-image-lock` résout les tags en digests `sha256` dans
`docker-compose.lock.yml`. `vps-compose` charge automatiquement ce verrou.
