// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.runner.browser.phantom_js;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../util/io.dart';
import 'browser.dart';

/// The PhantomJS script that opens the host page.
final _script = """
var system = require('system');
var page = require('webpage').create();

// Pipe browser messages to the process's stdout. This isn't used by default,
// but it can be useful for debugging.
page.onConsoleMessage = function(message) {
  console.log(message);
}

page.open(system.args[1], function(status) {
  if (status !== "success") phantom.exit(1);
});
""";

/// A class for running an instance of PhantomJS.
///
/// Any errors starting or running the process are reported through [onExit].
class PhantomJS implements Browser {
  /// The underlying process.
  Process _process;

  Future get onExit => _onExitCompleter.future;
  final _onExitCompleter = new Completer();

  /// A future that completes when the browser process has started.
  ///
  /// This is used to ensure that [close] works regardless of when it's called.
  Future get _onProcessStarted => _onProcessStartedCompleter.future;
  final _onProcessStartedCompleter = new Completer();

  /// Starts a new instance of PhantomJS open to the given [url], which may be a
  /// [Uri] or a [String].
  ///
  /// If [executable] is passed, it's used as the PhantomJS executable.
  /// Otherwise the default executable name for the current OS will be used.
  PhantomJS(url, {String executable}) {
    if (executable == null) {
      executable = Platform.isWindows ? "phantomjs.exe" : "phantomjs";
    }

    // Don't return a Future here because there's no need for the caller to wait
    // for the process to actually start. They should just wait for the HTTP
    // request instead.
    withTempDir((dir) {
      var script = p.join(dir, "script.js");
      new File(script).writeAsStringSync(_script);

      return Process.start(executable, [script, url.toString()])
          .then((process) {
        // PhantomJS synchronously emits standard output, which means that if we
        // don't drain its stdout stream it can deadlock.
        process.stdout.listen((_) {});

        _process = process;
        _onProcessStartedCompleter.complete();

        return _process.exitCode;
      });
    }).then((exitCode) {
      if (exitCode != 0) throw "PhantomJS failed with exit code $exitCode.";
    }).then(_onExitCompleter.complete)
        .catchError(_onExitCompleter.completeError);
  }

  Future close() {
    _onProcessStarted.then((_) => _process.kill());

    // Swallow exceptions. The user should explicitly use [onExit] for these.
    return onExit.catchError((_) {});
  }
}