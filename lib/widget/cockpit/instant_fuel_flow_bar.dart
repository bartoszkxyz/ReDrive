import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/custom_dashboard_theme.dart';
import '../../core/theme/theme_engine.dart';
import '../../providers/obd_provider.dart';
import '../../providers/trip_provider.dart';

/// Horizontal dynamic fuel consumption bar displaying instant L/100km, L/h,
/// and highlighted DFCO (Deceleration Fuel Cut-Off) status badge.
class InstantFuelFlowBar extends StatelessWidget {
  final double? instantFuelL100km;
  final double? instantFuelLPerHour;
  final bool? isDfcoActive;

  const InstantFuelFlowBar({
    super.key,
    this.instantFuelL100km,
    this.instantFuelLPerHour,
    this.isDfcoActive,
  });

  @override
  Widget build(BuildContext context) {
    final tripProvider = context.watch<TripProvider?>();
    final obdProvider = context.watch<ObdProvider?>();
    final themeEngine = context.watch<ThemeEngine?>();

    final colors = themeEngine?.colors ?? const CustomThemeColors();

    final activeTrip = tripProvider?.activeTrip;
    final l100km = instantFuelL100km ?? activeTrip?.instantFuelL100km ?? 0.0;
    final lph = instantFuelLPerHour ?? activeTrip?.instantFuelLPerHour ?? 0.0;
    final dfco = isDfcoActive ?? obdProvider?.data.isDfcoActive ?? false;

    final isStationary = (activeTrip?.currentSpeed ?? 0) == 0 && l100km == 0.0;
    final progress = isStationary
        ? (lph / 5.0).clamp(0.0, 1.0)
        : (l100km / 20.0).clamp(0.0, 1.0);

    return Container(
      key: const Key('instant_fuel_flow_bar'),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: colors.surfaceCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: dfco
              ? colors.primaryAccent.withValues(alpha: 0.7)
              : colors.textMuted.withValues(alpha: 0.15),
          width: dfco ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.speed,
                    size: 16,
                    color: colors.primaryAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'INSTANT FUEL CONSUMPTION',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
              if (dfco)
                Container(
                  key: const Key('dfco_active_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.primaryAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: colors.primaryAccent,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primaryAccent,
                          boxShadow: [
                            BoxShadow(
                              color: colors.primaryAccent.withValues(alpha: 0.8),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'DFCO: ACTIVE',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: colors.primaryAccent,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.0),
            child: Stack(
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6.0),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.02, 1.0),
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.fuelFlowBarStart,
                          colors.fuelFlowBarEnd,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(6.0),
                      boxShadow: [
                        BoxShadow(
                          color: colors.fuelFlowBarStart.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${l100km.toStringAsFixed(1)} L/100km',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textMain,
                ),
              ),
              Text(
                '${lph.toStringAsFixed(1)} L/h',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
              Text(
                isStationary ? 'Stationary Idle' : '0 - 20 L/100km',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
