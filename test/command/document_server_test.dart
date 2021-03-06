import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;

import 'cli_helpers.dart';

Directory temporaryDirectory = new Directory.fromUri(Directory.current.uri.resolve("test_project"));

void main() {
  setUpAll(() {
    Process.runSync("pub", ["global", "activate", "-spath", Directory.current.path]);
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test("Can get API reference", () async {
    await runWith(["test_project", "-t", "db"]);

    var process = await Process.start("pub", ["global", "run", "aqueduct:aqueduct", "document", "serve"],
        runInShell: true, workingDirectory: temporaryDirectory.path);

    var available = new Completer();
    var aggregateOutput = "";
    var sub = process.stdout.listen((bytes) {
      var logItem = UTF8.decode(bytes);
      aggregateOutput += logItem;
      if (aggregateOutput.contains("listening")) {
        available?.complete();
        available = null;
      }
    });

    await available.future;

    var response = await http.get("http://localhost:8111");
    expect(response.body, contains("redoc spec-url='swagger.json'"));

    await sub.cancel();

    process.kill();
  });
}

Future<CLIResult> runWith(List<String> args) {
  var allArgs = ["create"];
  allArgs.addAll(args);

  return runAqueductProcess(allArgs, Directory.current);
}