# Bundle de supervision

Ce répertoire contient la configuration prête à déployer du tableau de bord
VPS :

- Grafana pour la consultation en lecture seule ;
- Prometheus pour les métriques ;
- Node Exporter pour Debian et la partition racine ;
- métriques natives du démon Docker ;
- cAdvisor, désactivé par défaut, pour les métriques détaillées par conteneur ;
- Loki et Alloy, facultatifs, pour les journaux systemd, Docker et Nginx ;
- métriques locales sur les mises à jour, le redémarrage et les unités en
  échec.

Le déploiement et les flags `ENABLE_LOGS` et
`ENABLE_CONTAINER_METRICS` sont documentés dans
`docs/05-dashboard-observabilite.md`.

Le fichier `tools/generate-dashboard.mjs` régénère
`grafana/dashboards/vps-observability.json` après modification du modèle :

```bash
node tools/generate-dashboard.mjs
```
