# Bases de données partagées

Ce projet exécute uniquement deux images officielles :

- MariaDB pour Davis, FreshRSS et l'hébergement web ;
- PostgreSQL pour Linkwarden et Tiny Tiny RSS.

Aucun port SQL n'est publié sur l'hôte. Chaque application utilise son propre
réseau Docker interne `vps-db-*` et dispose de sa base, de son utilisateur et
de son mot de passe.

```bash
sudo vps-image-lock databases
sudo vps-compose databases up -d --wait
sudo vps-compose databases ps
```

Les scripts sous `docker-entrypoint-initdb.d` ne sont exécutés que lors de la
création initiale des répertoires de données. L'installateur les rejoue ensuite
en mode idempotent afin de réconcilier les utilisateurs et mots de passe
applicatifs.
