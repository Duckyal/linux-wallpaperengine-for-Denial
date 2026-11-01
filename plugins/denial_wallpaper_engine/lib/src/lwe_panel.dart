import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import 'lwe_controller.dart';
import 'lwe_driver.dart';
import 'lwe_updater.dart';
import 'workshop_discovery.dart';

export 'lwe_panel_bus.dart' show LwePanelBus, LwePanelEvent;

/// Bumped every time the panel opens so [lweUpdateCheckProvider] re-runs.
final lweUpdateNonceProvider = StateProvider<int>((ref) => 0);

/// The engine crash the panel currently shows, if any. Fed by the panel from
/// [LweDriver.failures] and [LweDriver.lastFailure]; watched by the failure
/// banner and the wallpaper grid (which flags the broken tile). Cleared on a
/// healthy start or when the user dismisses it.
final lweEngineFailureProvider = StateProvider<LweEngineFailure?>(
  (ref) => null,
);

/// Runs an update check against the host; recomputes whenever the nonce
/// changes (i.e. each time the panel is opened).
final lweUpdateCheckProvider = FutureProvider<LweUpdateResult>((ref) {
  ref.watch(lweUpdateNonceProvider);
  return ref.watch(lweUpdaterProvider).checkForUpdate();
});

/// Panel strings, Chinese when the system locale is Chinese, English
/// otherwise. Read from the platform dispatcher directly so it works
/// regardless of the shell's MaterialApp localization setup.
class _T {
  static bool get isZh => WidgetsBinding
      .instance
      .platformDispatcher
      .locale
      .languageCode
      .startsWith('zh');

  static const String title = 'linux-wallpaperengine for Denial';

  static String get close => isZh ? '关闭' : 'Close';
  static String get configFailed =>
      isZh ? '配置读取失败：' : 'Failed to read config: ';
  static String get workshopFailed =>
      isZh ? '读取 Workshop 壁纸失败：' : 'Failed to read Workshop wallpapers: ';
  static String get noWallpapers => isZh
      ? '未找到 Workshop 壁纸。\n请先在 Steam 的 Wallpaper Engine 创意工坊订阅并下载。'
      : 'No Workshop wallpapers found.\nSubscribe and download them in the '
            'Steam Wallpaper Engine Workshop first.';
  static String get installed => isZh ? '已安装壁纸' : 'Installed wallpapers';
  static String get gridHint => isZh
      ? '单击选择壁纸 · 循环图标加入轮换 · 应用参数后生效'
      : 'Click to select · loop icon adds to rotation · Apply to take effect';
  static String get enable => isZh ? '启用动态壁纸' : 'Enable live wallpaper';
  static String get stop =>
      isZh ? '停止渲染（保留选择）' : 'Stop rendering (keep selection)';
  static String get fpsCap => isZh ? '帧率上限' : 'Frame rate cap';
  static String get mute =>
      isZh ? '静音（停用音频分析）' : 'Mute (disable audio analysis)';
  static String get volume => isZh ? '音量' : 'Volume';
  static String get scaling => isZh ? '缩放模式' : 'Scaling mode';
  static String get pauseFullscreen => isZh ? '全屏时暂停' : 'Pause on fullscreen';
  static String get pauseFocused =>
      isZh ? '只在焦点全屏时暂停' : 'Pause only on focused fullscreen';
  static String get disableMouse =>
      isZh ? '禁用鼠标交互' : 'Disable mouse interaction';
  static String get disableParticles => isZh ? '禁用粒子' : 'Disable particles';
  static String get disableParallax => isZh ? '禁用视差' : 'Disable parallax';
  static String get audioOff => isZh ? '停用音频处理' : 'Disable audio processing';
  static String get autoDuck => isZh
      ? '别的应用放声时自动压低壁纸音量'
      : 'Auto-duck wallpaper volume when apps play audio';
  static String get draftHint => isZh
      ? '所有调整先保存在草稿里，点"应用参数"后一次性生效。'
      : 'Edits stay in a draft until you press "Apply".';
  static String get rotation => isZh ? '轮换间隔' : 'Rotation interval';
  static String get off => isZh ? '关闭' : 'Off';
  static String minutes(int n) => isZh ? '$n 分钟' : '$n min';
  static String get random => isZh ? '随机切换' : 'Random';
  static String get apply => isZh ? '应用参数' : 'Apply';
  static String get applyFailed => isZh ? '应用失败：' : 'Failed to apply: ';
  static String get appliedClosing =>
      isZh ? '配置已应用，正在返回桌面…' : 'Applied — returning to desktop…';

