import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lwe_debug.dart';

/// Process driver for linux-wallpaperengine.
///
/// Handles process lifecycle and argv building. The wallpaper renders via
/// wlr-layer-shell; this class only manages the external process.
class LweDriver {
  LweDriver({required this.configPath});

  final String configPath;
  Process? _process;
  int? _lastPid;
  int _pendingStarts = 0;
  Future<void> _applyQueue = Future<void>.value();
  String? _cachedWaylandDisplay;

  /// How long a freshly started engine must survive before we consider it
  /// healthy. Exits before this window with a non-zero code are crashes
  /// (e.g. scene wallpapers the engine cannot parse abort with SIGABRT).
  static const crashWindow = Duration(seconds: 5);

  final StreamController<LweEngineFailure?> _failures =
      StreamController<LweEngineFailure?>.broadcast();

  /// Crash/recovery events for the engine started by [apply]. Emits a
  /// [LweEngineFailure] when a fresh process dies inside [crashWindow], and
  /// `null` when a process survives it (the panel clears its error banner on
  /// that). A broadcast stream: late subscribers (panel open) see only events
  /// after they subscribe, which is fine — the banner is transient UX.
  Stream<LweEngineFailure?> get failures => _failures.stream;

  /// The most recent crash, kept so a failure that happened while the panel
  /// was closed (e.g. a startup restore) still greets the user when they open
  /// it. Cleared by a healthy start or [clearFailure].
  LweEngineFailure? get lastFailure => _lastFailure;
  LweEngineFailure? _lastFailure;

  /// Drops [lastFailure] after the user acknowledged it.
  void clearFailure() => _lastFailure = null;

  /// Verdict of the most recent [apply]: completes with a [LweEngineFailure]
  /// when the engine crashed on that wallpaper, or `null` when it survived
  /// [crashWindow] or was stopped/replaced intentionally. Created at spawn
  /// time and handed to the exit watcher, so a caller that awaits it right
  /// after `apply` returns cannot miss the event (unlike the [failures]
  /// stream). The panel uses it to decide whether to close after Apply: a
  /// wallpaper that crashes the engine must keep the panel open so the
  /// failure stays visible.
  Future<LweEngineFailure?>? get lastStartVerdict => _verdict?.future;

  Completer<LweEngineFailure?>? _verdict;

  static void _settle(
    Completer<LweEngineFailure?>? verdict,
    LweEngineFailure? failure,
  ) {
    if (verdict != null && !verdict.isCompleted) verdict.complete(failure);
  }

  /// True while a scheduled startup apply has not fired yet. The panel-open
  /// sync defers to it: the engine being absent during the first-frame
  /// window is intentional and must not read as "stopped".
  bool get hasScheduledStart => _pendingStarts > 0;

