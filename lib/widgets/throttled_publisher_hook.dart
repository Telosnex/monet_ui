import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:monet_ui/util/throttled_publisher.dart';

class ThrottledPublisherResult {
  final void Function(void Function()) publish;
  final Future<void> Function() flush;

  const ThrottledPublisherResult(this.publish, this.flush);
}

/// Hook that provides a throttled publisher for function calls.
///
/// Usage:
/// ```dart
/// final throttled = useThrottledPublisher(Duration(milliseconds: 16));
///
/// // In a scroll listener:
/// scrollController.addListener(() {
///   throttled.publish(() {
///     // This will be throttled to 16ms intervals
///     updateScrollBasedUI();
///   });
/// });
/// ```
ThrottledPublisherResult useThrottledPublisher(Duration duration) {
  final publisherRef = useRef<ThrottledPublisher?>(null);

  // Create publisher on first use
  if (publisherRef.value == null) {
    publisherRef.value = ThrottledPublisher(interval: duration);
  }

  // Update interval if it changes
  // ignore: function-always-returns-null
  useEffect(() {
    if (publisherRef.value?.interval != duration) {
      publisherRef.value?.dispose();
      publisherRef.value = ThrottledPublisher(interval: duration);
    }
    return null;
  }, [duration]);

  // Dispose on unmount
  useEffect(() {
    return () {
      publisherRef.value?.dispose();
      publisherRef.value = null;
    };
  }, []);

  // Memoize the result to avoid recreating functions
  return useMemoized(() {
    final publisher = publisherRef.value!;

    return ThrottledPublisherResult(publisher.publish, publisher.flush);
  }, [publisherRef.value]);
}
