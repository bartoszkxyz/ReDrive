import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../services/headunit/native_app_launcher_service.dart';

/// Configuration for an application slot in the Cockpit Launcher Bay.
class PipSlotConfig {
  final String id;
  final String label;
  final IconData icon;
  final String packageName;
  final String? activityName;
  final bool isConfigurable;

  const PipSlotConfig({
    required this.id,
    required this.label,
    required this.icon,
    required this.packageName,
    this.activityName,
    this.isConfigurable = false,
  });

  PipSlotConfig copyWith({
    String? label,
    IconData? icon,
    String? packageName,
    String? activityName,
  }) {
    return PipSlotConfig(
      id: id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      packageName: packageName ?? this.packageName,
      activityName: activityName ?? this.activityName,
      isConfigurable: isConfigurable,
    );
  }
}

/// TS18 Radio & Audio Controls Bay for the Cockpit Launcher.
///
/// Provides:
/// 1. Digital FM / AM radio tuner frequency display and seek/step controls.
/// 2. Tactile 6-station preset memory bank (P1 - P6).
/// 3. Direct native Android master volume control (Mute, Vol -, Vol +).
/// 4. Media skip & playback controls (Previous, Play/Pause, Next).
/// 5. One-tap launch button to open TS18 FM/AM Radio (com.tw.radio) full-screen.
class PipApplicationBay extends StatefulWidget {
  final NativeAppLauncherService launcherService;
  final void Function(PipSlotConfig slot)? onSlotChanged;
  final bool autoSetPipWindow;

  PipApplicationBay({
    super.key,
    NativeAppLauncherService? launcherService,
    this.onSlotChanged,
    this.autoSetPipWindow = false,
  }) : launcherService = launcherService ?? NativeAppLauncherService();

  @override
  State<PipApplicationBay> createState() => _PipApplicationBayState();
}

class _PipApplicationBayState extends State<PipApplicationBay> {
  static const PipSlotConfig _radioSlot = PipSlotConfig(
    id: 'radio',
    label: 'Radio',
    icon: Icons.radio_rounded,
    packageName: NativeAppLauncherService.pkgRadio,
    activityName: NativeAppLauncherService.actRadio,
    isConfigurable: false,
  );

  bool _isAm = false;
  double _fmFrequency = 98.50;
  int _amFrequency = 648;
  int _selectedPresetIndex = 2; // Default to P3

  final List<double> _fmPresets = [89.1, 95.8, 98.5, 101.2, 104.5, 107.0];
  final List<int> _amPresets = [540, 648, 720, 810, 990, 1080];

