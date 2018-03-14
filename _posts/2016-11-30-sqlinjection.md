---
layout: post
title:  "SQL Injection"
date: 2016-11-30 22:00:00 +1100
tags: [java, spring-data-jpa, sql]
description: En début de semaine, j'ai eu des rappels sur les failles de sécurité liée au code et notamment le fameux SQL Injection.
comments: true
---
En début de semaine, j'ai eu des rappels sur les failles de sécurité liée au code et notamment le fameux [SQL Injection](https://fr.wikipedia.org/wiki/Injection_SQL).

Une des erreurs classiques est de faire de la concaténation de chaines sans considérer le contenu des paramètres. Exemple la requête suivante (en HQL): `"from Person where name ='" + input + "'"` peut être interprété comme `"from Person where name = '' or '1'='1'"` si `input = ' or '1'='1`. Et donc au lieu de selectionner les personnes en filtrant sur le nom, on retourne l'ensemble des personnes.

Au taf, on utilise `spring-data-jpa`. Du coup je me suis demandé si les développeurs de Spring avaient pris la problématique en considération.

## Tests

J'ai testé:
1. la concaténation (expliquée ci-dessus) en utilisant `EntityManager`
2. toujours dans l'`EntityManager`, le passage par les Bind Parameters
3. la génération automatique des requêtes avec `spring-data-jpa`
4. l'écriture des requêtes avec `@Query`

### Concaténation avec l'`EntityManager`

Voici le code de la méthode:
{% highlight java %}
Query query = em.createQuery("from Person where name = '" + name + "'");
List<Person> result = query.getResultList();
{% endhighlight %}

Et sans surprise, on tombe dans le cas décrit en introduction. Notre code est vulnérable aux injections SQL. *À ne pas faire*.

### Bind Parameters sur l'`EntityManager`

Dans ce cas, on injecte le paramètre de la requête en utilisant la méthode `setParameter(String, Object)`:

{% highlight java %}
Query query = em.createQuery("from Person where name = :name");
query.setParameter("name", name);
List<Person> result = query.getResultList();
{% endhighlight %}

JPA semble bien faire son travail et traite les paramètres pour éviter l'injection SQL. Si on passe par l'`EntityManager`, c'est la méthode recommandée.

### Spring Data JPA

Ici, on utilise le mécanisme un peu magique de [Spring Data JPA](http://docs.spring.io/spring-data/jpa/docs/current/reference/html/) se basant sur le nom de la méthode pour générer la requête :

{% highlight java %}
public interface PersonRepository extends CrudRepository<Person, Long> {
  List<Person> findByName(@Param("name") String name);
}
{% endhighlight %}

Sans surprise, les équipes de Spring ne sont pas tombés dans le panneau.

### @Query

Dans ce cas, on utilise toujours Spring Data JPA, mais on écrit nous-mêmes la requête avec l'annotation `@Query` :
{% highlight java %}
public interface PersonRepository extends CrudRepository<Person, Long> {
  @Query("from Person where name = :name")
  List<Person> findByName(@Param("name") String name);
}
{% endhighlight %}

Et encore une fois, il n'y a pas de problème d'injection.

## Conclusion

Il ne faut jamais faire de la concaténation de chaine lors de la génération de requêtes SQL. Il est plus simple et plus sûr d'utiliser des mécanismes proposés par les frameworks et librairies.

[Les sources des tests sont disponibles sur github](https://github.com/gronono/gronono.github.io/blob/master/demo/sql-injection).
