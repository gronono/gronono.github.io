---
layout: post
title:  "Installer un proxy-cache pour Docker en 2 minutes"
date: 2019-05-23 19:30 +1100
tags: [docker]
comments: true
---
Voici comment installer un proxy-cache pour [Docker](https://docker.com) très simplement en quelques minutes.

<!--more-->

On va utiliser l'image officiel du registre de Docker pour notre proxy-cache.

Il nous faut modifier la configuration par défaut. Pour cela, on va d'abord la récupérer :
```bash
docker run -it --rm --entrypoint cat registry:2 /etc/docker/registry/config.yml > ${PWD}/registry-config.yml
```

Il faut la modifier pour rajouter les lignes suivantes :
```yaml
proxy:
  remoteurl: https://registry-1.docker.io
```

On peut maintenant lancer le service via Docker avec la nouvelle configuration :
```bash
docker run -d --restart=always -p 5000:5000 --name docker-registry-proxy -v ${PWD}/registry-config.yml:/etc/docker/registry/config.yml registry:2
```

On configure le démon docker via le ficier `/etc/docker/daemon.json` :
```json
{
	"registry-mirrors": [ "http://localhost:5000" ]
}
```
Et on le relance :
```bash
$ sudo systemctl restart docker.service
```

Pour tester, on peut lancer par exemple `hello-world` (à condition de ne pas avoir l'image déjà en local):
```bash
$ docker run hello-world
```

Et on peut vérifier que le proxy l'a bien téléchargé via :
```bash
$ curl http://localhost:5000/v2/_catalog
{"repositories":["library/hello-world"]}
```

Et voilà notre proxy-cache pour Docker est opérationnel.
