# Connecting to a Database from Aqueduct

The interface to a database from Aqueduct is an instance of `ManagedContext`, which contains the following two objects:

- a `ManagedDataModel` that describes your application's data model
- a `PersistentStore` that creates database connections and transmits data across that connection.

A `ManagedContext` uses these two objects to coordinate moving data to and from your application and a database when executing `Query<T>`s. A `ManagedContext` - and its store and data model - are created in a `ApplicationChannel` constructor.

```dart
class MyApplicationChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    var dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    var psc = PostgreSQLPersistentStore.fromConnectionInfo(
        "username", "password", "host", 5432, "databaseName");

    context = ManagedContext(dataModel, psc);
  }
}
```

A `ManagedDataModel` should be instantiated with its `fromCurrentMirrorSystem` convenience constructor. You may optionally pass a list of `ManagedObject<T>` subclasses to its default constructor.

```dart
var dataModel = ManagedDataModel([User, Post, Friendship]);
```

A `ManagedContext` is required to create and execute a `Query<T>`. The context determines which database the query is executed in. A context must exist before creating instances of any `ManagedObject` subclass in your application. Controllers that need to execute database queries must have a reference to a context; this is typically accomplished by passing the context to a controller's constructor.

### Using a Configuration File

Connection information for a database is most often configured through a configuration file. This allows you to build configurations for different environments (production, testing, etc.), without having to modify code.

```dart
class MyConfigurationItem extends ConfigurationItem {
  MyConfigurationItem(String configPath) : super.fromFile(configPath);

  DatabaseConnectionConfiguration database;
}

class MyApplicationChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    final config = MyConfigurationItem(options.configurationFilePath);

    final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
    final psc = PostgreSQLPersistentStore.fromConnectionInfo(
        config.database.username,
        config.database.password,
        config.database.host,
        config.database.port,
        config.database.databaseName);        

    context = ManagedContext(dataModel, psc);
  }
}
```

A YAML configuration file loaded by this application must look like this:

```
database:
  username: bob
  password: bobspassword
  host: localhost
  port: 5432
  databaseName: my_app
```

A `PersistentStore` is an interface. Concrete implementations - like `PostgreSQLPersistentStore` - implement that interface to transmit data to a database in the format it expects. A `PostgreSQLPersistentStore` will automatically connect and maintain a persistent connection to a database. If the connection is lost for some reason, it will automatically reconnect the next time a query is executed. If a connection cannot be established, an exception is thrown that sends a 503 status code response by default.
