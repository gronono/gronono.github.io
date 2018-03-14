---
layout: post
title:  "HibernateUtils"
date:   2016-11-28 18:00:00 +1100
tags: [java, hibernate, spring]
description: Il y a quelques jours je suis tombé sur une classe Java nommée "HibernateUtils". Il y a quelques points qui ont attiré mon attention et que j'ai envie de partager avec vous.
comments: true
---
Il y a quelques jours je suis tombé sur une classe Java nommée "HibernateUtils". Il y a quelques points qui ont attiré mon attention et que j'ai envie de partager avec vous.

Avant de commencer voici la classe en question:

{% highlight java %}
/**
 * Classe HibernateUtils.
 *
 * <p>
 * Fournis des méthodes utilitaires de connexion et de gestion de la session
 * d'accès aux données nécessaires à la constitution des éditions.
 * </p>
 */
public final class HibernateUtils {

    /**
     * The Hibernate session factory.
     */
    private static volatile SessionFactory sessionFactory;

    /**
     * The report's data access configuration.
     */
    private static volatile Configuration config;

    /**
     * Session thread.
     */
    private static ThreadLocal<Session> SESSION_LOCALE;

    public static Configuration getConfiguration() {
        if (config != null) {
            return config;
        }

        return new Configuration();
    }

    /**
     * @param pConfiguration The report JDBC configuration.
     * @return The database Session (opened).
     * @throws HibernateException Usually indicates an invalid configuration or invalid mapping information.
     */
    public static Session getSession(final JdbcConfiguration pConfiguration) throws HibernateException {
        config = getConfiguration();
        String platform = StringUtils.upperCase(pConfiguration.getType());
        switch (platform) {
        case "MYSQL":
            getMySQLConfig(pConfiguration);
            break;
        case "POSTGRESQL":
            getPostgreSQLConfig(pConfiguration);
            break;
        case "ORACLE":
            getOracleConfig(pConfiguration);
            break;
        default:
            break;
        }

        ServiceRegistry registry = new StandardServiceRegistryBuilder().applySettings(config.getProperties()).build();

        sessionFactory = config.buildSessionFactory(registry);
        SESSION_LOCALE = new ThreadLocal<Session>();
        Session lSession = SESSION_LOCALE.get();
        return sessionFactory.openSession();
    }

    /**
     * Close the session.
     */
    public static void closeSession() {
        SESSION_LOCALE.get().close();
    }

    /**
     * constructor intentionally private
     */
    private HibernateUtils() {
    }

    private static void getMySQLConfig(final JdbcConfiguration pConfiguration) {
          config.setProperty(HibernateConfigProperty.HIBERNATE_DIALECT, "org.hibernate.dialect.MySQL5Dialect");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_DRIVER_CLASS, "com.mysql.jdbc.Driver");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_URL, "jdbc:mysql://"
                  + pConfiguration.getServer() + ":" + pConfiguration.getPort() + "/" + pConfiguration.getDb());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_USERNAME, pConfiguration.getUser());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_PASSWORD, pConfiguration.getPassword());
      }

      private static void getPostgreSQLConfig(final JdbcConfiguration pConfiguration) {
          config.setProperty(HibernateConfigProperty.HIBERNATE_DIALECT, "org.hibernate.dialect.PostgreSQLDialect");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_DRIVER_CLASS, "org.postgresql.Driver");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_URL, "jdbc:postgresql://"
                  + pConfiguration.getServer() + ":" + pConfiguration.getPort() + "/" + pConfiguration.getDb());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_USERNAME, pConfiguration.getUser());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_PASSWORD, pConfiguration.getPassword());
      }

      private static void getOracleConfig(final JdbcConfiguration pConfiguration) {
          config.setProperty(HibernateConfigProperty.HIBERNATE_DIALECT, "org.hibernate.dialect.Oracle10gDialect");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_DRIVER_CLASS, "oracle.jdbc.OracleDriver");
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_URL, "jdbc:oracle:thin:@"
                  + pConfiguration.getServer() + ":" + pConfiguration.getPort() + ":" + pConfiguration.getDb());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_USERNAME, pConfiguration.getUser());
          config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_PASSWORD, pConfiguration.getPassword());

      }
}
{% endhighlight %}

## Classe utilitaire

La classe se nomme `HibernateUtils`, elle est déclarée finale, possède un constructeur privé et toutes ses méthodes sont déclarées statiques. C'est donc bien une classe utilitaire.