  /// The compositor's Wayland socket name. deniald itself is the compositor
  /// server, so its environment carries no WAYLAND_DISPLAY; children spawned
  /// from the shell need it pointed at the session socket to connect.
  ///
  /// The result is cached after the first call because the Wayland socket
  /// does not change during a session.
  String? _waylandDisplay() {
    if (_cachedWaylandDisplay != null) return _cachedWaylandDisplay;
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime == null) return null;
    final dir = Directory(runtime);
    final sockets =
        dir
            .listSync()
            .whereType<File>()
            .map((entry) => entry.uri.pathSegments.last)
            .where(
              (name) => name.startsWith('wayland-') && !name.endsWith('.lock'),
            )
            .toList()
          ..sort();
    _cachedWaylandDisplay = sockets.isEmpty ? null : sockets.last;
    return _cachedWaylandDisplay;
  }

  /// Starts the wallpaper process with the given wallpaper ID and settings.
  ///
  /// Applies are serialized so a second call while one is starting still
  /// reaps the process it replaces instead of racing it.
  Future<void> apply(String id, LweSettings settings) {
    final task = _applyQueue.then((_) => _apply(id, settings));
    _applyQueue = task.catchError((Object _) {});
    return task;
  }

  Future<void> _apply(String id, LweSettings settings) async {
    await stop();
    final args = _buildArgs(id, settings);
    lweLog('apply: linux-wallpaperengine $args');
    try {
      final environment = {
        ...Platform.environment,
        if (_waylandDisplay() != null) 'WAYLAND_DISPLAY': _waylandDisplay()!,
      };
      _process = await Process.start(
        'linux-wallpaperengine',
        args,
        environment: environment,
      );
      _lastPid = _process!.pid;
      lweLog('apply: started pid=${_process!.pid}');
    } on Object catch (error) {
      lweLog('apply: start failed: $error');
      rethrow;
    }
    final process = _process!;
    // Fresh verdict for this start; the watcher settles it.
    final verdict = Completer<LweEngineFailure?>();
    _verdict = verdict;
    process.stdout.drain<void>();
    // Keep the last few stderr lines: when the engine aborts, its own error
    // text (e.g. a json type_error from a broken scene) is the most useful
    // thing to show the user.
    final stderrTail = <String>[];
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          lweLog('engine stderr: $line');
          stderrTail.add(line);
          if (stderrTail.length > 5) stderrTail.removeAt(0);
        });
    unawaited(_watchExit(process, id, stderrTail, verdict));
  }

  /// Watches [process] for a crash and reports it on [failures]. Exits inside
  /// [crashWindow] surface as "this wallpaper failed to start"; a process that
  /// survives the window announces itself healthy first, and a LATER non-zero
  /// exit still surfaces (the engine died on its own, e.g. an abort minutes
  /// into rendering). Intentional stops replace or null out [_process] first,
  /// so their SIGKILL exits never read as a crash.
  Future<void> _watchExit(
    Process process,
    String wallpaperId,
    List<String> stderrTail,
    Completer<LweEngineFailure?> verdict,
  ) async {
    const pending = -0x7FFFF;
    final early = await process.exitCode.timeout(
      crashWindow,
      onTimeout: () => pending,
    );
    if (early == pending) {
      // Survived the window: healthy start. Tell subscribers so a stale
      // failure banner from a previous attempt can clear itself.
      lweLog('engine pid=${process.pid} healthy past crash window');
      _lastFailure = null;
      _failures.add(null);
      _settle(verdict, null);
      final late = await process.exitCode;
      lweLog('engine pid=${process.pid} exited code=$late');
      if (late == 0 || !identical(process, _process)) return;
      _reportCrash(process, wallpaperId, late, stderrTail);
      return;
    }
    lweLog('engine pid=${process.pid} exited code=$early');
    if (early == 0 || !identical(process, _process)) {
      // Clean exit or an intentional stop/replacement: this start is over.
      _settle(verdict, null);
      return;
    }
    _reportCrash(process, wallpaperId, early, stderrTail);
    _settle(verdict, _lastFailure);
  }

  void _reportCrash(
    Process process,
    String wallpaperId,
    int exitCode,
    List<String> stderrTail,
  ) {
    _process = null;
    final failure = LweEngineFailure(
      wallpaperId: wallpaperId,
      exitCode: exitCode,
      detail: stderrTail.isEmpty
          ? null
          : stderrTail[stderrTail.length - 1].trim(),
    );
    _lastFailure = failure;
    _failures.add(failure);
  }

  /// Whether a wallpaper engine process is actually rendering right now.
  ///
  /// Checks our tracked child first, then any engine instance pgrep can see
  /// — the latter covers processes from an earlier shell instance or started
  /// externally, which the in-memory fields miss. This is the ground truth
  /// the panel sync reconciles the persisted `enabled` flag against.
  Future<bool> isRendering() async {
    final process = _process;
    if (process != null) {
      // Zero-timeout probe: the future only completes once the process has
      // exited, so the timeout sentinel means "still running".
      const running = -0x100000;
      final exit = await process.exitCode.timeout(
        Duration.zero,
        onTimeout: () => running,
      );
      if (exit == running) return true;
    }
    try {
      final result = await Process.run('pgrep', [
        '-f',
        'linux-wallpaperengine',
      ]);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  /// Schedules the startup apply after [delay] — the compositor's
  /// first-frame window must pass before a second GPU client may spawn —
  /// reaping leftover instances just before the spawn. [shouldRun] is
  /// re-checked at fire time so a disable landing inside the delay window
  /// still prevents the start.
  Future<void> scheduleApply(
    Duration delay,
    String id,
    LweSettings settings, {
    Future<bool> Function()? shouldRun,
  }) {
    final done = Completer<void>();
    _pendingStarts++;
    Timer(delay, () async {
      try {
        if (shouldRun != null && !await shouldRun()) {
          lweLog('scheduled apply skipped: disabled since schedule');
          if (!done.isCompleted) done.complete();
          return;
        }
        await reapStaleInstances();
        await apply(id, settings);
        if (!done.isCompleted) done.complete();
      } on Object catch (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      } finally {
        _pendingStarts--;
      }
    });
    return done.future;
  }

  /// Stops the current wallpaper process.
  ///
  /// linux-wallpaperengine ignores SIGTERM, so escalate to SIGKILL. A stale
  /// pid from a previous session is also reaped here via reapStaleInstances.
  Future<void> stop() async {
    final process = _process;
    _process = null;
    final lastPid = _lastPid;
    _lastPid = null;
    if (process == null && lastPid == null) return;
    if (process != null) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () => 0,
      );
    } else if (lastPid != null) {
      Process.run('kill', ['-9', '$lastPid'], runInShell: false);
    }
  }

  /// Releases the failure stream. Called from the provider's dispose.
  void dispose() {
    _failures.close();
  }

  /// Kills any stale linux-wallpaperengine instances from previous sessions.
  Future<void> reapStaleInstances() async {
    final result = await Process.run('pgrep', ['-f', 'linux-wallpaperengine']);
    if (result.exitCode != 0) return;
    final pids = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && int.tryParse(line) != null);
    for (final pid in pids) {
      await Process.run('kill', ['-9', pid]);
    }
  }

  List<String> _buildArgs(String id, LweSettings settings) {
    final args = <String>[
      // An output selector is mandatory: without one the engine renders into
      // a plain window instead of the wlr-layer-shell background layer.
      if (settings.screenRoot.isNotEmpty) ...[
        '--screen-root',
        settings.screenRoot,
      ],
      '--bg',
      id,
      '--fps',
      settings.fps.toString(),
    ];

    if (settings.silent) {
      args.add('--silent');
    } else {
      args.addAll(['--volume', settings.volume.toString()]);
    }

    if (settings.fullscreenPause) {
      if (settings.fullscreenPauseOnlyActive) {
        args.add('--fullscreen-pause-only-active');
      }
    } else {
      args.add('--no-fullscreen-pause');
    }

    if (settings.disableMouse) args.add('--disable-mouse');
    if (settings.disableParticles) args.add('--disable-particles');
    if (settings.disableParallax) args.add('--disable-parallax');
    if (!settings.audioProcessing) args.add('--no-audio-processing');
    if (!settings.automute) args.add('--noautomute');
    if (settings.layer != 'bottom') args.addAll(['--layer', settings.layer]);
    if (settings.scaling != 'default') {
      args.addAll(['--scaling', settings.scaling]);
    }

    return args;
  }
}

