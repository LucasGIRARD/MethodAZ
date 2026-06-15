# Kill the Newsletter

## Fichiers

- Modèle : `install/services/kill-newsletter/docker-compose.yml`
- Installation : `/opt/selfhosted/kill-newsletter`
- Port HTTP : `127.0.0.1:3005`
- Domaine : `newsletter.example.fr`

L'installateur clone automatiquement le dépôt amont, sélectionne la révision
verrouillée par `KILL_NEWSLETTER_REF`, puis construit l'image avec le
Dockerfile fourni par ce projet. Il suffit d'ajouter `kill-newsletter` à
`SERVICES` dans `install/config/vps.env` et de lancer la phase applicative :

```bash
sudo vps-install --phase services
```

Le conteneur démarre uniquement le serveur HTTP sur le port interne `8000`.
Il n'est pas activé par défaut. La réception de courriels depuis Internet
nécessite une conception séparée pour SMTP, MX, SPF, DKIM, DMARC, DNS inverse
et réputation IP. Ne pas ouvrir un port SMTP à partir de ce modèle.

Pour changer de version, modifier `KILL_NEWSLETTER_REF` vers un commit
explicitement choisi, puis rejouer la phase `services`.

## Données

```text
/opt/selfhosted/kill-newsletter/data
```