  // --- Update banner ---
  static String get checkingUpdate => isZh
      ? '正在检查 linux-wallpaperengine 更新…'
      : 'Checking for linux-wallpaperengine update…';
  static String get updateAvailable => isZh ? '有可用更新' : 'Update available';
  static String get upToDate => isZh ? '已是最新' : 'Up to date';
  static String get updateNow => isZh ? '更新' : 'Update';
  static String get installFailed => isZh ? '更新失败：' : 'Update failed: ';
  static String get updateReleases =>
      isZh ? '打开 GitHub 发布页' : 'Open GitHub releases';
  static String get notInstalled => isZh
      ? '未安装 linux-wallpaperengine，无法设置壁纸。'
      : 'linux-wallpaperengine is not installed, so wallpapers cannot render.';
  static String get checkUpdate => isZh ? '检查更新' : 'Check for updates';
  static String get copyCommand => isZh ? '复制更新命令' : 'Copy update command';
  static String get openedReleases =>
      isZh ? '已打开 GitHub 发布页' : 'Opened GitHub releases page';
  static String get copiedReleases => isZh
      ? '已复制发布页链接，请粘贴到浏览器打开'
      : 'Copied releases link — paste it in a browser';
  static String get noOpener =>
      isZh ? '无法打开浏览器，也无法复制链接' : 'Could not open a browser or copy the link';
  static String versionLabel(String current, String latest) =>
      isZh ? '当前 $current → 最新 $latest' : 'current $current → latest $latest';

  // --- Engine failure banner ---
  static String get engineCrashed =>
      isZh ? '壁纸启动失败，引擎已退出' : 'Wallpaper failed to start; the engine exited';
  static String get engineCrashedTile =>
      isZh ? '此壁纸导致引擎崩溃' : 'This wallpaper crashed the engine';
  static String get tryAnotherWallpaper =>
      isZh ? '换一个壁纸试试' : 'Try another wallpaper';
  static String get dismiss => isZh ? '知道了' : 'Dismiss';
}

/// Full-screen wallpaper manager overlay mounted on the aboveWindows layer.
///
/// Interaction model (draft-based): clicking a tile only SELECTS it and
/// every control edits a local draft; nothing is persisted or restarted
/// until the "Apply" button commits the whole draft at once. The enable
/// toggle and stop button remain immediate actions.
class LweWallpaperPanel extends ConsumerStatefulWidget {
  const LweWallpaperPanel({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  ConsumerState<LweWallpaperPanel> createState() => _LweWallpaperPanelState();
}

class _LweWallpaperPanelState extends ConsumerState<LweWallpaperPanel> {
  bool _busy = false;
  LweState? _draft;
  String? _toast;
  Timer? _toastTimer;

  LweState get draft => _draft!;

  LweState? _loadedState;
  StreamSubscription<LweEngineFailure?>? _failureSub;

  @override
  void initState() {
    super.initState();
    // The panel is mounted fresh on each open, so seed from the driver's
    // retained failure: a wallpaper that crashed during the startup restore
    // (panel closed) must still be visible when the user opens it.
    final retained = ref.read(lweDriverProvider).lastFailure;
    if (retained != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          ref.read(lweEngineFailureProvider.notifier).state = retained;
      });
    }
    _failureSub = ref.read(lweDriverProvider).failures.listen((failure) {
      if (!mounted) return;
      ref.read(lweEngineFailureProvider.notifier).state = failure;
    });
  }

