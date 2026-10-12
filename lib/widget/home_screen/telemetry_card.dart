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

  const TelemetryCard({
    super.key,
    required this.title,
    required this.value,
    this.valueSuffix = '',
    this.fractionDigits = 0,
    required this.unit,
    required this.iconPath,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: title,
            iconPath: iconPath,
            colorScheme: colorScheme,
          ),
          const Spacer(),

          _AnimatedValue(
            value: value,
            suffix: valueSuffix,
            fractionDigits: fractionDigits,
            unit: unit,
            colorScheme: colorScheme,
          ),
          const Spacer(),

          _SegmentedIndicator(progress: progress, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final String title;
  final String iconPath;
  final ColorScheme colorScheme;

  const _CardHeader({
    required this.title,
    required this.iconPath,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SvgPicture.asset(
          iconPath,
          width: 16,
          height: 16,
          colorFilter: ColorFilter.mode(colorScheme.primary, BlendMode.srcIn),
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

  const _AnimatedValue({
    required this.value,
    required this.suffix,
    required this.fractionDigits,
    required this.unit,
    required this.colorScheme,
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
                  color: colorScheme.onSurface,
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

  const _SegmentedIndicator({
    required this.progress,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
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
                        ? colorScheme.primary
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