/// Settings for the wallpaper process.
class LweSettings {
  const LweSettings({
    this.silent = true,
    this.volume = 0,
    this.fps = 30,
    this.fullscreenPause = true,
    this.fullscreenPauseOnlyActive = false,
    this.disableMouse = false,
    this.disableParticles = false,
    this.disableParallax = false,
    this.audioProcessing = true,
    this.automute = true,
    this.layer = 'bottom',
    this.scaling = 'default',
    this.screenRoot = '',
  });

  final bool silent;
  final int volume;
  final int fps;
  final bool fullscreenPause;
  final bool fullscreenPauseOnlyActive;
  final bool disableMouse;
  final bool disableParticles;
  final bool disableParallax;
  final bool audioProcessing;
  final bool automute;
  final String layer;
  final String scaling;
  final String screenRoot;

  LweSettings copyWith({
    bool? silent,
    int? volume,
    int? fps,
    bool? fullscreenPause,
    bool? fullscreenPauseOnlyActive,
    bool? disableMouse,
    bool? disableParticles,
    bool? disableParallax,
    bool? audioProcessing,
    bool? automute,
    String? layer,
    String? scaling,
    String? screenRoot,
  }) {
    return LweSettings(
      silent: silent ?? this.silent,
      volume: volume ?? this.volume,
      fps: fps ?? this.fps,
      fullscreenPause: fullscreenPause ?? this.fullscreenPause,
      fullscreenPauseOnlyActive:
          fullscreenPauseOnlyActive ?? this.fullscreenPauseOnlyActive,
      disableMouse: disableMouse ?? this.disableMouse,
      disableParticles: disableParticles ?? this.disableParticles,
      disableParallax: disableParallax ?? this.disableParallax,
      audioProcessing: audioProcessing ?? this.audioProcessing,
      automute: automute ?? this.automute,
      layer: layer ?? this.layer,
      scaling: scaling ?? this.scaling,
      screenRoot: screenRoot ?? this.screenRoot,
    );
  }

