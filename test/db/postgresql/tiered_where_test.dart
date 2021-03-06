import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import '../model_graph.dart';
import '../../helpers.dart';

/*
  If you're going to look at these tests, you'll have to draw out the model graph defined in model_graph.dart
  to make sense of it. The size of it makes it difficult to draw in ASCII.

  Explicit join = Using joinOn/joinMany to create a new sub-Query
  Implicit join = Using the property of a related object in the 'where' of a Query
 */

void main() {
  List<RootObject> rootObjects;
  ManagedContext ctx;
  setUpAll(() async {
    ctx = await contextWithModels([
      RootObject,
      RootJoinObject,
      OtherRootObject,
      ChildObject,
      GrandChildObject
    ]);
    rootObjects = await populateModelGraph(ctx);
  });

  tearDownAll(() async {
    await ctx.persistentStore.close();
  });

  group("Joins return appropriate properties", () {
    // This group ensures that the right fields are returned and turned into objects,
    // not whether or not the right objects are returned.
    test("Values are not returned from implicitly joined tables", () async {
      var q = new Query<RootObject>()..where.child.cid = whereGreaterThan(1);
      var results = await q.fetch();

      for (var r in results) {
        expect(r.backingMap.containsKey("child"), false);
        expect(r.backingMap.length, r.entity.defaultProperties.length);
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }
      }
    });

    test("Objects have default values when explicitly joined", () async {
      var q = new Query<RootObject>()..join(object: (r) => r.child);
      var results = await q.fetch();

      for (var r in results) {
        expect(
            r.backingMap.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backingMap.length,
              r.child.entity.defaultProperties.length);
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }
        }
      }
    });

    test(
        "Query with both explicit and implicit join only returns values for explicit join",
        () async {
      var q = new Query<RootObject>();

      q.join(object: (r) => r.child)..where.grandChild.gid = whereGreaterThan(1);
      var results = await q.fetch();

      for (var r in results) {
        expect(
            r.backingMap.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        // Child may be null, but even if it is the key must be in the map
        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(r.child.backingMap.length,
              r.child.entity.defaultProperties.length);
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }
          expect(r.child.backingMap.containsKey("grandChild"), false);
        }
      }
    });

    test("Nested explicit joins return values for all tables", () async {
      var q = new Query<RootObject>();

      q.join(object: (r) => r.child)..join(object: (c) => c.grandChild);

      var results = await q.fetch();
      for (var r in results) {
        expect(
            r.backingMap.length,
            r.entity.defaultProperties.length +
                1); // +1 is for key containing 'child'
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }

        expect(r.backingMap.containsKey("child"), true);
        if (r.child != null) {
          expect(
              r.child.backingMap.length,
              r.child.entity.defaultProperties.length +
                  1); // +1 is for key containing 'grandchild
          for (var property in r.child.entity.defaultProperties) {
            expect(r.child.backingMap.containsKey(property), true);
          }

          expect(r.child.backingMap.containsKey("grandChild"), true);
          if (r.child.grandChild != null) {
            expect(r.child.grandChild.backingMap.length,
                r.child.grandChild.entity.defaultProperties.length);
            for (var property in r.child.grandChild.entity.defaultProperties) {
              expect(r.child.grandChild.backingMap.containsKey(property), true);
            }
          }
        }
      }

      expect(results.any((r) => r.child?.grandChild != null), true);
    });

    test("Query can specify resultProperties values when explicitly joined",
        () async {
      var q = new Query<RootObject>()..returningProperties((r) => [r.rid]);

      q.join(object: (r) => r.child)..returningProperties((c) => [c.cid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backingMap.length, 2 /* id + child */);
        expect(r.backingMap.containsKey("rid"), true);
        expect(r.backingMap.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backingMap.length, 1);
          expect(r.child.backingMap.containsKey("cid"), true);
        }
      }
    });

    test(
        "Query with nested explicit joins can specify resultProperties for all objects",
        () async {
      var q = new Query<RootObject>()..returningProperties((r) => [r.rid]);

      var cq = q.join(object: (r) => r.child)..returningProperties((c) => [c.cid]);

      cq.join(object: (c) => c.grandChild)..returningProperties((g) => [g.gid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backingMap.length, 2 /* id + child */);
        expect(r.backingMap.containsKey("rid"), true);
        expect(r.backingMap.containsKey("child"), true);

        if (r.child != null) {
          expect(r.child.backingMap.length, 2 /* id + grandchild */);
          expect(r.child.backingMap.containsKey("cid"), true);
          expect(r.child.backingMap.containsKey("grandChild"), true);

          if (r.child?.grandChild != null) {
            expect(r.child.grandChild.backingMap.length, 1);
            expect(r.child.grandChild.backingMap.containsKey("gid"), true);
          }
        }
      }
      expect(results.any((r) => r.child?.grandChild != null), true);
    });
  });

  group("With where clauses on root object", () {
    test("Implicity joining related object", () async {
      var q = new Query<RootObject>()..where.child.cid = whereEqualTo(1);
      var results = await q.fetch();

      var inMemoryMatch = rootObjects.firstWhere((r) => r.child?.cid == 1);
      expect(results.length, 1);
      expect(results.first.rid, inMemoryMatch.rid);
    });

    test("Explicitly joining related object", () async {
      var q = new Query<RootObject>()..where.rid = whereGreaterThan(1);

      q.join(set: (r) => r.children)..where.cid = whereGreaterThan(5);

      var results = await q.fetch();
      expect(results.length, rootObjects.length - 1);
      expect(results.any((r) => r.rid == 1), false);

      for (var r in results) {
        expect(r.children, isNotNull);
        expect(r.children.any((c) => c.cid <= 5), false);
      }

      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);
    });

    test("Explicitly joining related objects, nested implicit join", () async {
      var q = new Query<RootObject>()..where.rid = whereEqualTo(1);
      q.join(set: (r) => r.children)
        ..where.grandChildren.haveAtLeastOneWhere.gid = whereEqualTo(5);

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.children.length, 1);
      expect(results.first.children.first.grandChildren, isNull);
    });

    test("Explicitly joining related objects and nested related objects",
        () async {
      var q = new Query<RootObject>()..where.rid = whereEqualTo(1);

      var cq = q.join(set: (r) => r.children);

      cq.join(set: (c) => c.grandChildren)..where.gid = whereLessThan(6);

      var results = await q.fetch();
      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.children.length,
          rootObjects.firstWhere((r) => r.rid == 1).children.length);
      expect(
          results.first.children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .length,
          1);
      expect(
          results.first.children
              .where((c) => c.cid != 2)
              .every((c) => c.grandChildren.length == 0),
          true);
    });

    test("Nested implicit joins are combined", () async {
      var q = new Query<RootObject>()
        ..where.children.haveAtLeastOneWhere.cid = whereEqualTo(2)
        ..where
            .children
            .haveAtLeastOneWhere
            .grandChildren
            .haveAtLeastOneWhere
            .gid = whereLessThan(8);
      var results = await q.fetch();

      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.backingMap.containsKey("children"), false);

      q = new Query<RootObject>()
        ..where.children.haveAtLeastOneWhere.cid = whereEqualTo(2)
        ..where
            .children
            .haveAtLeastOneWhere
            .grandChildren
            .haveAtLeastOneWhere
            .gid = whereGreaterThan(8);
      results = await q.fetch();
      expect(results.length, 0);
    });
  });

  group("With where clauses on child object", () {
    test("Explicit joins do not impact returned root objects", () async {
      var q = new Query<RootObject>();
      q.join(object: (r) => r.child)..where.cid = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.child?.cid == 1).child, isNotNull);
      expect(
          results.where((r) => r.rid != 1).every(
              (r) => r.backingMap.containsKey("child") && r.child == null),
          true);
    });

    test(
        "Implicit join on child affects child object returned, but not root objects",
        () async {
      var q = new Query<RootObject>();
      q.join(set: (r) => r.children)..where.grandChild.gid = whereEqualTo(4);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.first.cid, 2);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    });

    // Filter child by values in both child and grandchild
    test(
        "Where clause on child + implicit join to granchild can find overly identified object",
        () async {
      var q = new Query<RootObject>();
      q.join(set: (r) => r.children)
        ..where.cid = whereEqualTo(2)
        ..where.grandChildren.haveAtLeastOneWhere.gid = whereEqualTo(6);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.first.cid, 2);
      expect(results.firstWhere((r) => r.rid == 1).children.first.grandChildren,
          isNull);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    });

    test(
        "Where clause on child + implicit join to grandchild returns empty if conditions conflict",
        () async {
      var q = new Query<RootObject>();
      q.join(set: (r) => r.children)
        ..where.cid = whereEqualTo(4)
        ..where.grandChildren.haveAtLeastOneWhere.gid = whereEqualTo(6);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.every((r) => r.children.isEmpty), true);
    });

    test(
        "Where clause on child + implicit join to grandchild returns appropriate matches",
        () async {
      var q = new Query<RootObject>();
      q.join(set: (r) => r.children)
        ..where.cid = whereLessThanEqualTo(5)
        ..where.grandChildren.haveAtLeastOneWhere.gid = whereGreaterThan(5);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 2);
      expect(
          results.firstWhere((r) => r.rid == 1).children.any((c) => c.cid == 2),
          true);
      expect(
          results.firstWhere((r) => r.rid == 1).children.any((c) => c.cid == 4),
          true);
      expect(results.where((r) => r.rid != 1).every((r) => r.children.isEmpty),
          true);
    });
  });

  group("With where clauses on grandchild object", () {
    test(
        "Explicit join on child and grandchild, retains all root objects and child objects",
        () async {
      var q = new Query<RootObject>();
      var cq = q.join(set: (r) => r.children);
      cq.join(set: (c) => c.grandChildren)..where.gid = whereEqualTo(5);

      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .length,
          1);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .firstWhere((c) => c.cid == 2)
              .grandChildren
              .first
              .gid,
          5);
      expect(
          results
              .firstWhere((r) => r.rid == 1)
              .children
              .where((c) => c.cid != 2)
              .every((c) => c.grandChildren.length == 0),
          true);

      expect(
          results
              .where((r) => r.rid != 1)
              .every((r) => r.children.every((c) => c.grandChildren.isEmpty)),
          true);
    });
  });

  group("Implicit and explicit same table", () {
    test(
        "An explicit and implicit join on the same table return the keys of the explicit join",
        () async {
      var q = new Query<RootObject>()..where.child.value1 = whereGreaterThan(0);

      q.join(object: (r) => r.child)..returningProperties((c) => [c.cid]);

      var results = await q.fetch();
      for (var r in results) {
        expect(r.backingMap.length,
            r.entity.defaultProperties.length + 1); // +1 is for child
        for (var property in r.entity.defaultProperties) {
          expect(r.backingMap.containsKey(property), true);
        }
        expect(r.child.backingMap.length, 1);
        expect(r.child.backingMap.containsKey("cid"), true);
      }
    });

    test(
        "An explicit and implicit join on same table combine predicates and have appropriate impact on root objects",
        () async {
      var q = new Query<RootObject>()
        ..where.children.haveAtLeastOneWhere.cid = whereGreaterThan(5);

      q.join(set: (r) => r.children)..where.cid = whereLessThan(10);

      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(
          results.firstWhere((r) => r.rid == 2).children.any((c) => c.cid == 7),
          true);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);
      expect(
          results.firstWhere((r) => r.rid == 4).children.any((c) => c.cid == 9),
          true);
    });
  });

  group("Filtering by existence", () {
    test("WhereNotNull on hasMany", () async {
      var q = new Query<RootObject>()..where.children = whereNotNull;
      var results = await q.fetch();

      expect(results.length, 3);
      expect(results.any((r) => r.rid == 1), true);
      expect(results.any((r) => r.rid == 2), true);
      expect(results.any((r) => r.rid == 4), true);
      expect(results.every((r) => r.backingMap["children"] == null), true);
    });

    test("WhereNull on hasMany", () async {
      var q = new Query<RootObject>()..where.children = whereNull;
      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.any((r) => r.rid == 3), true);
      expect(results.any((r) => r.rid == 5), true);
      expect(results.every((r) => r.backingMap["children"] == null), true);
    });

    test("WhereNotNull on hasOne", () async {
      var q = new Query<RootObject>()..where.child = whereNotNull;
      var results = await q.fetch();

      expect(results.length, 3);
      expect(results.any((r) => r.rid == 1), true);
      expect(results.any((r) => r.rid == 2), true);
      expect(results.any((r) => r.rid == 3), true);
      expect(results.every((r) => r.backingMap["child"] == null), true);
    });

    test("WhereNull on hasOne", () async {
      var q = new Query<RootObject>()..where.child = whereNull;
      var results = await q.fetch();

      expect(results.length, 2);
      expect(results.any((r) => r.rid == 4), true);
      expect(results.any((r) => r.rid == 5), true);
      expect(results.every((r) => r.backingMap["child"] == null), true);
    });
  });

  group("Same entity, different relationship property", () {
    test("Where clause on root object for two properties with same entity type",
        () async {
      var q = new Query<RootObject>()
        ..where.children.haveAtLeastOneWhere.cid = whereGreaterThan(3)
        ..where.child.cid = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length, 1);
      expect(results.first.rid, 1);
      expect(results.first.child, isNull);
      expect(results.first.children, isNull);

      q = new Query<RootObject>()
        ..where.children.haveAtLeastOneWhere.cid = whereGreaterThan(10)
        ..where.child.cid = whereEqualTo(1);
      results = await q.fetch();

      expect(results.length, 0);
    });

    test("Join on on two properties with same entity type", () async {
      var q = new Query<RootObject>();

      q.join(set: (r) => r.children)..where.cid = whereGreaterThan(3);

      q.join(object: (r) => r.child)..where.cid = whereEqualTo(1);
      var results = await q.fetch();

      expect(results.length, rootObjects.length);
      expect(results.firstWhere((r) => r.rid == 1).child.cid, 1);
      expect(results.firstWhere((r) => r.rid == 1).children.length, 2);
      expect(results.firstWhere((r) => r.rid == 2).children.length, 1);
      expect(results.firstWhere((r) => r.rid == 4).children.length, 1);

      expect(
          results.where((r) => r.rid != 1).every((r) => r.child == null), true);
    });
  });
}
