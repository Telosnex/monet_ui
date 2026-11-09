import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'package:loggy/loggy.dart';

import 'package:monet_ui/widgets/monet_perf_debug_switches.dart';

const _kBytesPerMiB = 1024 * 1024;

/// Production limits for renderer-owned raster images.
///
/// A negative aggregate limit means that images live for their owner's
/// lifetime instead of competing in a process-wide LRU. We still account for
/// current/peak bytes, clear on memory pressure, and reject a single unusually
/// large image. Tests can configure finite limits to exercise admission logic.
abstract final class RasterMaskImageCacheConfig {
  static const int unlimited = -1;
  static const int maxBytes = unlimited;
  static const int maxImageBytes = 8 * _kBytesPerMiB;
}

/// Approximate retained GPU memory owned by one raster-mask cache.
///
/// Impeller snapshots are normally four-byte RGBA textures with a mip chain,
/// so accounting uses 16/3 bytes per physical pixel. Driver padding and glyph
/// atlas memory are not included; this is admission control, not process RSS.
@immutable
class RasterMaskImageCacheStats {
  const RasterMaskImageCacheStats({
    required this.estimatedBytes,
    required this.peakEstimatedBytes,
    required this.imageCount,
    required this.evictions,
    required this.rejections,
    required this.maxBytes,
    required this.maxImageBytes,
    required this.perImageRejections,
    required this.groupRejections,
    required this.visibleSetRejections,
  });

  final int estimatedBytes;
  final int peakEstimatedBytes;
  final int imageCount;
  final int evictions;
  final int rejections;

  /// `-1` means aggregate cache size is unlimited.
  final int maxBytes;
  final int maxImageBytes;
  final int perImageRejections;
  final int groupRejections;
  final int visibleSetRejections;
}

enum RasterMaskRejection { perImage, group, visibleSet }

