---
layout: post
title:  "Exposer un service tournant dans un container LXC"
date: 2019-05-22 08:30:00 +1100
tags: [lxc]
comments: true
---

Aujourd'hui j'avais besoin de faire des tests de configuration d'un serveur [Apache](https://httpd.apache.org/).
Au lieu d'installer le serveur sur ma machine, j'ai décidé de le faire tourner dans un container [LXC](https://linuxcontainers.org/).

<!--more-->

## Création du service Apache dans un container LXC

Sur ma machien hôte je lance la création du container. J'utilise une image [Debian](https://www.debian.org/) et je l'appelle "apache"

```
$ lxc launch images:debian/stretch apache
```

Puis j'entre dans le container pour y installer apache et je vérifie l'installation :

```bash
$ lxc exec apache bash
root@apache:~# apt install apache2 curl
# Pour vérifier l'écoute sur le port 80
root@apache:~# netstat -tnlp | grep 80
# Pour vérifier "l'affichage" de la page
root@apache:~# curl http://localhost
```

## Exposition du service sur la machine hôte

Par défaut, LXC n'expose pas le service Apache. Il reste cloisonner dans le container. Il faut donc créer un système de proxy pour exposer un port du système de l'hôte (ici 8080) vers le port du container (ici le 80). LXC le fait pour nous via la notion de "config device". On lance donc la commande:

```bash
# Pour vérifier que le port 8080 est libre
$ netstat -tnlp | grep 8080
# Pour créer le proxy nommé 'port80' depuis le port 8080 de la machine hôte vers le port 80 du container nommé 'apache'
$ lxc config device add apache port80 proxy listen=tcp:0.0.0.0:8080 connect=tcp:localhost:80
# Pour 'visualiser' ce qu'on vient de faire
$ lxc config device show apache
# Pour vérifier que le port 8080 est bien écouté par LXC
$ sudo netstat -tnlp | grep 8080
# Pour vérifier que le proxy fonctionne correctement
$ curl http://localhost:8080
```

Pour supprimer le proxy, il faut lancer la commande suivante:
```bash
$ lxc config device remove apache port80
$ lxc config device show apache
```

Je vais pouvoir tester ma configuration d'Apache.
