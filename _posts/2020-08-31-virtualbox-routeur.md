---
layout: post
title:  "Créer une infra virtuelle avec VirtualBox - Partie 1 : le routeur Internet"
date: 2019-05-23 19:30 +1100
tags: [debian, linux, virtualbox, routeur, réseau]
comments: true
---
Voici le premier article d'une série sur comment créer une infrastructure virtuelle sous VirtualBox.

Dans cet article, nous allons voir comment simuler un réseau local/privé ayant accès à Internet dans VirtualBox.

<!--more-->

Le but est d'arriver à mettre en place le réseau privé définit par le schéma suivant :

![Schéma du réseau](/assets/virtual-router/virtualbox-router.png)

Au total, on a trois machines virtuelles :
* les machines nommées `machine1` et `machine2` possèdent chacune une seule interface réseau sur le réseau interne à VirtualBox nommé `intnet`,
* la machine nommée `routeur` possède deux interfaces réseaux : une sur le réseau interne `intnet` et l'autre configurée en NAT.

L'accès à Internet depuis les machines 'machine1' et 'machine2' se fait via la machine 'routeur'.

Pour les trois machines, je suis parti d'une base Debian 10.

# Configuration de la machine 'routeur'

Il s'agit de l'installation la plus compliquée puisqu'elle sert de routeur réseau entre le réseau NAT et le réseau interne.

Dans VirtualBox, j'ai configuré les deux interfaces comme indiqué sur les captures d'écran suivantes :

![Configuration du NAT](/assets/virtual-router/virtualbox-nat.png)

![Configuration du réseau interne](/assets/virtual-router/virtualbox-intnet.png)

La commande `ip address show` nous montre bien qu'on a deux interfaces dont l'une d'elles (enp0s3) possède une IP (10.0.2.15/24).
Il s'agit de l'interface en mode NAT. VirtualBox lui attribue automatiquement une adresse.

Par contre la seconde interface (enp0s8) n'est pas configurée.

```bash
$ ip address show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:89:4b:81 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global dynamic enp0s3
       valid_lft 84902sec preferred_lft 84902sec
    inet6 fe80::a00:27ff:fe89:4b81/64 scope link 
       valid_lft forever preferred_lft forever
3: enp0s8: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 08:00:27:a1:c2:6e brd ff:ff:ff:ff:ff:ff
```

Pour la configurer, nous allons lui fixer son adresse en ajoutant le fichier `/etc/network/interfaces.d/enp0s8`:
```bash
$ cat /etc/network/interfaces/enp0s8
auto enp0s8
iface enp0s8 inet static
  address 192.168.2.1
  netmask 255.255.255.0
  network 192.168.2.0
  broadcast 192.168.2.255
```

> Après l'activation de la nouvelle interface, la connexion SSH freezait après avoir entré le mot de passe. Pour y remédier, j'ai dû désactiver l'option `UseDNS` dans la configuration du daemon SSH. 

Après un reboot de la machine, on peut voir que notre interface possède maintenant une adresse IP:
```bash
$ ip address show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:89:4b:81 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.15/24 brd 10.0.2.255 scope global dynamic enp0s3
       valid_lft 86381sec preferred_lft 86381sec
    inet6 fe80::a00:27ff:fe89:4b81/64 scope link 
       valid_lft forever preferred_lft forever
3: enp0s8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 08:00:27:a1:c2:6e brd ff:ff:ff:ff:ff:ff
    inet 192.168.2.1/24 brd 192.168.2.255 scope global enp0s8
       valid_lft forever preferred_lft forever
    inet6 fe80::a00:27ff:fea1:c26e/64 scope link 
       valid_lft forever preferred_lft forever
```

Et on a toujours accès à Internet
```bash
$ ping -c1 gronono.fr
PING gronono.fr (185.199.109.153) 56(84) bytes of data.
64 bytes from 185.199.109.153 (185.199.109.153): icmp_seq=1 ttl=63 time=282 ms

--- gronono.fr ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 281.546/281.546/281.546/0.000 ms
```

