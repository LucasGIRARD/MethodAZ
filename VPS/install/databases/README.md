# Bases de données partagées

Ce projet exécute une seule image officielle PostgreSQL pour Linkwarden,
Davis, FreshRSS, Tiny Tiny RSS et l'hébergement web.

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
