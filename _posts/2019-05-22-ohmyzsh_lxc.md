---
layout: post
title:  "Auto-complétion de LXC avec Oh-My-Zsh"
date: 2019-05-22 18:45:00 +1100
tags: [lxc, oh-my-zsh]
comments: true
---

[Oh-My-Zsh](https://ohmyz.sh/) fournit de nombreux plugins notamment pour l'auto-complétion des commandes. Malheureusement, il n'y a pas de plugin pour [LXC](https://linuxcontainers.org/).

Voici comment y remédier.

<!--more-->

[Endaaman](https://github.com/endaaman) a déjà écrit le [code nécessaire](https://github.com/endaaman/lxd-completion-zsh) pour l'auto-complétion de LXC avec Zsh. 

Je propose donc de réutiliser son travail et en faire un plugin pour Oh-My-Zsh.

```bash 
cd ~/.oh-my-zsh/custom/plugins/
git clone https://github.com/endaaman/lxd-completion-zsh.git
cd lxd-completion-zsh
ln -sf _lxc lxd-completion-zsh.plugin.zsh
```

Puis on l'active dans le fichier ~/.zshrc
```
plugins=(
    ...
    lxd-completion-zsh
)
```

Et enfin on recharge Zsh avec un `source ~/.zshrc` et si tout se passe bien, on a maintenant l'auto-complétion.

Voici un exemple de ce que ça donne :
```bash
$ lxc st+TAB
start    -- Start containers
stop     -- Stop containers
storage  -- Manage storage pools and volumes
$ lxc start +TAB
kmaster   tpl-kube
```