Globalement je n'aime pas les classes dites utilitaires. Toutes classes d'une application sont utiles sinon on les supprime du projet.

### État statique

Cette classe utilitaire contient un état statique. Et il faut toujours se méfier des états statiques : problèmes de memory leak, de multithreading, ...

Le développeur utilise judicieusement `ThreadLocal` qui lui permet de garbager automatiquement la `Session` lorsque le thread se termine et résout le problème du memoryleak et du multithreading en un coup. Mais il reste les références à `SessionFactory` et `Configuration`.

Ils utilisent le mot-clé `volatile` alors que [la plupart des gens ne savent pas ce qu'il signifie](http://www.touilleur-express.fr/2010/12/09/quelle-est-la-difference-entre-volatile-et-synchronized/).
De plus si on veut avoir une instance d'un objet dans un contexte statique et multithreadé, le plus simple est de faire `private static Configuration config = new Configuration();` (qu'on peut déclarer maintenant `final`).

Les subtilités inhérentes à `volatile`, `synchronized` et le multithreading me font aussi me poser des questions sur le fait que la référence à la `SessionFactory` change dans la méthode `getSession(JdbcConfiguration)`. Étant donné qu'elle n'est utilisée que dans cette méthode, n'aurait-il pas été plus simple d'en faire une variable locale ?

### Fourre-tout

Une classe suffixée par `Utils` est l'occasion d'avoir un fourre-tout sans avoir de notion (métier ou technique) clairement définie derrière. On se retrouve souvent à avoir des classes qui grossissent à n'en plus finir, contiennent finalement des méthodes qui n'ont plus rien à voir entre elles et qui ne sont appelées qu'une seule fois. **Les classes utilitaires ne devraient exister que pour enrichir le langage.**

Si on regarde l'utilisation de cette classe dans le projet, on s'aperçoit :
1. la méthode `getConfiguration()` n'est pas appelée en dehors de cette classe : on peut la passer en `private`,
2. la méthode `closeSession()` n'est jamais appelée dans toute l'application : on peut la supprimer,
2. cette classe sert à vérifier que les paramètres de connexion fournis sont corrects (ping sur la base),
3. à récupérer une connexion à la base de données

Le fait que la méthode `closeSession()` ne soit jamais appelée me semble complètement anormale. Est-ce que ça signifie que les sessions obtenues par `getSession(JdbcConfiguration)` ne sont jamais fermées ?

Finalement le besoin ici n'est pas d'avoir un fourre-tout par rapport à `Hibernate` mais d'avoir un mécanisme manipulant les connexions à la base. On pourrait donc écrire une interface décrivant ce service, par exemple :

{% highlight java %}
public interface DatabaseService {

	/**
	 * Effectue un ping vers la base de données.
	 * C'est à dire vérifie que les paramètres de connexion spécifiés sont corrects.
	 *
	 * @param jdbcConfiguration Les paramètres de connexion à la base de données.
   * @return true si le ping est correct, false sinon
	 */
	boolean ping(JdbcConfiguration jdbcConfiguration);

	/**
	 * Permet de récupérer une connexion à la base de données.
	 * <em>Attention:</em>Vous devez fermer la connexion après usage.
	 *
	 * @param jdbcConfiguration Les paramètres de connexion à la base de données.
	 * @return La connexion.
	 */
	Connection getConnection(JdbcConfiguration jdbcConfiguration);
}
{% endhighlight %}

Je propose une implémentation plus loin du service. Mais à ce stade, il n'est pas difficile de faire une implémentation se reposant sur `Hibernate` en reprenant le code de la classe `HibernateUtils`.

## Switch/case

Maintenant qu'on a fini avec le statut '`Utils`' de la classe , il est temps d'examiner un peu le contenu de la classe.

Comme nous l'avons vu le cœur de la classe est la méthode `getSession(JdbcConfiguration)`. Et elle contient un `switch`/`case` me posant plusieurs problèmes.

### Cas par défaut

Dans un `switch`/`case`, il faut toujours utiliser `default`. Et l'auteur y a pensé, mais il n'y fait absolument rien ! Que se passe-t-il si la plateforme n'est pas supportée ? On se retrouve avec une configuration non initialisée et Hibernate va planter avec une erreur potentiellement obscure. Il aurait été beaucoup plus explicite de mettre un `throw UnsupportedOperationException("unsupported platform: " + platform );` ou équivalent. Ça peut sauver pas mal de santé mentale à celui qui tombe sur l'erreur.

