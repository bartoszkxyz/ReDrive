import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class TelemetryCard extends StatelessWidget {
  final String title;
  final double value;
  final String valueSuffix;
  final int fractionDigits;
  final String unit;
  final String iconPath;
  final double progress;
  final Color? statusColor;
  final String? statusBadge;

  const TelemetryCard({
    super.key,
    required this.title,
    required this.value,
    this.valueSuffix = '',
    this.fractionDigits = 0,
    required this.unit,
    required this.iconPath,
    required this.progress,
    this.statusColor,
    this.statusBadge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveAccentColor = statusColor ?? colorScheme.primary;
    final hasStatus = statusColor != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasStatus
              ? statusColor!.withValues(alpha: 0.7)
              : colorScheme.onSurface.withValues(alpha: 0.05),
          width: hasStatus ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: title,
            iconPath: iconPath,
            colorScheme: colorScheme,
            accentColor: effectiveAccentColor,
            statusBadge: statusBadge,
            statusColor: statusColor,
          ),
          const Spacer(),

          _AnimatedValue(
            value: value,
            suffix: valueSuffix,
            fractionDigits: fractionDigits,
            unit: unit,
            colorScheme: colorScheme,
            valueColor: hasStatus ? statusColor : null,
          ),
          const Spacer(),

          _SegmentedIndicator(
            progress: progress,
            colorScheme: colorScheme,
            fillColor: effectiveAccentColor,
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String title;
  final String iconPath;
  final ColorScheme colorScheme;
  final Color accentColor;
  final String? statusBadge;
  final Color? statusColor;

  const _CardHeader({
    required this.title,
    required this.iconPath,
    required this.colorScheme,
    required this.accentColor,
    this.statusBadge,
    this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(
          iconPath,
          width: 16,
          height: 16,
          colorFilter: ColorFilter.mode(accentColor, BlendMode.srcIn),
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
        if (statusBadge != null && statusColor != null) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor!.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: statusColor!, width: 1),
            ),
            child: Text(
              statusBadge!.toUpperCase(),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: statusColor,
                fontSize: 9,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnimatedValue extends StatelessWidget {
  final double value;
  final String suffix;
  final int fractionDigits;
  final String unit;
  final ColorScheme colorScheme;
  final Color? valueColor;

  const _AnimatedValue({
    required this.value,
    required this.suffix,
    required this.fractionDigits,
    required this.unit,
    required this.colorScheme,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: value),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          builder: (context, animValue, _) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                "${animValue.toStringAsFixed(fractionDigits)}$suffix",
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: valueColor ?? colorScheme.onSurface,
                  fontSize: 40,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
            );
          },
        ),
        Text(
          unit.toUpperCase(),
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SegmentedIndicator extends StatelessWidget {
  final double progress;
  final ColorScheme colorScheme;
  final Color? fillColor;

  const _SegmentedIndicator({
    required this.progress,
    required this.colorScheme,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = fillColor ?? colorScheme.primary;

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