  int _volume = 15;
  int _maxVolume = 30;
  bool _isMuted = false;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    if (widget.autoSetPipWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyActivePipWindow();
      });
    }

    _loadAudioState();
  }

  void _loadAudioState() {
    widget.launcherService.getAudioState().then((state) {
      if (state != null && mounted) {
        setState(() {
          _volume = state['volume'] as int? ?? _volume;
          _maxVolume = state['maxVolume'] as int? ?? _maxVolume;
          _isMuted = state['isMuted'] as bool? ?? _isMuted;
        });
      }
    });
  }

  void _applyActivePipWindow() {
    widget.launcherService.setPipWindow(
      packageName: _radioSlot.packageName,
      activityName: _radioSlot.activityName,
      x: 742,
      y: 68,
      width: 510,
      height: 564,
    );
    widget.onSlotChanged?.call(_radioSlot);
  }

  void _maximizeActiveApp() {
    HapticFeedback.mediumImpact();
    widget.launcherService.launchRadio();
  }

  void _setBand(bool isAm) {
    if (_isAm == isAm) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isAm = isAm;
      _selectedPresetIndex = -1;
    });
  }

  void _stepFrequency(double delta) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_isAm) {
        final next = (_amFrequency + (delta * 90).round()).clamp(531, 1602);
        _amFrequency = next;
      } else {
        final next = (_fmFrequency + delta).clamp(87.5, 108.0);
        _fmFrequency = double.parse(next.toStringAsFixed(2));
      }
      _selectedPresetIndex = -1;
    });
  }

  void _seekFrequency(bool up) {
    HapticFeedback.mediumImpact();
    setState(() {
      if (_isAm) {
        final step = up ? 45 : -45;
        _amFrequency = (_amFrequency + step).clamp(531, 1602);
      } else {
        final step = up ? 0.5 : -0.5;
        final next = (_fmFrequency + step).clamp(87.5, 108.0);
        _fmFrequency = double.parse(next.toStringAsFixed(2));
      }
      _selectedPresetIndex = -1;
    });
  }

  void _selectPreset(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPresetIndex = index;
      if (_isAm) {
        _amFrequency = _amPresets[index];
      } else {
        _fmFrequency = _fmPresets[index];
      }
    });
  }

  void _changeVolume(int delta) async {
    HapticFeedback.selectionClick();
    final next = (_volume + delta).clamp(0, _maxVolume);
    setState(() {
      _volume = next;
      _isMuted = next == 0;
    });
    final res = await widget.launcherService.adjustVolume(delta > 0 ? 1 : -1);
    if (res != null && mounted) {
      setState(() {
        _volume = res['volume'] as int? ?? _volume;
        _maxVolume = res['maxVolume'] as int? ?? _maxVolume;
      });
    }
  }

  void _toggleMute() async {
    HapticFeedback.lightImpact();
    final newMute = !_isMuted;
    setState(() => _isMuted = newMute);
    await widget.launcherService.setVolume(newMute ? 0 : 15);
  }

  void _sendMediaKey(int keyCode) {
    HapticFeedback.selectionClick();
    if (keyCode == NativeAppLauncherService.keyCodeMediaPlayPause) {
      setState(() => _isPlaying = !_isPlaying);
    }
    widget.launcherService.sendMediaKey(keyCode);
  }

  @override
  Widget build(BuildContext context) {
    final themeEngine = context.watch<ThemeEngine?>();
    final colors = themeEngine?.colors ?? const CustomThemeColors();

    final currentFreqStr = _isAm
        ? '$_amFrequency'
        : _fmFrequency.toStringAsFixed(2);
    final currentUnitStr = _isAm ? 'kHz' : 'MHz';

    return Container(
      key: const Key('pip_application_bay'),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: colors.textMuted.withValues(alpha: 0.15),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Top Header Bar: Radio Title, FM/AM Band Selector & Fullscreen Maximize
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.radio_rounded, size: 16, color: colors.primaryAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'RADIO TUNER',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: colors.textMain,
                  ),
                ),
              ),

              // FM / AM Band Switcher
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.textMuted.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _BandButton(
                      key: const Key('pip_tab_radio'),
                      label: 'FM',
                      isActive: !_isAm,
                      colors: colors,
                      onTap: () => _setBand(false),
                    ),
                    _BandButton(
                      key: const Key('radio_band_am'),
                      label: 'AM',
                      isActive: _isAm,
                      colors: colors,
                      onTap: () => _setBand(true),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Corner Maximize Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('pip_maximize_button'),
                  onTap: _maximizeActiveApp,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.surfaceCard.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colors.primaryAccent.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen_rounded, size: 15, color: colors.primaryAccent),
                        const SizedBox(width: 3),
                        Text(
                          'FULL',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: colors.textMain,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 2. Radio Interactive Surface
          Expanded(
            child: Container(
              key: const Key('pip_live_surface'),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: colors.background.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(
                  color: colors.primaryAccent.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Frequency & Status Hero Readout
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                currentFreqStr,
                                style: TextStyle(
                                  fontFamily: 'RobotoMono',
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  color: colors.primaryAccent,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                currentUnitStr,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF00E676),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'STEREO • TS18 LIVE AUDIO',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: colors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // Signal Indicator
                      Row(
                        children: List.generate(4, (i) {
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 3.5,
                            height: 8.0 + (i * 3.5),
                            decoration: BoxDecoration(
                              color: colors.primaryAccent.withValues(alpha: (i + 1) * 0.25),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),

                  // Tuning & Seeking Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.surfaceCard.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.textMuted.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _TuneActionButton(
                          key: const Key('radio_seek_down'),
                          icon: Icons.fast_rewind_rounded,
                          label: 'SEEK -',
                          colors: colors,
                          onTap: () => _seekFrequency(false),
                        ),
                        _TuneActionButton(
                          key: const Key('radio_step_down'),
                          icon: Icons.chevron_left_rounded,
                          label: '-0.1',
                          colors: colors,
                          onTap: () => _stepFrequency(-0.1),
                        ),
                        _TuneActionButton(
                          key: const Key('radio_step_up'),
                          icon: Icons.chevron_right_rounded,
                          label: '+0.1',
                          colors: colors,
                          onTap: () => _stepFrequency(0.1),
                        ),
                        _TuneActionButton(
                          key: const Key('radio_seek_up'),
                          icon: Icons.fast_forward_rounded,
                          label: 'SEEK +',
                          colors: colors,
                          onTap: () => _seekFrequency(true),
                        ),
                      ],
                    ),
                  ),

                  // 6-Station Presets Bank (P1 to P6)
                  Row(
                    children: [
                      for (int i = 0; i < 6; i++) ...[
                        Expanded(
                          child: _PresetButton(
                            key: Key('radio_preset_${i + 1}'),
                            label: 'P${i + 1}',
                            freq: _isAm
                                ? '${_amPresets[i]}'
                                : _fmPresets[i].toStringAsFixed(1),
                            isSelected: i == _selectedPresetIndex,
                            colors: colors,
                            onTap: () => _selectPreset(i),
                          ),
                        ),
                        if (i < 5) const SizedBox(width: 4),
                      ],
                    ],
                  ),

                  // Volume Controller Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.surfaceCard.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.textMuted.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          key: const Key('pip_volume_mute_button'),
                          icon: Icon(
                            _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: _isMuted ? Colors.redAccent : colors.primaryAccent,
                            size: 18,
                          ),
                          onPressed: _toggleMute,
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          key: const Key('pip_volume_down_button'),
                          icon: Icon(Icons.remove_circle_outline_rounded, color: colors.textMain, size: 18),
                          onPressed: () => _changeVolume(-1),
                          visualDensity: VisualDensity.compact,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'MASTER VOLUME',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textMuted,
                                      ),
                                    ),
                                    Text(
                                      '$_volume / $_maxVolume',
                                      style: TextStyle(
                                        fontFamily: 'RobotoMono',
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: colors.primaryAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: _maxVolume > 0 ? (_volume / _maxVolume) : 0,
                                    backgroundColor: colors.background,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _isMuted ? Colors.redAccent : colors.primaryAccent,
                                    ),
                                    minHeight: 5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          key: const Key('pip_volume_up_button'),
                          icon: Icon(Icons.add_circle_outline_rounded, color: colors.textMain, size: 18),
                          onPressed: () => _changeVolume(1),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),

                  // Media Skip Controls & Full Radio App Launch Button
                  Row(
                    children: [
                      _MediaIconButton(
                        key: const Key('pip_media_prev_button'),
                        icon: Icons.skip_previous_rounded,
                        colors: colors,
                        onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaPrevious),
                      ),
                      const SizedBox(width: 6),
                      _MediaIconButton(
                        key: const Key('pip_media_play_button'),
                        icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        colors: colors,
                        onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaPlayPause),
                      ),
                      const SizedBox(width: 6),
                      _MediaIconButton(
                        key: const Key('pip_media_next_button'),
                        icon: Icons.skip_next_rounded,
                        colors: colors,
                        onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaNext),
                      ),
                      const SizedBox(width: 8),

                      // Open Full App Button
                      Expanded(
                        child: SizedBox(
                          height: 36,
                          child: ElevatedButton.icon(
                            key: const Key('pip_action_launch_radio'),
                            onPressed: _maximizeActiveApp,
                            icon: const Icon(Icons.radio_rounded, size: 15),
                            label: const Text(
                              'OPEN RADIO APP',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primaryAccent.withValues(alpha: 0.18),
                              foregroundColor: colors.primaryAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.5)),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final CustomThemeColors colors;
  final VoidCallback onTap;

  const _BandButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primaryAccent.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
              color: isActive ? colors.primaryAccent : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _TuneActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final CustomThemeColors colors;
  final VoidCallback onTap;

  const _TuneActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: colors.primaryAccent),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: colors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String label;
  final String freq;
  final bool isSelected;
  final CustomThemeColors colors;
  final VoidCallback onTap;

  const _PresetButton({
    super.key,
    required this.label,
    required this.freq,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primaryAccent.withValues(alpha: 0.22)
                : colors.surfaceCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected
                  ? colors.primaryAccent
                  : colors.textMuted.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colors.primaryAccent : colors.textMuted,
                ),
              ),
              Text(
                freq,
                style: TextStyle(
                  fontFamily: 'RobotoMono',
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? colors.primaryAccent : colors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaIconButton extends StatelessWidget {
  final IconData icon;
  final CustomThemeColors colors;
  final VoidCallback onTap;

  const _MediaIconButton({
    super.key,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 18, color: colors.primaryAccent),
        ),
      ),
    );
  }
}