  Map<String, dynamic> toJson() => {
    'silent': silent,
    'volume': volume,
    'fps': fps,
    'fullscreenPause': fullscreenPause,
    'fullscreenPauseOnlyActive': fullscreenPauseOnlyActive,
    'disableMouse': disableMouse,
    'disableParticles': disableParticles,
    'disableParallax': disableParallax,
    'audioProcessing': audioProcessing,
    'automute': automute,
    'layer': layer,
    'scaling': scaling,
    'screenRoot': screenRoot,
  };

  factory LweSettings.fromJson(Map<String, dynamic> json) => LweSettings(
    silent: json['silent'] as bool? ?? true,
    volume: json['volume'] as int? ?? 0,
    fps: json['fps'] as int? ?? 30,
    fullscreenPause: json['fullscreenPause'] as bool? ?? true,
    fullscreenPauseOnlyActive:
        json['fullscreenPauseOnlyActive'] as bool? ?? false,
    disableMouse: json['disableMouse'] as bool? ?? false,
    disableParticles: json['disableParticles'] as bool? ?? false,
    disableParallax: json['disableParallax'] as bool? ?? false,
    audioProcessing: json['audioProcessing'] as bool? ?? true,
    automute: json['automute'] as bool? ?? true,
    layer: json['layer'] as String? ?? 'bottom',
    scaling: json['scaling'] as String? ?? 'default',
    screenRoot: json['screenRoot'] as String? ?? '',
  );
}

/// Why an engine process died during its crash window. Surfaced to the panel
/// so a wallpaper the engine cannot render shows up as a visible failure
/// instead of silently flipping the toggle back off.
class LweEngineFailure {
  const LweEngineFailure({
    required this.wallpaperId,
    required this.exitCode,
    this.detail,
  });

  final String wallpaperId;
  final int exitCode;

  /// Last stderr line the engine printed before dying, when available.
  final String? detail;
}

/// Provider for the LweDriver.
final lweDriverProvider = Provider<LweDriver>((ref) {
  final home = Platform.environment['HOME'] ?? '/';
  final driver = LweDriver(
    configPath: '$home/.config/denial-wallpaper-engine/config.json',
  );
  ref.onDispose(driver.dispose);
  return driver;
});
