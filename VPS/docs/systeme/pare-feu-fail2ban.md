# Pare-feu et Fail2ban

## Politique

La chaîne `INPUT` bloque par défaut. Seuls les flux suivants sont acceptés :

| Port | Protocole | Usage |
| ---: | --- | --- |
| `**000` | TCP | SSH et SFTP |
| `80` | TCP | Nginx et validation ACME |
| `443` | TCP | Nginx HTTPS |

ICMP et ICMPv6 restent autorisés pour le diagnostic, la découverte IPv6 et la
détection de MTU.

## Implémentation

Debian utilise les commandes `iptables` et `ip6tables` avec le frontal
`nf_tables` :

```bash
sudo update-alternatives --set iptables /usr/sbin/iptables-nft
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
iptables --version
```

Les règles générées sont stockées dans :

```text
/etc/iptables/rules.v4
/etc/iptables/rules.v6
```

Le premier passage autorise aussi temporairement le port 22. La commande
`sudo vps-install --finalize-ssh` le retire après validation.

## Docker

Un rechargement complet des tables peut supprimer les chaînes créées par
Docker. L'installateur détecte un démon actif et le redémarre après application
des règles.

Tous les services applicatifs publient leurs ports sur `127.0.0.1`; Nginx en
réseau hôte est le seul frontal public sur 80 et 443.

## Fail2ban

Deux jails sont installées :

```text
sshd               échecs d'authentification SSH
iptables-portscan  scans TCP ou UDP rapides journalisés par le noyau
```

Vérification :

```bash
sudo fail2ban-client -t
sudo fail2ban-client status sshd
sudo fail2ban-client status iptables-portscan
sudo journalctl -u fail2ban --since today
```

Les limites Nginx et les nuances de détection sont détaillées dans
[Protection contre les scans et limitation Nginx](../15-protection-scans-rate-limit.md).

## Contrôle final

```bash
sudo iptables-restore --test /etc/iptables/rules.v4
sudo ip6tables-restore --test /etc/iptables/rules.v6
sudo iptables -L INPUT -n -v --line-numbers
sudo ip6tables -L INPUT -n -v --line-numbers
sudo ss -tulpn
```