/// Renderer-owned image accounting with optional finite admission/LRU policy.
/// Each consumer owns a separate instance, keys, limits and eviction callbacks;
/// a memory-pressure event clears every registered instance independently.
class RasterMaskImageBudget with WidgetsBindingObserver {
  RasterMaskImageBudget({
    required this.debugLabel,
    required int maxBytes,
    required int maxImageBytes,
  }) : assert(
         maxBytes >= 0 || maxBytes == RasterMaskImageCacheConfig.unlimited,
       ),
       assert(maxImageBytes >= 0),
       _defaultMaxBytes = maxBytes,
       _defaultMaxImageBytes = maxImageBytes,
       _maxBytes = maxBytes,
       _maxImageBytes = maxImageBytes {
    WidgetsBinding.instance.addObserver(this);
    // Same telemetry behavior as the original text cache. Every cache owns its
    // own timer/counters; fake-async widget tests must not retain pending timers.
    final isWidgetTestBinding = WidgetsBinding.instance.runtimeType
        .toString()
        .contains('TestWidgetsFlutterBinding');
    if (kDebugMode && !isWidgetTestBinding) {
      _telemetryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        String mib(int bytes) => (bytes / _kBytesPerMiB).toStringAsFixed(2);
        final maxMiB = _hasAggregateLimit ? mib(_maxBytes) : 'unlimited';
        logInfo(
          '[$debugLabel] estimatedMiB=${mib(_estimatedBytes)} '
          'peakMiB=${mib(_peakEstimatedBytes)} images=${_entries.length} '
          'maxMiB=$maxMiB maxImageMiB=${mib(_maxImageBytes)} '
          'evictions=$_evictions rejections=$_rejections',
        );
      });
    }
  }

  final String debugLabel;
  final int _defaultMaxBytes;
  final int _defaultMaxImageBytes;
  Timer? _telemetryTimer;

  void dispose() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    clear();
  }

  final LinkedHashMap<Object, _RasterMaskImageEntry> _entries =
      LinkedHashMap.identity();
  int _maxBytes;
  int _maxImageBytes;
  int _estimatedBytes = 0;
  int _peakEstimatedBytes = 0;
  int _evictions = 0;
  int _rejections = 0;
  int _perImageRejections = 0;
  int _groupRejections = 0;
  int _visibleSetRejections = 0;
  RasterMaskRejection? _lastRejection;
  // Disjoint sums: touched this frame, and touched last frame but not this
  // one. Their complement is idle for a full frame. Keep retry checks O(1).
  bool _frameByteAccountingInitialized = false;
  int _currentFrameBytes = 0;
  int _previousFrameBytes = 0;
  int _availabilityRevision = 0;
  int _frame = 0;
  bool _frameAdvanceScheduled = false;
  bool _isClearing = false;

  bool get _hasAggregateLimit => _maxBytes >= 0;

  /// For eviction callbacks only. Bulk clear (notably memory pressure) must
  /// not immediately repopulate all images via ordinary idle-capacity retry.
  bool get isClearing => _isClearing;

  RasterMaskImageCacheStats get stats => .new(
    estimatedBytes: _estimatedBytes,
    peakEstimatedBytes: _peakEstimatedBytes,
    imageCount: _entries.length,
    evictions: _evictions,
    rejections: _rejections,
    maxBytes: _maxBytes,
    maxImageBytes: _maxImageBytes,
    perImageRejections: _perImageRejections,
    groupRejections: _groupRejections,
    visibleSetRejections: _visibleSetRejections,
  );

  int get availabilityRevision => _availabilityRevision;
  RasterMaskRejection? get lastRejection => _lastRejection;

  /// A memoized capacity failure may recover without a release: prior owners
  /// can go offstage while retaining their images. Only retry if the request
  /// fits without evicting anything painted this OR the preceding frame.
  /// The subsequent reservation must also use `protectPreviousFrame: true`.
  bool canRetryAfterIdleFrame(int requestedBytes) {
    if (!_hasAggregateLimit) return true;
    _frameForCurrentPaint();
    return requestedBytes + _currentFrameBytes + _previousFrameBytes <=
        _maxBytes;
  }

  /// Atomically admits all requested images or none of them.
  ///
  /// Images painted earlier in this frame are protected. Overflow therefore
  /// settles on a stable visible set rather than recreating masks in paint
  /// order every frame; images not painted this frame are normal LRU victims.
  bool tryReserveAll(
    List<RasterMaskImageReservation> reservations, {
    bool protectPreviousFrame = false,
  }) {
    if (reservations.isEmpty) return true;
    final frame = _hasAggregateLimit ? _frameForCurrentPaint() : 0;
    var additionalBytes = 0;
    for (final reservation in reservations) {
      assert(!_entries.containsKey(reservation.key));
      if (reservation.estimatedBytes > _maxImageBytes ||
          (_hasAggregateLimit && reservation.estimatedBytes > _maxBytes)) {
        _reject(reservations, reason: .perImage);
        return false;
      }
      additionalBytes += reservation.estimatedBytes;
    }
    if (_hasAggregateLimit && additionalBytes > _maxBytes) {
      _reject(reservations, reason: .group);
      return false;
    }

    final victims = <MapEntry<Object, _RasterMaskImageEntry>>[];
    var bytesAfterEviction = _estimatedBytes;
    if (_hasAggregateLimit &&
        bytesAfterEviction + additionalBytes > _maxBytes) {
      for (final entry in _entries.entries) {
        if (entry.value.lastUsedFrame <
            frame - (protectPreviousFrame ? 1 : 0)) {
          victims.add(entry);
          bytesAfterEviction -= entry.value.estimatedBytes;
          if (bytesAfterEviction + additionalBytes <= _maxBytes) break;
        }
      }
    }
    if (_hasAggregateLimit &&
        bytesAfterEviction + additionalBytes > _maxBytes) {
      _reject(reservations, reason: .visibleSet);
      return false;
    }
    for (final victim in victims) {
      _entries.remove(victim.key);
      _estimatedBytes -= victim.value.estimatedBytes;
      _forgetFrameBytes(victim.value);
      _evictions++;
      victim.value.evict();
    }

    for (final reservation in reservations) {
      _entries[reservation.key] = _RasterMaskImageEntry(
        estimatedBytes: reservation.estimatedBytes,
        lastUsedFrame: frame,
        evict: reservation.evict,
      );
      _estimatedBytes += reservation.estimatedBytes;
      if (_hasAggregateLimit) {
        _currentFrameBytes += reservation.estimatedBytes;
      }
    }
    _peakEstimatedBytes = math.max(_peakEstimatedBytes, _estimatedBytes);
    return true;
  }

  void touch(Object key) {
    if (!_hasAggregateLimit) return;
    _ensureFrameByteAccounting();
    final entry = _entries.remove(key);
    if (entry == null) return;
    final frame = _frameForCurrentPaint();
    if (entry.lastUsedFrame != frame) {
      _forgetFrameBytes(entry);
      _currentFrameBytes += entry.estimatedBytes;
      entry.lastUsedFrame = frame;
    }
    _entries[key] = entry;
  }

  void release(Object key) {
    if (_hasAggregateLimit) _ensureFrameByteAccounting();
    final entry = _entries.remove(key);
    if (entry == null) return;
    _estimatedBytes -= entry.estimatedBytes;
    if (_hasAggregateLimit) _forgetFrameBytes(entry);
    _availabilityRevision++;
  }

  void clear() {
    if (_entries.isEmpty) return;
    final victims = _entries.values.toList(growable: false);
    _entries.clear();
    _estimatedBytes = 0;
    _currentFrameBytes = 0;
    _previousFrameBytes = 0;
    _availabilityRevision++;
    _isClearing = true;
    try {
      for (final victim in victims) {
        victim.evict();
      }
    } finally {
      _isClearing = false;
    }
  }

  @override
  void didHaveMemoryPressure() => clear();

  void debugConfigure({required int maxBytes, required int maxImageBytes}) {
    assert(maxBytes >= 0 || maxBytes == RasterMaskImageCacheConfig.unlimited);
    assert(maxImageBytes >= 0);
    clear();
    _maxBytes = maxBytes;
    _maxImageBytes = maxImageBytes;
    _availabilityRevision++;
    _resetCounters();
  }

  void debugReset() {
    clear();
    _maxBytes = _defaultMaxBytes;
    _maxImageBytes = _defaultMaxImageBytes;
    _availabilityRevision++;
    _resetCounters();
  }

  int _frameForCurrentPaint() {
    _ensureFrameByteAccounting();
    if (!_frameAdvanceScheduled) {
      _frameAdvanceScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _previousFrameBytes = _currentFrameBytes;
        _currentFrameBytes = 0;
        _frame++;
        _frameAdvanceScheduled = false;
      });
    }
    return _frame;
  }

  void _ensureFrameByteAccounting() {
    if (_frameByteAccountingInitialized) return;
    // Hot reload can add these sums to an already-populated budget. Rebuild
    // once, not by scanning the LRU on every denial/paint.
    _currentFrameBytes = 0;
    _previousFrameBytes = 0;
    for (final entry in _entries.values) {
      if (entry.lastUsedFrame == _frame) {
        _currentFrameBytes += entry.estimatedBytes;
      } else if (entry.lastUsedFrame == _frame - 1) {
        _previousFrameBytes += entry.estimatedBytes;
      }
    }
    _frameByteAccountingInitialized = true;
  }

  void _forgetFrameBytes(_RasterMaskImageEntry entry) {
    if (entry.lastUsedFrame == _frame) {
      _currentFrameBytes -= entry.estimatedBytes;
    } else if (entry.lastUsedFrame == _frame - 1) {
      _previousFrameBytes -= entry.estimatedBytes;
    }
  }

  void _reject(
    List<RasterMaskImageReservation> reservations, {
    required RasterMaskRejection reason,
  }) {
    _lastRejection = reason;
    _rejections++;
    switch (reason) {
      case .perImage:
        _perImageRejections++;
      case .group:
        _groupRejections++;
      case .visibleSet:
        _visibleSetRejections++;
    }
    if (MonetPerfDebugSwitches.logCachedTextImageBudget) {
      final requested = reservations.fold<int>(
        0,
        (total, entry) => total + entry.estimatedBytes,
      );
      logDebug(
        '[$debugLabel] rejected=$requested reason=$reason '
        'current=$_estimatedBytes max=$_maxBytes '
        'maxImage=$_maxImageBytes images=${_entries.length}',
      );
    }
  }

  void _resetCounters() {
    _peakEstimatedBytes = 0;
    _evictions = 0;
    _rejections = 0;
    _perImageRejections = 0;
    _groupRejections = 0;
    _visibleSetRejections = 0;
    _lastRejection = null;
  }
}

class _RasterMaskImageEntry {
  _RasterMaskImageEntry({
    required this.estimatedBytes,
    required this.lastUsedFrame,
    required this.evict,
  });

  final int estimatedBytes;
  int lastUsedFrame;
  final VoidCallback evict;
}

class RasterMaskImageReservation {
  const RasterMaskImageReservation({
    required this.key,
    required this.estimatedBytes,
    required this.evict,
  });

  final Object key;
  final int estimatedBytes;
  final VoidCallback evict;
}

/// RGBA base level plus full mip chain; excludes driver padding/other caches.
int estimateRasterMaskImageBytes(int width, int height) =>
    (width * height * 16 + 2) ~/ 3;
