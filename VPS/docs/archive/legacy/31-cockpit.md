Installation :

```Bash
sudo apt update
sudo apt install -y cockpit cockpit-system cockpit-storaged cockpit-packagekit
sudo systemctl enable --now cockpit.socket
```

Autoriser Cockpit dans UFW uniquement depuis ton IP fixe si possible :

```Bash
sudo ufw allow from TON_IP_FIXE to any port 9090 proto tcp comment "Cockpit admin"
```

Si tu n’as pas d’IP fixe, ouverture générale, moins recommandée :

```Bash
sudo ufw allow 9090/tcp comment "Cockpit admin"
```

Accès :

```
https://IP_DU_SERVEUR:9090
```

Connexion avec ton utilisateur Linux :

```
Utilisateur : lucas
Mot de passe : mot de passe système
```

Recommandation : ne pas exposer Cockpit via un sous-domaine public au début. Garde-le sur `:9090`, protégé par UFW, ou utilise un VPN type WireGuard/Tailscale plus tard.