Il est temps maintenant d'activer le routage.

Pour cela, il faut dans un premier temps activer l'`IP Forward` au niveau du noyau en supprimant le `#` sur la ligne correspondante le fichier `/etc/sysctl.conf`
```bash
$ grep "ip_forward" /etc/sysctl.conf 
net.ipv4.ip_forward=1
```

Puis il faut créer une règle `iptables` pour faire du NAT entre les deux interfaces réseaux en créant le script executable `/etc/if-pre-up.d/iptables` :
```bash
$ cat /etc/network/if-pre-up.d/iptables 
#!/bin/sh
/usr/sbin/iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
/usr/sbin/iptables -A FORWARD -i enp0s8 -j ACCEPT

$ sudo chmod +x /etc/network/if-pre-up.d/iptables
```

On reboote la machine et on peut passer à la configuration des deux autres machines.

# Configuration des machines "machine1" et "machine2"

La configuration des machines est strictement identique au détail de l'adresse IP près.

Dans VirtualBox, on commence par configurer la première interface en mode réseau internet en prenant soin de bien mettre le même nom de réseau que l'interface du serveur.

![Configuration du réseau internet](/assets/virtual-router/virtualbox-machine-intnet.png)

On vérifie que notre interface n'a pas d'adresse IP:
```bash
$ ip address show
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: enp0s3: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN group default qlen 1000
    link/ether 08:00:27:5e:7d:50 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::a00:27ff:fe5e:7d50/64 scope link
       valid_lft forever preferred_lft forever
```

On va maintenant lui attribuer l'IP fixe 192.168.2.101/24 (la machine2 aura l'IP 192.168.2.102/24) en ajoutant le fichier `/etc/network/interfaces.d/enp0s3` :
```bash
$ cat /etc/network/interfaces.d/enp0s3
auto enp0s3
iface enp0s3 inet static
  address 192.168.2.101
  netmask 255.255.255.0
  network 192.168.2.0
  broadcast 192.168.2.255
```

Après un reboot, nos deux machines (`routeur` et `machine1`) peuvent se pinguer respectivement mais la `machine1` ne résout pas les noms DNS:
```bash
$ ping gronono.fr
ping: gronono.fr: Échec temporaire dans la résolution du nom
```

Pour y remédier, il faut ajouter une gateway :
```bash
$ cat /etc/network/interfaces.d/enp0s3
auto enp0s3
iface enp0s3 inet static
  address 192.168.2.101
  netmask 255.255.255.0
  network 192.168.2.0
  broadcast 192.168.2.255
  gateway 192.168.2.1
```

Après un petit reboot, notre `machine1` devrait maintenant pouvoir accéder à Internet:
```bash
$ $ ping -c1 gronono.fr
PING gronono.fr (185.199.110.153) 56(84) bytes of data.
64 bytes from 185.199.110.153 (185.199.110.153): icmp_seq=1 ttl=61 time=203 ms

--- gronono.fr ping statistics ---
1 packets transmitted, 1 received, 0% packet loss, time 0ms
rtt min/avg/max/mdev = 203.029/203.029/203.029/0.000 ms
```

> Si vous avez toujours un problème de résolution de nom, il se peut que votre configuration DNS ne soit pas bonne. Vérifiez le fichier `/etc/resolv.conf` et en cas de doute, vous pouvez utiliser le serveur DNS de Google : `8.8.8.8` (après avoir vérifié que vous arrivez à faire un ping dessus.)


Il reste à faire la même chose pour les autres machines de notre réseau.

# Conclusion

Dans cette première partie, nous avons mis en place la base de notre infrastructure.

Nous verrons dans un prochain article comment mettre en place un serveur DHCP pour nos machines `machine1` et `machine2`.
