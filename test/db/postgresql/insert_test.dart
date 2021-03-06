// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../../helpers.dart';
import 'package:postgres/postgres.dart';

void main() {
  ManagedContext context;

  tearDown(() async {
    await context?.persistentStore?.close();
    context = null;
  });

  test("Accessing valueObject of Query automatically creates an instance",
      () async {
    context = await contextWithModels([TestModel]);

    var q = new Query<TestModel>()..values.id = 1;

    expect(q.values.id, 1);
  });

  test("Insert Bad Key", () async {
    context = await contextWithModels([TestModel]);

    var insertReq = new Query<TestModel>()
      ..valueMap = {
        "name": "bob",
        "emailAddress": "bk@a.com",
        "bad_key": "doesntmatter"
      };

    var successful = false;
    try {
      await insertReq.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(
          e.toString(), "Property bad_key in values does not exist on simple");
      expect(e.event, QueryExceptionEvent.requestFailure);
    }
    expect(successful, false);
  });

  test("Inserting an object that violated a unique constraint fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "dup@a.com";

    var insertReq = new Query<TestModel>()..values = m;
    await insertReq.insert();

    var insertReqDup = new Query<TestModel>()..values = m;

    var successful = false;
    try {
      await insertReqDup.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.conflict);
      expect((e.underlyingException as PostgreSQLException).code, "23505");
    }
    expect(successful, false);

    m.emailAddress = "dup1@a.com";
    var insertReqFollowup = new Query<TestModel>()..values = m;

    var result = await insertReqFollowup.insert();

    expect(result.emailAddress, "dup1@a.com");
  });

  test("Insert an object that violates a unique set constraint fails with conflict", () async {
    context = await contextWithModels([MultiUnique]);

    var q = new Query<MultiUnique>()
      ..values.a = "a"
      ..values.b = "b";

    await q.insert();

    q = new Query<MultiUnique>()
      ..values.a = "a"
      ..values.b = "a";

    await q.insert();

    q = new Query<MultiUnique>()
      ..values.a = "a"
      ..values.b = "b";
    try {
      await q.insert();
      expect(true, false);
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.conflict);
    }
  });

  test("Inserting an object works and returns the object", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "1@a.com";

    var insertReq = new Query<TestModel>()..values = m;

    var result = await insertReq.insert();

    expect(result is TestModel, true);
    expect(result.id, greaterThan(0));
    expect(result.name, "bob");
    expect(result.emailAddress, "1@a.com");
  });

  test("Inserting an object works", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()
      ..name = "bob"
      ..emailAddress = "2@a.com";

    var insertReq = new Query<TestModel>()..values = m;

    var result = await insertReq.insert();

    var readReq = new Query<TestModel>()
      ..predicate =
          new QueryPredicate("emailAddress = @email", {"email": "2@a.com"});

    result = await readReq.fetchOne();
    expect(result.name, "bob");
  });

  test("Inserting an object without required key fails", () async {
    context = await contextWithModels([TestModel]);

    var m = new TestModel()..emailAddress = "required@a.com";

    var insertReq = new Query<TestModel>()..values = m;

    var successful = false;
    try {
      await insertReq.insert();
      successful = true;
    } on QueryException catch (e) {
      expect(e.event, QueryExceptionEvent.requestFailure);
      expect((e.underlyingException as PostgreSQLException).code, "23502");
    }
    expect(successful, false);
  });

  test(
      "Inserting an object via a values map works and returns appropriate object",
      () async {
    context = await contextWithModels([TestModel]);

    var insertReq = new Query<TestModel>()
      ..valueMap = {"id": 20, "name": "Bob"}
      ..returningProperties((t) => [t.id, t.name]);

    var value = await insertReq.insert();
    expect(value.id, 20);
    expect(value.name, "Bob");
    expect(value.asMap().containsKey("emailAddress"), false);

    insertReq = new Query<TestModel>()
      ..valueMap = {"id": 21, "name": "Bob"}
      ..returningProperties((t) => [t.id, t.name, t.emailAddress]);

    value = await insertReq.insert();
    expect(value.id, 21);
    expect(value.name, "Bob");
    expect(value.emailAddress, null);
    expect(value.asMap().containsKey("emailAddress"), true);
    expect(value.asMap()["emailAddress"], null);
  });

  test("Inserting object with relationship returns embedded object", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var u = new GenUser()..name = "Joe";
    var q = new Query<GenUser>()..values = u;
    u = await q.insert();

    var p = new GenPost()
      ..owner = u
      ..text = "1";
    var pq = new Query<GenPost>()..values = p;
    p = await pq.insert();

    expect(p.id, greaterThan(0));
    expect(p.owner.id, greaterThan(0));
  });

  test("Timestamp inserted correctly by default", () async {
    context = await contextWithModels([GenTime]);

    var t = new GenTime()..text = "hey";

    var q = new Query<GenTime>()..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(
        result.dateCreated.difference(new DateTime.now()).inSeconds <= 0, true);
  });

  test("Can insert timestamp manually", () async {
    context = await contextWithModels([GenTime]);

    var dt = new DateTime.now();
    var t = new GenTime()
      ..dateCreated = dt
      ..text = "hey";

    var q = new Query<GenTime>()..values = t;

    var result = await q.insert();

    expect(result.dateCreated is DateTime, true);
    expect(
        result.dateCreated.difference(dt).inSeconds == 0, true);
  });

  test("Transient values work correctly", () async {
    context = await contextWithModels([TransientModel]);

    var t = new TransientModel()..value = "foo";

    var q = new Query<TransientModel>()..values = t;
    var result = await q.insert();
    expect(result.transientValue, null);
  });

  test("JSON -> Insert with List", () async {
    context = await contextWithModels([GenUser, GenPost]);

    var json = {
      "name": "Bob",
      "posts": [
        {"text": "Post"}
      ]
    };

    var u = new GenUser()..readFromMap(json);

    var q = new Query<GenUser>()..values = u;

    var result = await q.insert();
    expect(result.id, greaterThan(0));
    expect(result.name, "Bob");
    expect(result.posts, isNull);

    var pq = new Query<GenPost>();
    expect(await pq.fetch(), hasLength(0));
  });

  test("Insert object with no keys", () async {
    context = await contextWithModels([BoringObject]);

    var q = new Query<BoringObject>();
    var result = await q.insert();
    expect(result.id, greaterThan(0));
  });

  test("Can use public accessor to set private property in values", () async {
    context = await contextWithModels([PrivateField]);

    await (new Query<PrivateField>()..values.public = "x").insert();
    var q = new Query<PrivateField>()
      ..where.public = "x";
    var result = await q.fetchOne();
    expect(result.public, "x");
  });

  test("Can use enum to set property to be stored in db", () async {
    context = await contextWithModels([EnumObject]);

    var q = new Query<EnumObject>()
      ..values.enumValues = EnumValues.efgh;

    var result = await q.insert();
    expect(result.enumValues, EnumValues.efgh);
  });
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {}