  @override
  void dispose() {
    _failureSub?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _updateDraft(LweState Function(LweState) mutate) {
    setState(() => _draft = mutate(_draft ?? _loadedState!));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      // Immediate actions (enable/stop) change controller state behind the
      // draft's back; fold their `enabled` result back in so the toggle
      // reflects reality, while keeping uncommitted draft edits.
      final latest = ref.read(lweControllerProvider).value;
      if (latest != null && mounted) {
        setState(() => _draft = _draft?.copyWith(enabled: latest.enabled));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Commits the whole draft via [LweController.commitPanel]. On success the
  /// panel closes shortly after a toast, so the user immediately SEES the
  /// wallpaper change the panel was blocking. Failures stay with an error
  /// toast so the draft can be fixed.
  ///
  /// A wallpaper that crashes the engine does NOT close the panel: the driver
  /// only reports the crash a few seconds after spawning, and closing then
  /// would hide the failure banner and read as "the plugin is broken".
  /// Instead we wait for that start's verdict and stay open with the banner
  /// and the flagged tile so the user can pick another wallpaper.
  Future<void> _applyDraft() async {
    final d = draft;
    final driver = ref.read(lweDriverProvider);
    final verdictBefore = driver.lastStartVerdict;
    try {
      await _run(
        () => ref
            .read(lweControllerProvider.notifier)
            .commitPanel(
              wallpaperId: d.currentWallpaperId,
              playlist: d.playlist,
              settings: d.settings,
              rotationMinutes: d.rotationMinutes,
            ),
      );
      if (!mounted) return;
      // A new verdict future means commitPanel actually restarted the engine.
      final verdict = driver.lastStartVerdict;
      if (verdict != null && !identical(verdict, verdictBefore)) {
        // Engine crashes land within a few hundred ms of spawn; the healthy
        // verdict only arrives after the full crash window. Cap the wait so
        // a normal apply still closes promptly — a verdict that arrives after
        // the timeout still raises the banner via the failure stream.
        final failure = await verdict.timeout(
          const Duration(milliseconds: 2500),
          onTimeout: () => null,
        );
        if (!mounted) return;
        if (failure != null) {
          // Keep the draft: the user picks a different wallpaper and retries.
          _showToast(_T.engineCrashed);
          return;
        }
      }
      setState(() => _draft = null);
      _showToast(_T.appliedClosing);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) widget.onClose();
      });
    } on Object catch (error) {
      if (mounted) _showToast('${_T.applyFailed}$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lweControllerProvider);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF7C9EFF),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        child: Material(
          type: MaterialType.transparency,
          // Builder: _buildPanel must resolve Theme.of BELOW the dark Theme
          // above — the State's own context sits outside it and would pick
          // up the shell's (possibly light) scheme, rendering dark-on-dark.
          child: Builder(
            builder: (context) => state.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _PanelScaffold(
                onClose: widget.onClose,
                child: Center(child: Text('${_T.configFailed}$error')),
              ),
              data: (state) {
                _loadedState = state;
                // The draft never edits `enabled` itself (only immediate
                // actions and the panel-open sync change it), so re-fold it
                // from the controller on every emission — that's how a sync
                // landing after the draft was seeded still reaches the
                // toggle.
                _draft = _draft?.copyWith(enabled: state.enabled) ?? state;
                return _buildPanel(context, ref);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context, WidgetRef ref) {
    final state = draft;
    final settings = state.settings;
    final controller = ref.read(lweControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        _PanelScaffold(
          onClose: widget.onClose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _T.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _T.close,
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .4),
              ),
              _EngineFailureBanner(
                onDismiss: () {
                  ref.read(lweDriverProvider).clearFailure();
                  ref.read(lweEngineFailureProvider.notifier).state = null;
                },
              ),
              _UpdateBanner(
                onCheckAgain: () => ref
                    .read(lweUpdateNonceProvider.notifier)
                    .update((n) => n + 1),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: _WallpaperGrid(
                        playlist: state.playlist,
                        activeId: state.currentWallpaperId,
                        selectedId: draft.currentWallpaperId,
                        enabled: state.enabled && !_busy,
                        failedId: ref
                            .watch(lweEngineFailureProvider)
                            ?.wallpaperId,
                        onSelect: (id) => _updateDraft(
                          (d) => d.copyWith(currentWallpaperId: id),
                        ),
                        onTogglePlaylist: (id) => _updateDraft((d) {
                          final playlist = [...d.playlist];
                          if (!playlist.remove(id)) playlist.add(id);
                          return d.copyWith(playlist: playlist);
                        }),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      color: scheme.outlineVariant.withValues(alpha: .4),
                    ),
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SwitchRow(
                              label: _T.enable,
                              value: state.enabled,
                              onChanged: (v) =>
                                  _run(() => controller.setEnabled(v)),
                            ),
                            if (state.enabled &&
                                state.currentWallpaperId != null)
                              _OutlinedAction(
                                label: _T.stop,
                                icon: Icons.stop_rounded,
                                onTap: _busy
                                    ? null
                                    : () => _run(controller.stopWallpaper),
                              ),
                            const SizedBox(height: 16),
                            _SliderRow(
                              label: _T.fpsCap,
                              valueLabel: '${settings.fps} FPS',
                              value: settings.fps.toDouble(),
                              min: 5,
                              max: 120,
                              divisions: 23,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(fps: v.round()),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.mute,
                              value: settings.silent,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(silent: v),
                                ),
                              ),
                            ),
                            if (!settings.silent)
                              _SliderRow(
                                label: _T.volume,
                                valueLabel: '${settings.volume}',
                                value: settings.volume.toDouble(),
                                min: 0,
                                max: 128,
                                divisions: 32,
                                onChanged: (v) => _updateDraft(
                                  (d) => d.copyWith(
                                    settings: d.settings.copyWith(
                                      volume: v.round(),
                                    ),
                                  ),
                                ),
                              ),
                            _ChoiceRow(
                              label: _T.scaling,
                              value: settings.scaling,
                              options: const [
                                'default',
                                'fit',
                                'fill',
                                'stretch',
                              ],
                              onSelected: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(scaling: v),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.pauseFullscreen,
                              value: settings.fullscreenPause,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    fullscreenPause: v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.pauseFocused,
                              value: settings.fullscreenPauseOnlyActive,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    fullscreenPauseOnlyActive: v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.disableMouse,
                              value: settings.disableMouse,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    disableMouse: v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.disableParticles,
                              value: settings.disableParticles,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    disableParticles: v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.disableParallax,
                              value: settings.disableParallax,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    disableParallax: v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.audioOff,
                              value: !settings.audioProcessing,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(
                                    audioProcessing: !v,
                                  ),
                                ),
                              ),
                            ),
                            _SwitchRow(
                              label: _T.autoDuck,
                              value: settings.automute,
                              onChanged: (v) => _updateDraft(
                                (d) => d.copyWith(
                                  settings: d.settings.copyWith(automute: v),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _T.rotation,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 30,
                                    child: SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        overlayShape:
                                            SliderComponentShape.noOverlay,
                                      ),
                                      child: Slider(
                                        value: state.rotationMinutes
                                            .clamp(0, 120)
                                            .toDouble(),
                                        min: 0,
                                        max: 120,
                                        divisions: 24,
                                        onChanged: (value) => _updateDraft(
                                          (d) => d.copyWith(
                                            rotationMinutes: value.round(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Text(
                                    state.rotationMinutes <= 0
                                        ? _T.off
                                        : _T.minutes(state.rotationMinutes),
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            FilledButton.tonalIcon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      await _run(controller.applyRandom);
                                      // Random picks a new wallpaper immediately;
                                      // adopt it into the draft so a later "Apply"
                                      // doesn't revert to the stale pick.
                                      final latest = ref
                                          .read(lweControllerProvider)
                                          .value;
                                      if (latest != null && mounted) {
                                        setState(
                                          () => _draft = _draft?.copyWith(
                                            enabled: latest.enabled,
                                            currentWallpaperId:
                                                latest.currentWallpaperId,
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: Text(_T.random),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _busy ? null : _applyDraft,
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(_T.apply),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _T.draftHint,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_toast != null)
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _toast == null ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: _Toast(text: _toast!),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-bleed panel frame: fills the entire output edge-to-edge. The
/// background is ~90% opaque so a hint of the live wallpaper shows through.
class _PanelScaffold extends StatelessWidget {
  const _PanelScaffold({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: const Color(0xE614181D), child: child);
  }
}

/// Floating capsule toast at the top of the panel.
class _Toast extends StatelessWidget {
  const _Toast({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xF01A1E24),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16)],
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFFE8EAF0),
        ),
      ),
    );
  }
}

/// Red banner shown while the engine crashed on the current wallpaper. The
/// point is honesty: a wallpaper the engine cannot render must announce
/// itself instead of silently flipping the enable toggle back off, which
/// reads as "the plugin is broken".
class _EngineFailureBanner extends ConsumerWidget {
  const _EngineFailureBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = ref.watch(lweEngineFailureProvider);
    if (failure == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final wallpapers = ref.watch(lweWallpapersProvider).value ?? const [];
    String? title;
    for (final w in wallpapers) {
      if (w.id == failure.wallpaperId) {
        title = w.title;
        break;
      }
    }
    final label = StringBuffer(
      '${_T.engineCrashed}${title == null ? '' : '：$title'}',
    );
    if (failure.detail != null && failure.detail!.isNotEmpty) {
      label.write('\n${failure.detail}');
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: .35),
        border: Border(bottom: BorderSide(color: scheme.errorContainer)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_rounded, color: scheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label.toString(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _T.tryAnotherWallpaper,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          TextButton(onPressed: onDismiss, child: Text(_T.dismiss)),
        ],
      ),
    );
  }
}

/// Update banner shown at the top of the panel. Runs an update check whenever
/// the panel opens and renders one of several states: checking, an available
/// update (with a one-click "Update" when a package manager is known), up to
/// date, not installed, or an unknown state that offers the GitHub releases
/// page / a copyable command.
class _UpdateBanner extends ConsumerStatefulWidget {
  const _UpdateBanner({required this.onCheckAgain});

  final VoidCallback onCheckAgain;

  @override
  ConsumerState<_UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends ConsumerState<_UpdateBanner> {
  bool _installing = false;

  Future<void> _install() async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      final result = await ref.read(lweUpdaterProvider).installUpdate();
      if (!mounted) return;
      _showToast(
        result.success
            ? (result.message.isNotEmpty ? result.message : _T.updateNow)
            : '${_T.installFailed}${result.message}',
      );
      if (result.success) {
        widget.onCheckAgain();
      }
    } on Object catch (error) {
      if (mounted) _showToast('${_T.installFailed}$error');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  void _showToast(String text) {
    // Reuse the panel's toast by calling the nearest panel state.
    final panel = context.findAncestorStateOfType<_LweWallpaperPanelState>();
    panel?._showToast(text);
  }

  /// Opens the GitHub releases page. If no browser opener is available, copies
  /// the URL to the clipboard so the user can paste it, and reports what
  /// happened either way (the click must never feel dead).
  Future<void> _openReleases() async {
    final opened = await ref.read(lweUpdaterProvider).openReleasesPage();
    if (opened) {
      _showToast(_T.openedReleases);
      return;
    }
    final copied = await ref
        .read(lweUpdaterProvider)
        .copyToClipboard(LweUpdater.releasesUrl);
    _showToast(copied ? _T.copiedReleases : _T.noOpener);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final check = ref.watch(lweUpdateCheckProvider);

    // Only show the banner when there is something to act on (an update is
    // available, or the binary isn't installed). Otherwise stay silent so the
    // panel doesn't nag when everything is up to date or detection is unknown.
    return check.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (result) => _buildBanner(context, scheme, result),
    );
  }

  Widget _buildBanner(
    BuildContext context,
    ColorScheme scheme,
    LweUpdateResult result,
  ) {
    if (result is LweUpdateNotInstalled) {
      return _BannerShell(
        icon: Icon(Icons.warning_amber_rounded, color: scheme.error, size: 18),
        label: _T.notInstalled,
        trailing: TextButton.icon(
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(_T.updateReleases),
          onPressed: () => _openReleases(),
        ),
      );
    }

    if (result is LweUpdateAvailable) {
      final local = result.localVersion?.toString() ?? '?';
      final latest = result.latestVersion.toString();
      final action = _installing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : result.actionable
          ? FilledButton.icon(
              onPressed: _install,
              icon: const Icon(Icons.system_update_rounded, size: 16),
              label: Text(_T.updateNow),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity(horizontal: -2, vertical: -2),
              ),
            )
          : TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(_T.updateReleases),
              onPressed: () => _openReleases(),
            );
      return _BannerShell(
        icon: Icon(Icons.new_releases_rounded, color: scheme.primary, size: 18),
        label: '${_T.updateAvailable} · ${_T.versionLabel(local, latest)}',
        trailing: action,
      );
    }

    if (result is LweUpdateUpToDate) {
      // Everything is current — don't show anything.
      return const SizedBox.shrink();
    }

    // Unknown: we found the binary but couldn't resolve "latest" (offline,
    // unknown package manager, or a git build). Don't nag; only surface
    // something actionable when there's actually a detected update.
    if (result is LweUpdateUnknown) {
      return const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }
}

/// Compact banner row: icon + label on the left, action on the right.
class _BannerShell extends StatelessWidget {
  const _BannerShell({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final Widget icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .5),
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .4),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 18, height: 18, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Tiny spinner used while the update check runs.
class _TraySpinner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 14,
    height: 14,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _WallpaperGrid extends ConsumerWidget {
  const _WallpaperGrid({
    required this.playlist,
    required this.activeId,
    required this.selectedId,
    required this.enabled,
    required this.onSelect,
    required this.onTogglePlaylist,
    this.failedId,
  });

  final List<String> playlist;
  final String? activeId;
  final String? selectedId;
  final bool enabled;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onTogglePlaylist;

  /// The wallpaper the engine crashed on, when a failure is on screen. Its
  /// tile gets a red badge so the blame lands on the wallpaper, not the
  /// panel.
  final String? failedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpapers = ref.watch(lweWallpapersProvider);
    final scheme = Theme.of(context).colorScheme;
    return wallpapers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('${_T.workshopFailed}$error'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                _T.noWallpapers,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    '${_T.installed}（${items.length}）',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _T.gridHint,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 210,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 16 / 10,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _Tile(
                    item: item,
                    selected: item.id == selectedId,
                    running: item.id == activeId,
                    inPlaylist: playlist.contains(item.id),
                    enabled: enabled,
                    failed: item.id == failedId,
                    onSelect: () => onSelect(item.id),
                    onTogglePlaylist: () => onTogglePlaylist(item.id),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.selected,
    required this.running,
    required this.inPlaylist,
    required this.enabled,
    required this.onSelect,
    required this.onTogglePlaylist,
    this.failed = false,
  });

  final WorkshopWallpaper item;
  final bool selected;
  final bool running;
  final bool inPlaylist;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onTogglePlaylist;

  /// True when the engine crashed on this exact wallpaper.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: InkWell(
        borderRadius: radius,
        onTap: enabled ? onSelect : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: failed
                  ? scheme.error
                  : selected
                  ? scheme.primary
                  : running
                  ? scheme.primary.withValues(alpha: .55)
                  : scheme.outlineVariant,
              width: (failed || selected) ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (item.preview != null)
                  Image.file(
                    File(item.preview!),
                    fit: BoxFit.cover,
                    cacheWidth: 420,
                    cacheHeight: 262,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                  )
                else
                  ColoredBox(color: scheme.surfaceContainerHighest),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _PlaylistToggle(
                    active: inPlaylist,
                    enabled: enabled,
                    onTap: onTogglePlaylist,
                  ),
                ),
                if (failed)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Tooltip(
                      message: _T.engineCrashedTile,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.bug_report_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: .78),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          if (running)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: scheme.primary,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular loop toggle in the tile corner; edits the draft playlist
/// only. Tapping it must not also select the tile.
class _PlaylistToggle extends StatelessWidget {
  const _PlaylistToggle({
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.primary : Colors.black.withValues(alpha: .45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.loop_rounded,
            size: 14,
            color: active
                ? scheme.onPrimary
                : Colors.white.withValues(alpha: .85),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          SizedBox(
            height: 32,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12.5)),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 30,
            child: SliderTheme(
              data: SliderTheme.of(context)
                  .copyWith(overlayShape: SliderComponentShape.noOverlay),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -4, vertical: -3),
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
              ),
              segments: [
                for (final option in options)
                  ButtonSegment(value: option, label: Text(option)),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onSelected(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  const _OutlinedAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