### Switch sur des chaînes

C'est une fonctionnalité apparue avec Java 7. Comme vous en doutez sûrement, je ne suis pas fan. Surtout qu'ici le nombre de possibilités est fini et connu au moment de la compilation : pour ajouter une plateforme, il faut nécessairement modifier le code (au moins ajouter la dépendance vers le driver). Donc je pense que ça aurait été une meilleure idée de passer par une énumération. Et comme la bonne pratique veut qu'on convertisse les valeurs le plus tôt possible, on peut avoir :

{% highlight java %}
public enum DatabasePlatform {
	MYSQL, POSTGRESQL, ORACLE
}
{% endhighlight %}

{% highlight java %}
// pConfiguration possède déjà la version convertie.
DatabasePlatform platform = pConfiguration.getType();
Configuration config = null;
switch (platform) {
case MYSQL:
    config = getMySQLConfig(pConfiguration);
    break;
case POSTGRESQL:
    config = getPostgreSQLConfig(pConfiguration);
    break;
case ORACLE:
    config = getOracleConfig(pConfiguration);
    break;
default:
	throw new UnsupportedOperationException("unsupported platform: " + platform);
}
{% endhighlight %}

### Logique dupliquée

Les trois `case` appellent quasiment les mêmes méthodes dans lesquelles on initialise le login et le mot de passe de façon commune et le dialecte, le driver et l'url spécifique à la base de données.
Maintenant qu'on a une classe d'énumération, on peut facilement stocker les informations spécifiques à la base dans l'enum. Il y a juste un peu problème avec l'url qu'on peut résoudre (par exemple) avec du remplacement de wildcard.

L'énumération devient:
{% highlight java %}
public enum DatabasePlatform {
  MYSQL(MySQL5Dialect.class, com.mysql.jdbc.Driver.class, "jdbc:mysql://${server}:${port}/${instance}"),
  POSTGRESQL(PostgreSQLDialect.class, org.postgresql.Driver.class, "jdbc:postgresql://${server}:${port}/${instance}"),
  ORACLE(Oracle10gDialect.class, oracle.jdbc.OracleDriver.class, "jdbc:oracle:thin:@${server}:${port}:${instance}");

  private Class<? extends Dialect> dialect;
  private Class<? extends Driver> driver;
  private String url;

  private DatabasePlatform(Class<? extends Dialect> dialect, Class<? extends Driver> driver, String url) {
    this.dialect = dialect;
    this.driver = driver;
    this.url = url;
  }

  public Class<? extends Dialect> getDialect() {
    return dialect;
  }

  public Class<? extends Driver> getDriver() {
    return driver;
  }

  public String getUrl(String server, String port, String instance) {
    return url
        .replace("${server}", server)
        .replace("${port}", port)
        .replace("${instance}", instance);
  }
}
{% endhighlight %}

Et la méthode `getSession(JdbcConfiguration)`:
{% highlight java %}
private Session getSession(final JdbcConfiguration pConfiguration) throws HibernateException {
  DatabasePlatform platform = pConfiguration.getType();
  Configuration config = new Configuration();
  config.setProperty(HibernateConfigProperty.HIBERNATE_DIALECT, platform.getDialect().getName());
  config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_DRIVER_CLASS, platform.getDriver().getName());
  config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_URL, platform.getUrl(pConfiguration.getServer(), pConfiguration.getPort(), pConfiguration.getDb()));
  config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_USERNAME, pConfiguration.getUser());
  config.setProperty(HibernateConfigProperty.HIBERNATE_CONNECTION_PASSWORD, pConfiguration.getPassword());

  ServiceRegistry registry = new StandardServiceRegistryBuilder().applySettings(config.getProperties()).build();
  SessionFactory sessionFactory = config.buildSessionFactory(registry);
  return sessionFactory.openSession();
}
{% endhighlight %}

On a supprimé la logique dupliquée, centralisé la gestion des drivers `JDBC` et on a maintenant une vérification de type sûr - les classes des dialectes et des drivers sont vérifiées à la compilation. Et effet de bord non voulu, mon IDE m'a remonté que la classe utilisée pour le driver postgresql est dépréciée.

## Couplage avec Hibernate

