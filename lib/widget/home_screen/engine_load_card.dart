import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Engine Load card for the Home screen.
/// Displays calculated engine load percentage with dynamic color indicators
/// for efficient (eco) and inefficient (heavy load) ranges.
class EngineLoadCard extends StatelessWidget {
  final double load;
  final bool isConnected;
  final bool isDemo;
  final String title;

  const EngineLoadCard({
    super.key,
    required this.load,
    required this.isConnected,
    this.isDemo = false,
    this.title = 'ENGINE LOAD',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOnline = isConnected || isDemo || load > 0;

    final _LoadStatus status = _resolveStatus(load, isOnline);

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
          // Header row with Title and Efficiency Status Pill
          Row(
            children: [
              SvgPicture.asset(
                'assets/images/svg/dashboard/engine.svg',
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
                  title.toUpperCase(),
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

          // Main Load Readout & Efficiency Guidance Note
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
                      end: isOnline ? load : 0.0,
                    ),
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    builder: (context, animValue, _) {
                      return Text(
                        isOnline ? animValue.toStringAsFixed(1) : '--',
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
                    '%',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 16,
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

          // Segmented gauge colored according to efficiency state
          _LoadSegmentedIndicator(
            progress: isOnline ? (load / 100.0).clamp(0.0, 1.0) : 0.0,
            activeColor: isOnline ? status.color : colorScheme.primary,
          ),
        ],
      ),
    );
  }

  static _LoadStatus _resolveStatus(double load, bool isOnline) {
    if (!isOnline) {
      return const _LoadStatus(
        badgeText: 'STANDBY',
        color: Colors.grey,
        icon: Icons.power_settings_new_rounded,
        guidanceText: 'Awaiting ECU data...',
      );
    }

    if (load < 20.0) {
      return const _LoadStatus(
        badgeText: 'LIGHT',
        color: Color(0xFF4FC3F7), // Cyan low demand
        icon: Icons.eco_outlined,
        guidanceText: 'Low demand • Coasting / Idle',
      );
    } else if (load <= 55.0) {
      return const _LoadStatus(
        badgeText: 'EFFICIENT',
        color: Color(0xFF00E676), // Vibrant emerald green eco zone
        icon: Icons.eco_rounded,
        guidanceText: 'Optimal eco range • Peak efficiency',
      );
    } else if (load <= 75.0) {
      return const _LoadStatus(
        badgeText: 'MODERATE',
        color: Color(0xFFFFB74D), // Amber
        icon: Icons.trending_up_rounded,
        guidanceText: 'Moderate load • Normal acceleration',
      );
    } else {
      return const _LoadStatus(
        badgeText: 'INEFFICIENT',
        color: Color(0xFFFF5252), // Red heavy load
        icon: Icons.local_gas_station_rounded,
        guidanceText: 'Heavy engine load • Inefficient',
      );
    }
  }
}

/// Backwards compatibility alias
typedef FuelLoadCard = EngineLoadCard;

class _LoadStatus {
  final String badgeText;
  final Color color;
  final IconData icon;
  final String guidanceText;

  const _LoadStatus({
    required this.badgeText,
    required this.color,
    required this.icon,
    required this.guidanceText,
  });
}

class _LoadSegmentedIndicator extends StatelessWidget {
  final double progress;
  final Color activeColor;

  const _LoadSegmentedIndicator({
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
          duration: const Duration(milliseconds: 250),
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
