import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Engine coolant temperature card for the Home screen.
/// Visually indicates warm-up phase, ready-to-drive optimal temperature,
/// or high temperature / overheating alerts.
class EngineTempCard extends StatelessWidget {
  final int coolantTemp;
  final bool isConnected;
  final bool isDemo;

  const EngineTempCard({
    super.key,
    required this.coolantTemp,
    required this.isConnected,
    this.isDemo = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOnline = isConnected || isDemo || coolantTemp > 0;

    final _TempStatus status = _resolveStatus(coolantTemp, isOnline);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status.color.withValues(alpha: isOnline ? 0.2 : 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with Title and Ready-to-Drive Status Pill
          Row(
            children: [
              SvgPicture.asset(
                'assets/images/svg/dashboard/temp.svg',
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  isOnline ? status.color : colorScheme.primary,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ENGINE TEMP',
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: status.color.withValues(alpha: 0.8),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(status.icon, size: 11, color: status.color),
                    const SizedBox(width: 4),
                    Text(
                      status.badgeText,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        color: status.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Spacer(),

          // Main Temperature readout & Ready-to-Drive guidance
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0.0,
                      end: isOnline ? coolantTemp.toDouble() : 0.0,
                    ),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, animValue, _) {
                      return Text(
                        isOnline ? animValue.round().toString() : '--',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: isOnline ? colorScheme.onSurface : Colors.white38,
                          fontSize: 38,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '°C',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                status.guidanceText,
                textScaler: TextScaler.noScaling,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isOnline
                      ? status.color.withValues(alpha: 0.9)
                      : colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Segmented gauge colored to reflect warm-up / ready state
          _TempSegmentedIndicator(
            progress: isOnline ? (coolantTemp / 110.0).clamp(0.0, 1.0) : 0.0,
            activeColor: isOnline ? status.color : colorScheme.primary,
          ),
        ],
      ),
    );
  }

  static _TempStatus _resolveStatus(int temp, bool isOnline) {
    if (!isOnline) {
      return const _TempStatus(
        badgeText: 'STANDBY',
        color: Colors.grey,
        icon: Icons.power_settings_new_rounded,
        guidanceText: 'Awaiting ECU data...',
      );
    }

    if (temp < 50) {
      return const _TempStatus(
        badgeText: 'WARMING UP',
        color: Color(0xFF4FC3F7), // Cold cyan
        icon: Icons.hourglass_bottom_rounded,
        guidanceText: 'Engine cold • Keep revs low',
      );
    } else if (temp < 75) {
      return const _TempStatus(
        badgeText: 'WARMING UP',
        color: Color(0xFFFFB74D), // Amber warm
        icon: Icons.trending_up_rounded,
        guidanceText: 'Warming up • Moderate throttle',
      );
    } else if (temp <= 98) {
      return const _TempStatus(
        badgeText: 'READY TO DRIVE',
        color: Color(0xFF00E676), // Vibrant emerald optimal
        icon: Icons.check_circle_rounded,
        guidanceText: 'Optimal operating temp • Ready to drive',
      );
    } else if (temp <= 108) {
      return const _TempStatus(
        badgeText: 'HIGH TEMP',
        color: Color(0xFFFF7043), // Deep orange
        icon: Icons.thermostat_rounded,
        guidanceText: 'Elevated coolant temp • Fan active',
      );
    } else {
      return const _TempStatus(
        badgeText: 'OVERHEATING',
        color: Color(0xFFFF5252), // Red warning
        icon: Icons.warning_rounded,
        guidanceText: 'Overheating alert! Stop safely',
      );
    }
  }
}

class _TempStatus {
  final String badgeText;
  final Color color;
  final IconData icon;
  final String guidanceText;

  const _TempStatus({
    required this.badgeText,
    required this.color,
    required this.icon,
    required this.guidanceText,
  });
}

class _TempSegmentedIndicator extends StatelessWidget {
  final double progress;
  final Color activeColor;

  const _TempSegmentedIndicator({
    required this.progress,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final int segments = availableWidth < 180 ? 12 : 18;
        final double segmentWidth = availableWidth < 180 ? 4 : 5.5;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: progress),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, animProgress, _) {
            final filledSegments = (animProgress * segments).round();

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(segments, (index) {
                return Container(
                  width: segmentWidth,
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: index < filledSegments
                        ? activeColor
                        : colorScheme.onSurface.withValues(alpha: 0.1),
                  ),
                );
              }),
            );
          },
        );
      },
    );
  }
}