Jusque-là j'ai gardé le fait que le développeur est utilisé `Hibernate` pour remplir ses deux besoins : faire un ping de la base et obtenir une connexion. Mais l'application en question est une application `spring-boot` utilisant `spring-data-jpa`. Donc `hibernate` est une dépendance indirecte fournie par Spring. Et si les gars de `spring-data-jpa` décident de changer l'implémentation JPA par défaut par autre chose qu'Hibernate il faudra revoir cette classe (ou introduire directement la dépendance, ce qui peut avoir des effets bords inattendus du à plusieurs implémentations de JPA dans le classpath).

De plus utiliser Hibernate pour un besoin aussi trivial revient à sortir une usine à gaz pour pas grand-chose, en ajoutant les problèmes liés à la gestion des sessions dans Hibernate inutile à notre cas.

En supprimant le couplage avec Hibernate, mais en gardant celui avec Spring (qui te toute façon sera non triviale à supprimer par l'intrusivité du framework), on a :

{% highlight java %}
public class SpringDatabaseService implements DatabaseService {

	@Override
	public boolean ping(JdbcConfiguration jdbcConfiguration) {
		try {
			return getConnection(jdbcConfiguration).isValid(0);
		} catch (SQLException e) {
			// Une implémentation plus judicieuse remonterait la cause
			return false;
		}
	}

	@Override
	public Connection getConnection(JdbcConfiguration jdbcConfiguration) {
		DatabasePlatform platform = jdbcConfiguration.getType();
		DataSource ds = new SimpleDriverDataSource(
				platform.getDriver(),
				platform.getUrl(jdbcConfiguration.getServer(), jdbcConfiguration.getPort(), jdbcConfiguration.getDb()),
				jdbcConfiguration.getUser(),
				jdbcConfiguration.getPassword());

		try {
			return ds.getConnection();
		} catch (SQLException e) {
			// Bien évidement, ici il faut propager l'exception
			// avec probablement une meilleur exception que RuntimeException
			throw new RuntimeException(e);
		}
	}
}
{% endhighlight %}

Avec l'enum qui va bien (on a enlevé le dialecte):

{% highlight java %}
public enum DatabasePlatform {
  MYSQL(new com.mysql.jdbc.Driver(), "jdbc:mysql://${server}:${port}/${instance}"),
  POSTGRESQL(new org.postgresql.Driver(), "jdbc:postgresql://${server}:${port}/${instance}"),
  ORACLE(new oracle.jdbc.OracleDriver(), "jdbc:oracle:thin:@${server}:${port}:${instance}");

  private Driver driver;
  private String url;

  private DatabasePlatform(Driver driver, String url) {
    this.driver = driver;
    this.url = url;
  }

  public Driver getDriver() {
    return driver;
  }

  public String getUrl(String server, String port, String instance) {
    return url
        .replace("${server}", server)
        .replace("${port}", port)
        .replace("${instance}", instance);
  }
}
{% endhighlight %}

## Fermeture automatique

Il reste un dernier petit détail. Le développeur doit toujours penser à fermer la connexion lorsqu'il appelle `getConnection(JdbcConfiguration)` et on peut y remédier si c'est nous qui contrôlons la fermeture. Exemple (en java 8):

{% highlight java %}
public void doInConnection(JdbcConfiguration jdbcConfiguration, Consumer<Connection> consumer) {
	try (Connection cnx = getConnection(jdbcConfiguration)) {
		consumer.accept(cnx);
	}
}
private Connection getConnection(JdbcConfiguration jdbcConfiguration) {
  ...
}
{% endhighlight %}

L'idée est la suivante: on n'expose plus la méthode `getConnection(JdbcConfiguration)` et à la place, on fournit une méthode qui prend le traitement à faire avec la connexion `Consumer<Connection>`. Ainsi on peut ouvrir la connexion, faire le traitement et fermer la connexion. Ainsi on évite les fuites parce que l'appelant à oublier de fermer la connexion.

## Conclusion

Pour résumer on a simplifié le code :
* en supprimant les problèmes liés au multithreading,
* en rajoutant des notions de plus haut niveau (DatabaseService vs HibernateUtils),
* en découplant la notion de service et son implémentation
* en factorisant la gestion des drivers en un endroit unique
* en supprimant un framework compliqué : Hibernate,
* en forçant la fermeture des connexions.

J'espère que cet article vous aura plu. N'hésitez pas à commenter ci-dessous si vous d'accord ou pas.
