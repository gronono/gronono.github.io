---
layout: post
title:  "Configurer Apache en mode load balancer"
date: 2019-05-22 10:30:00 +1100
tags: [apache, loadbalancer]
comments: true
---

J'ai eu besoin de configurer un serveur [Apache](https://httpd.apache.org/) en mode load-balancing vers une application hébergée sur deux serveurs [Tomcat](http://tomcat.apache.org/) différents.

<!--more-->

## Activation des modules Apache

Pour que la configuration fonctionne, Apache a besoin des modules suivants. On les active via la commande `a2enmod`.

```bash
a2enmod proxy proxy_http rewrite deflate headers proxy_balancer proxy_connect lbmethod_byrequests
```

## Configuration de l'hôte virtuel

Pour la démo, j'utilise le virtualhost par défaut. Mais bien sûr, il faut adapter la configuration suivant votre cas.

```apache
<VirtualHost *:80>
  <Proxy balancer://cluster>
    BalancerMember http://<server1>:8080/<application>
    BalancerMember http://<server2>:8080/<application>
  </Proxy>

  ProxyPass / balancer://cluster/
  ProxyPassReverse / balancer://cluster/    
</VirtualHost>
```

Puis on relance le service Apache
```bash
systemctl restart apache2
```
