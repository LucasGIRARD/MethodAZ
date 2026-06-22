# Kill the Newsletter

## Fichiers

- Modèle : `install/services/kill-newsletter/docker-compose.yml`
- Installation : `/opt/selfhosted/kill-newsletter`
- Port HTTP local : `127.0.0.1:3005`
- Domaine : `newsletter.example.fr`

L'installateur clone automatiquement le dépôt amont, sélectionne la révision
verrouillée par `KILL_NEWSLETTER_REF`, puis construit l'image avec le
Dockerfile fourni par ce projet. Avec `SERVICES=all`, le service est inclus.
Avec une liste partielle, ajouter `kill-newsletter` à `SERVICES`, puis lancer
la phase applicative :

```bash
sudo vps-install --phase services
```

Le conteneur démarre uniquement le serveur HTTP local sur `127.0.0.1:3005`.
En production, il utilise `network_mode: host` pour éviter les problèmes de
publication Docker avec ce serveur Node. Nginx reste le seul point d'entrée
public et termine TLS.

Il n'est pas activé par défaut. La réception de courriels depuis Internet
nécessite une conception séparée pour SMTP, MX, SPF, DKIM, DMARC, DNS inverse
et réputation IP. Ne pas ouvrir un port SMTP à partir de ce modèle.

Pour changer de version, modifier `KILL_NEWSLETTER_REF` vers un commit
explicitement choisi, puis rejouer la phase `services`.

## Données

```text
/opt/selfhosted/kill-newsletter/data
```

## Dépannage

Le service connaît son domaine via `KILL_NEWSLETTER_HOSTNAME`. Pour tester le
port local, envoyer donc le même en-tête `Host` que le gateway Nginx :

```bash
sudo vps-compose kill-newsletter logs --tail=100 app
curl -i --max-time 5 \
  -H 'Host: newsletter.example.fr' \
  http://127.0.0.1:3005/
```

Remplacer `newsletter.example.fr` par la valeur réelle de `NEWSLETTER_DOMAIN`.
Un test direct sans cet en-tête peut être trompeur.

Le port `3005` parle HTTP local. Ce test est donc volontairement en `http://`.
Un test en `https://127.0.0.1:3005` doit échouer : HTTPS est uniquement géré par
Nginx sur les ports publics `80/443`.

Avec `network_mode: host`, `ss` doit montrer un processus `node` ou équivalent
en écoute sur `3005`, pas un `docker-proxy` :

```bash
sudo ss -ltnp | grep ':3005'
sudo docker inspect kill-newsletter-app-1 \
  --format '{{.HostConfig.NetworkMode}}'
```
