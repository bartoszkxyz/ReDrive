import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../services/headunit/native_app_launcher_service.dart';

/// Configuration for an application slot in the PIP Bay.
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

/// Native Topway TS18 Picture-in-Picture (PIP) Application Bay.
///
/// Drives Topway's hardware display overlay (sys.tw.forcepip) to constrain
/// live applications (Radio, DVR, TLINK5) into Section 3 of the Cockpit Launcher.
class PipApplicationBay extends StatefulWidget {
  final NativeAppLauncherService launcherService;
  final void Function(PipSlotConfig slot)? onSlotChanged;
  final bool autoSetPipWindow;

  PipApplicationBay({
    super.key,
    NativeAppLauncherService? launcherService,
    this.onSlotChanged,
    this.autoSetPipWindow = true,
  }) : launcherService = launcherService ?? NativeAppLauncherService();

  @override
  State<PipApplicationBay> createState() => _PipApplicationBayState();
}

class _PipApplicationBayState extends State<PipApplicationBay> {
  int _activeSlotIndex = 0;
  int _volume = 15;
  int _maxVolume = 30;
  bool _isMuted = false;
  bool _isDvrRecording = false;

  late final List<PipSlotConfig> _slots = [
    // Slot 1: Stock TS18 Radio (Hardcoded Primary)
    const PipSlotConfig(
      id: 'radio',
      label: 'Radio',
      icon: Icons.radio_rounded,
      packageName: NativeAppLauncherService.pkgRadio,
      activityName: NativeAppLauncherService.actRadio,
      isConfigurable: false,
    ),
    // Slot 2: HD DVR Dashcam (Configurable)
    const PipSlotConfig(
      id: 'dvr',
      label: 'DVR',
      icon: Icons.videocam_rounded,
      packageName: NativeAppLauncherService.pkgDvr,
      activityName: NativeAppLauncherService.actDvr,
      isConfigurable: true,
    ),
    // Slot 3: TLINK5 CarPlay & Auto (Configurable)
    const PipSlotConfig(
      id: 'tlink',
      label: 'TLINK5',
      icon: Icons.phone_android_rounded,
      packageName: NativeAppLauncherService.pkgTlink5,
      activityName: NativeAppLauncherService.actTlink5,
      isConfigurable: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.autoSetPipWindow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyActivePipWindow();
      });
    }

    _loadAudioAndDvrState();
  }

  void _loadAudioAndDvrState() {
    widget.launcherService.getAudioState().then((state) {
      if (state != null && mounted) {
        setState(() {
          _volume = state['volume'] as int? ?? _volume;
          _maxVolume = state['maxVolume'] as int? ?? _maxVolume;
          _isMuted = state['isMuted'] as bool? ?? _isMuted;
        });
      }
    });

    widget.launcherService.isDvrRecording().then((rec) {
      if (mounted) {
        setState(() => _isDvrRecording = rec);
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
    widget.launcherService.sendMediaKey(keyCode);
  }

  void _toggleDvr() async {
    HapticFeedback.mediumImpact();
    final res = await widget.launcherService.startDvrRecording();
    if (mounted) {
      setState(() => _isDvrRecording = res);
    }
  }

  void _applyActivePipWindow() {
    final activeSlot = _slots[_activeSlotIndex];
    widget.launcherService.setPipWindow(
      packageName: activeSlot.packageName,
      activityName: activeSlot.activityName,
      x: 742,
      y: 68,
      width: 510,
      height: 564,
    );
    widget.onSlotChanged?.call(activeSlot);
  }

  void _selectSlot(int index) {
    if (_activeSlotIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _activeSlotIndex = index;
    });
    _applyActivePipWindow();
  }

  void _maximizeActiveApp() {
    HapticFeedback.mediumImpact();
    final activeSlot = _slots[_activeSlotIndex];
    widget.launcherService.launchApp(
      activeSlot.packageName,
      activityName: activeSlot.activityName,
    );
  }

  void _openReassignDialog(BuildContext context, CustomThemeColors colors) async {
    HapticFeedback.lightImpact();
    final apps = await widget.launcherService.getInstalledApps();
    if (!mounted || !context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _ReassignAppSheet(
        colors: colors,
        installedApps: apps,
        activeSlot: _slots[_activeSlotIndex],
        onAppSelected: (app) {
          Navigator.of(sheetContext).pop();
          setState(() {
            _slots[_activeSlotIndex] = _slots[_activeSlotIndex].copyWith(
              label: app.label,
              packageName: app.packageName,
              activityName: app.activityName,
            );
          });
          _applyActivePipWindow();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeEngine = context.watch<ThemeEngine?>();
    final colors = themeEngine?.colors ?? const CustomThemeColors();
    final activeSlot = _slots[_activeSlotIndex];

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
          // 1. Top Segmented Tab Bar
          Row(
            children: [
              for (int i = 0; i < _slots.length; i++) ...[
                Expanded(
                  child: _PipTabButton(
                    key: Key('pip_tab_${_slots[i].id}'),
                    label: _slots[i].label,
                    icon: _slots[i].icon,
                    isActive: i == _activeSlotIndex,
                    colors: colors,
                    onTap: () => _selectSlot(i),
                  ),
                ),
                if (i < _slots.length - 1) const SizedBox(width: 6),
              ],
              if (activeSlot.isConfigurable) ...[
                const SizedBox(width: 6),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const Key('pip_reassign_button'),
                    onTap: () => _openReassignDialog(context, colors),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.background.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.textMuted.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.settings_outlined,
                        size: 16,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 10),

          // 2. Main PIP Live View Surface (Tactile automotive controller & app portal)
          Expanded(
            child: Stack(
              key: const Key('pip_live_surface'),
              children: [
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    decoration: BoxDecoration(
                      color: colors.background.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(
                        color: colors.primaryAccent.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: _buildActiveSurface(activeSlot, colors),
                  ),
                ),

                // Corner Maximize Fullscreen Button
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('pip_maximize_button'),
                      onTap: _maximizeActiveApp,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colors.surfaceCard.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colors.primaryAccent.withValues(alpha: 0.4),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fullscreen_rounded,
                              size: 16,
                              color: colors.primaryAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'FULL',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: colors.textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSurface(PipSlotConfig activeSlot, CustomThemeColors colors) {
    if (activeSlot.packageName == NativeAppLauncherService.pkgRadio) {
      return _buildRadioCard(colors);
    } else if (activeSlot.packageName == NativeAppLauncherService.pkgDvr) {
      return _buildDvrCard(colors);
    } else if (activeSlot.packageName == NativeAppLauncherService.pkgTlink5) {
      return _buildTlinkCard(colors);
    } else {
      return _buildGenericAppCard(activeSlot, colors);
    }
  }

  Widget _buildRadioCard(CustomThemeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.radio_rounded, color: colors.primaryAccent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RADIO & AUDIO',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.textMain,
                    ),
                  ),
                  Text(
                    'TS18 Automotive Tuner',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Volume Controller Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('pip_volume_mute_button'),
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: _isMuted ? Colors.redAccent : colors.primaryAccent,
                  size: 20,
                ),
                onPressed: _toggleMute,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                key: const Key('pip_volume_down_button'),
                icon: Icon(Icons.remove_circle_outline_rounded, color: colors.textMain, size: 20),
                onPressed: () => _changeVolume(-1),
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'VOL: $_volume / $_maxVolume',
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryAccent,
                  ),
                ),
              ),
              IconButton(
                key: const Key('pip_volume_up_button'),
                icon: Icon(Icons.add_circle_outline_rounded, color: colors.textMain, size: 20),
                onPressed: () => _changeVolume(1),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Media Quick Action Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildMediaButton(
              key: const Key('pip_media_prev_button'),
              icon: Icons.skip_previous_rounded,
              label: 'PREV',
              colors: colors,
              onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaPrevious),
            ),
            _buildMediaButton(
              key: const Key('pip_media_play_button'),
              icon: Icons.play_arrow_rounded,
              label: 'PLAY',
              colors: colors,
              onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaPlayPause),
            ),
            _buildMediaButton(
              key: const Key('pip_media_next_button'),
              icon: Icons.skip_next_rounded,
              label: 'NEXT',
              colors: colors,
              onTap: () => _sendMediaKey(NativeAppLauncherService.keyCodeMediaNext),
            ),
          ],
        ),

        // Open App Button
        SizedBox(
          width: double.infinity,
          height: 38,
          child: ElevatedButton.icon(
            key: const Key('pip_action_launch_radio'),
            onPressed: _maximizeActiveApp,
            icon: const Icon(Icons.radio_rounded, size: 16),
            label: const Text(
              'OPEN RADIO TUNER',
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primaryAccent.withValues(alpha: 0.2),
              foregroundColor: colors.primaryAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaButton({
    required Key key,
    required IconData icon,
    required String label,
    required CustomThemeColors colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.primaryAccent),
              const SizedBox(width: 4),
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

  Widget _buildDvrCard(CustomThemeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.videocam_rounded, color: colors.primaryAccent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HD DASHCAM (DVR)',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.textMain,
                    ),
                  ),
                  Text(
                    'Topway TS18 USB / AV Input',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isDvrRecording
                    ? const Color(0xFF00E676).withValues(alpha: 0.18)
                    : Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isDvrRecording ? const Color(0xFF00E676) : Colors.amber,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isDvrRecording ? const Color(0xFF00E676) : Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isDvrRecording ? 'REC ACTIVE' : 'STANDBY',
                    style: TextStyle(
                      fontFamily: 'RobotoMono',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _isDvrRecording ? const Color(0xFF00E676) : Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.sd_card_rounded, color: colors.textMuted, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Continuous loop recording • Direct TS18 hardware trigger on ignition',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: colors.textMuted),
                ),
              ),
            ],
          ),
        ),

        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  key: const Key('pip_action_record_dvr'),
                  onPressed: _toggleDvr,
                  icon: Icon(_isDvrRecording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded, size: 16),
                  label: Text(
                    _isDvrRecording ? 'STOP REC' : 'START REC',
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isDvrRecording ? Colors.redAccent : const Color(0xFF00E676),
                    side: BorderSide(
                      color: _isDvrRecording ? Colors.redAccent : const Color(0xFF00E676),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  key: const Key('pip_action_launch_dvr'),
                  onPressed: _maximizeActiveApp,
                  icon: const Icon(Icons.fullscreen_rounded, size: 16),
                  label: const Text(
                    'VIEW CAMERA',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryAccent.withValues(alpha: 0.2),
                    foregroundColor: colors.primaryAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTlinkCard(CustomThemeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.phone_android_rounded, color: colors.primaryAccent, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PHONE & SMART LINK',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: colors.textMain,
                    ),
                  ),
                  Text(
                    'CarPlay • Android Auto (TLINK5)',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.textMuted.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: colors.primaryAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Android Auto operates via 5GHz Wi-Fi link without competing with OBD Bluetooth.',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: colors.textMuted),
                ),
              ),
            ],
          ),
        ),

        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  key: const Key('pip_action_launch_tlink'),
                  onPressed: _maximizeActiveApp,
                  icon: const Icon(Icons.screen_share_rounded, size: 16),
                  label: const Text(
                    'OPEN TLINK5',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryAccent.withValues(alpha: 0.2),
                    foregroundColor: colors.primaryAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  key: const Key('pip_action_launch_bt'),
                  onPressed: () => widget.launcherService.launchBluetooth(),
                  icon: const Icon(Icons.call_rounded, size: 16),
                  label: const Text(
                    'PHONE APP',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.textMain,
                    side: BorderSide(color: colors.textMuted.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenericAppCard(PipSlotConfig slot, CustomThemeColors colors) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Icon(slot.icon, size: 44, color: colors.primaryAccent),
        Column(
          children: [
            Text(
              slot.label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: colors.textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              slot.packageName,
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: ElevatedButton.icon(
            key: Key('pip_action_launch_${slot.id}'),
            onPressed: _maximizeActiveApp,
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(
              'OPEN ${slot.label.toUpperCase()}',
              style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w800),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primaryAccent.withValues(alpha: 0.2),
              foregroundColor: colors.primaryAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.primaryAccent.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PipTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final CustomThemeColors colors;
  final VoidCallback onTap;

  const _PipTabButton({
    super.key,
    required this.label,
    required this.icon,
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primaryAccent.withValues(alpha: 0.18)
                : colors.background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? colors.primaryAccent.withValues(alpha: 0.7)
                  : colors.textMuted.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? colors.primaryAccent : colors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive ? colors.primaryAccent : colors.textMuted,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReassignAppSheet extends StatelessWidget {
  final CustomThemeColors colors;
  final List<DiscoveredAppInfo> installedApps;
  final PipSlotConfig activeSlot;
  final ValueChanged<DiscoveredAppInfo> onAppSelected;

  const _ReassignAppSheet({
    required this.colors,
    required this.installedApps,
    required this.activeSlot,
    required this.onAppSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('pip_reassign_sheet'),
      height: 480,
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: colors.primaryAccent.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.textMuted.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: colors.primaryAccent, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Reassign ${activeSlot.label} Slot',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.textMain,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: colors.textMuted,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: installedApps.isEmpty
                ? Center(
                    child: Text(
                      'No launchable apps discovered',
                      style: TextStyle(color: colors.textMuted),
                    ),
                  )
                : ListView.builder(
                    itemCount: installedApps.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (ctx, index) {
                      final app = installedApps[index];
                      final isSelected = app.packageName == activeSlot.packageName;

                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          key: Key('reassign_app_${app.packageName}'),
                          leading: CircleAvatar(
                            backgroundColor: isSelected
                                ? colors.primaryAccent.withValues(alpha: 0.2)
                                : colors.background,
                            child: Icon(
                              Icons.apps_rounded,
                              size: 18,
                              color: isSelected ? colors.primaryAccent : colors.textMuted,
                            ),
                          ),
                          title: Text(
                            app.label,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? colors.primaryAccent : colors.textMain,
                            ),
                          ),
                          subtitle: Text(
                            app.packageName,
                            style: TextStyle(
                              fontFamily: 'RobotoMono',
                              fontSize: 11,
                              color: colors.textMuted,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle_rounded, color: colors.primaryAccent)
                              : null,
                          onTap: () => onAppSelected(app),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
