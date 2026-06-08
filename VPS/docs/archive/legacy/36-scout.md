# Scan CVE alternative avec Docker Scout

Docker Scout analyse les images et fournit des rapports de vulnérabilités, avec notamment la commande `docker scout cves`.

Si le plugin est disponible :

```Bash
docker scout version
```

Scanner une image :

```Bash
docker scout cves caddy:2
docker scout cves freshrss/freshrss:latest
docker scout cves ghcr.io/linkwarden/linkwarden:latest
```

Pour ce serveur, garde Trivy comme outil principal car il est simple à automatiser sans dépendre d’un compte Docker.