class _TestModel {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedColumnAttributes(nullable: true, unique: true)
  String emailAddress;

  static String tableName() {
    return "simple";
  }
}

class GenUser extends ManagedObject<_GenUser> implements _GenUser {}

class _GenUser {
  @managedPrimaryKey
  int id;
  String name;

  ManagedSet<GenPost> posts;
}

class GenPost extends ManagedObject<_GenPost> implements _GenPost {}

class _GenPost {
  @managedPrimaryKey
  int id;
  String text;

  @ManagedRelationship(#posts)
  GenUser owner;
}

class GenTime extends ManagedObject<_GenTime> implements _GenTime {}

class _GenTime {
  @managedPrimaryKey
  int id;

  String text;

  @ManagedColumnAttributes(defaultValue: "(now() at time zone 'utc')")
  DateTime dateCreated;
}

class TransientModel extends ManagedObject<_Transient> implements _Transient {
  @managedTransientAttribute
  String transientValue;
}

class _Transient {
  @managedPrimaryKey
  int id;

  String value;
}

class BoringObject extends ManagedObject<_BoringObject> implements _BoringObject {}
class _BoringObject {
  @managedPrimaryKey
  int id;
}

class PrivateField extends ManagedObject<_PrivateField> implements _PrivateField {
  set public(String p) {
    _private = p;
  }

  String get public => _private;
}
class _PrivateField {
  @managedPrimaryKey
  int id;

  String _private;
}

class EnumObject extends ManagedObject<_EnumObject> implements _EnumObject {}
class _EnumObject {
  @managedPrimaryKey
  int id;

  EnumValues enumValues;
}

class MultiUnique extends ManagedObject<_MultiUnique> implements _MultiUnique {}
@ManagedTableAttributes.unique(const [#a, #b])
class _MultiUnique {
  @managedPrimaryKey
  int id;

  String a;
  String b;
}

enum EnumValues {
  abcd, efgh, other18
}