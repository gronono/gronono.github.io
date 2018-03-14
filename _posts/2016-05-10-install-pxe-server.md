---
layout: post
title:  "Installer un serveur PXE"
date:   2016-05-10 18:00:00 +1100
tags: [dhcpd, linux, pxe, tftpd]
description: Un serveur PXE permet de faire un boot d'une machine via le réseau.
comments: true
---
Un [serveur PXE](https://fr.wikipedia.org/wiki/Preboot_Execution_Environment) permet de faire un boot d'une machine via le réseau. Pour installer ce serveur, je suis parti d'une [debian installé via une netinst](https://www.debian.org/CD/netinst) sur [VirtualBox](https://www.virtualbox.org/).

## Configuration du réseau
Je souhaitais que mon serveur soit accessible sur mon réseau physique. J'ai donc configuré la carte réseau de la machine virtuel en "Accès par pont" pluggué sur ma carte réseau physique.

Pour éviter tout soucis, j'ai configuré une IP fixe en éditant le fichier /etc/network/interfaces:
{% highlight bash %}
# The primary network interface
auto eth0
iface eth0 inet static
  address 192.168.1.12
  netmask 255.255.255.0
  gateway 192.168.1.1
{% endhighlight %}

Pour vérifier la configuration un petit ping sur google.fr à partir du serveur et un autre à partir de ma machine vers 192.168.1.12. Tout le monde répond donc la configuration réseau est bonne.

## Serveur TFTP
Un serveur PXE sert les fichiers en [TFTP](https://fr.wikipedia.org/wiki/Trivial_File_Transfer_Protocol). J'ai donc installé un serveur TFTP.
{% highlight bash %}
apt-get install atftpd
{% endhighlight %}

Le répertoire contenant les fichiers par TFTP est définit dans le fichier de conf /etc/default/atftpd. C'est donc /srv/tftp.

## Serveur DHCP
Pour que le serveur PXE fonctionne correctement, nous devons aussi avoir un serveur DHCP sur votre réseau. Et j'en ai un: mon routeur ADSL fait office de serveur DHCP. Malheureusement, je ne vais pas pouvoir le configurer correctement (comme c'est souvent le cas, les options sont limités sur les serveurs fournis avec les routeurs pour particulier).
Je suis donc obligé de le désactiver temporairement et d'en installer un autre sur mon serveur.

{% highlight bash %}
apt-get install isc-dhcp-server
{% endhighlight %}

La configuration est dans le fichier /etc/dhcp/dhcpd.conf.
J'y ai rajouté le bloc:
{% highlight bash %}
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.50 192.168.1.99;
    server-name "server";
    next-server 192.168.1.12;
    filename "/srv/tftp/pxelinux.0";
}
{% endhighlight %}

Et j'ai relancé le serveur dhcp:
{% highlight bash %}
/etc/init.d/isc-dhcp-server restart
{% endhighlight %}

## Le serveur PXE
L'installation se fait classiquement:
{% highlight bash %}
apt-get install pxe
{% endhighlight %}

La configuration est située dans le fichier /etc/pxe.conf.
J'ai du changer l'IP d'écoute qui n'était pas bonne - la bonne valeur est l'IP du serveur 192.168.1.12 dans mon cas.
J'ai aussi changé le répertoire des fichiers TFTP.

Après les modifications de configuration, n'oublions pas de relancer le service
{% highlight bash %}
/etc/init.d/pxe restart
{% endhighlight %}

## Le test
Pour essayer, je vais faire en sorte de servir une [Debian](https://www.debian.org/index.fr.html) via PXE.

Et les gars de chez Debian, ils sont sympas, [ils nous filent directement une archive](http://ftp.fr.debian.org/debian/dists/testing/main/installer-amd64/current/images/netboot/netboot.tar.gz) à décompresser dans le répertoire /srv/tftp.

{% highlight bash %}
cd /srv/tftp
curl http://ftp.fr.debian.org/debian/dists/testing/main/installer-amd64/current/images/netboot/netboot.tar.gz
tar xvf netboot.tar.gz
{% endhighlight %}

Lorsqu'on boot une machine sur le réseau, on arrive sur l'assistant d'installation de debian. Donc ça marche \o/

## Conclusion
J'ai connu pire en terme d'installation. Ici ça se passe plutôt bien. Ça m'ennuie un peu d'avoir eu à installer un serveur DHCP car je vais devoir switcher entre les deux suivant si je veux lancer le serveur PXE ou pas. La prochaine étape est l'installation d'un serveur [CoreOS via PXE](https://coreos.com/os/docs/latest/booting-with-pxe.html). Mais on en reparle plus tard.