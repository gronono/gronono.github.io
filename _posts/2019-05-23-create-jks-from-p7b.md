---
layout: post
title:  "Générer un fichier JKS à partir d'une clé privée et d'un fichier P7B"
date: 2019-05-23 10:00 +1100
tags: [java]
comments: true
---
Dans cet article, nous allons voir comment créer un fichier <abbr title="Java Key Store">JKS</abbr> à partir d'un fichier P7B et de la clé privée.

<!--more-->

Pour manipuler un fichier JKS, l'outil à utiliser est `keytool` fourni avec le <abbr title="Java Development Kit">JDK</abbr>.
Cet outil ne permet pas d'importer directement une clé publique et sa chaîne de certification. Il faut donc passer par autre type de magasin : le format P12.

Le fichier P7B ne contient pas la clé privée. Il stocke uniquement la chaîne de certification ; c'est-à-dire l'ensemble des certificats depuis le certificat root vers le certificat spécifique de notre clé.

Pour créer notre magasin au format P12, il faut que la chaîne de certification soit au format PEM, un autre format pouvant contenir la chaîne :
```
openssl pkcs7 -print_certs -in file.p7b -out file.pem
```

Une fois la chaîne de certification au format PEM, on peut créer le magasin au format P12 contenant la clé privée et sa chaîne de certificats :
```
openssl pkcs12 -export -name aliasName -in file.pem -inkey file.key -out file.p12
```
Le store au format P12 peut contenir plusieurs entrées. `aliasName` sert à spécifier le nom utilisé pour l'entrée.

La commande ci-dessus demande un mot de passe. Il permet de sécuriser le contenu du fichier P12.

Maintenant qu'on a notre store au format P12, il faut le convertir en JKS :
```
keytool -importkeystore -srcstoretype pkcs12 -srckeystore file.p12 -destkeystore file.jks
```
Le premier mot de passe demandé est celui du fichier P12 saisi précédemment. Puis l'outil demande le mot de passe du fichier JKS.

Et voilà, on a notre fichier JKS. Pour vérifier son contenu, on peut utiliser par exemple [KeyStore Explorer](https://keystore-explorer.org/).
