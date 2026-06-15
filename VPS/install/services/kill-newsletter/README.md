# Kill the Newsletter

L'installateur récupère automatiquement le dépôt amont dans `app/`, puis
sélectionne le commit défini par `KILL_NEWSLETTER_REF`. Pour l'activer,
ajouter `kill-newsletter` à `SERVICES`, puis lancer :

```bash
sudo vps-install --phase services
```

Ce service reste absent de la liste activée par défaut, car son exposition
SMTP nécessite une stratégie DNS et de réputation distincte. Le conteneur
fourni ici ne démarre que le serveur HTTP.
