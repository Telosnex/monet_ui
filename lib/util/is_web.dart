// This is convenient in situations where flutter/foundation.dart is not
// available, such as in code that appears in a Squadron worker.

export 'package:monet_ui/util/is_web_stub.dart'
    if (dart.library.js_interop) 'package:monet_ui/util/is_web_web.dart'
    if (dart.library.io) 'package:monet_ui/util/is_web_io.dart';
