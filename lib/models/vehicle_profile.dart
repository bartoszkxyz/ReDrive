import 'package:flutter/foundation.dart';

/// Supported engine fuel types with stoichiometric air-fuel ratio (AFR)
/// and fuel density specifications.
enum FuelType {
  gasoline,
  lpg,
  diesel,
  hybrid;

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case FuelType.gasoline:
        return 'Gasoline';
      case FuelType.lpg:
        return 'LPG';
      case FuelType.diesel:
        return 'Diesel';
      case FuelType.hybrid:
        return 'Hybrid';
    }
  }

  /// Default stoichiometric air-to-fuel ratio (mass basis).
  double get defaultStoichAfr {
    switch (this) {
      case FuelType.gasoline:
        return 14.7;
      case FuelType.lpg:
        return 15.5;
      case FuelType.diesel:
        return 14.5;
      case FuelType.hybrid:
        return 14.7;
    }
  }

  /// Default fuel density in grams per liter (g/L) at 15 °C.
  double get defaultDensityGramsPerLiter {
    switch (this) {
      case FuelType.gasoline:
        return 820.0;
      case FuelType.lpg:
        return 540.0;
      case FuelType.diesel:
        return 840.0;
      case FuelType.hybrid:
        return 820.0;
    }
  }

  /// Parses a fuel type string case-insensitively, supporting common synonyms.
  /// Defaults to [FuelType.gasoline] if unmatched or null.
  static FuelType fromString(String? raw) {
    if (raw == null) return FuelType.gasoline;
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'gasoline':
      case 'petrol':
        return FuelType.gasoline;
      case 'lpg':
        return FuelType.lpg;
      case 'diesel':
        return FuelType.diesel;
      case 'hybrid':
        return FuelType.hybrid;
      default:
        return FuelType.gasoline;
    }
  }
}

/// A recurring vehicle maintenance interval tracked against odometer distance.
class MaintenanceItem {
  final String id;
  final String name;
  final double intervalKm;
  final double lastServiceOdometerKm;
  final DateTime? lastServiceDate;

  const MaintenanceItem({
    required this.id,
    required this.name,
    required this.intervalKm,
    this.lastServiceOdometerKm = 0.0,
    this.lastServiceDate,
  });

  /// Odometer reading at which next service is due.
  double get nextDueOdometerKm => lastServiceOdometerKm + intervalKm;

  /// Remaining distance until service is due (can be negative if overdue).
  double remainingKm(double currentOdometerKm) =>
      nextDueOdometerKm - currentOdometerKm;

  /// Progress ratio from 0.0 (freshly serviced) to 1.0 (service due).
  /// Clamped between 0.0 and 2.0 to guard against wild overflows.
  double progress(double currentOdometerKm) => intervalKm <= 0
      ? 1.0
      : ((currentOdometerKm - lastServiceOdometerKm) / intervalKm)
          .clamp(0.0, 2.0);

  /// True if the current odometer reading has exceeded the service interval.
  bool isOverdue(double currentOdometerKm) =>
      remainingKm(currentOdometerKm) <= 0;

  /// True if service is not yet overdue, but within [thresholdKm] (default 1000 km).
  bool isDueSoon(double currentOdometerKm, {double thresholdKm = 1000.0}) =>
      !isOverdue(currentOdometerKm) &&
      remainingKm(currentOdometerKm) <= thresholdKm;

  /// Returns a copy of this item marked as serviced at [atOdometerKm].
  MaintenanceItem markServiced({
    required double atOdometerKm,
    DateTime? atDate,
  }) {
    return MaintenanceItem(
      id: id,
      name: name,
      intervalKm: intervalKm,
      lastServiceOdometerKm: atOdometerKm,
      lastServiceDate: atDate ?? DateTime.now(),
    );
  }

  MaintenanceItem copyWith({
    String? id,
    String? name,
    double? intervalKm,
    double? lastServiceOdometerKm,
    DateTime? lastServiceDate,
  }) {
    return MaintenanceItem(
      id: id ?? this.id,
      name: name ?? this.name,
      intervalKm: intervalKm ?? this.intervalKm,
      lastServiceOdometerKm:
          lastServiceOdometerKm ?? this.lastServiceOdometerKm,
      lastServiceDate: lastServiceDate ?? this.lastServiceDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intervalKm': intervalKm,
        'lastServiceOdometerKm': lastServiceOdometerKm,
        if (lastServiceDate != null)
          'lastServiceDate': lastServiceDate!.toIso8601String(),
      };

  factory MaintenanceItem.fromJson(Map<String, dynamic> json) {
    return MaintenanceItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      intervalKm: _toDouble(json['intervalKm']),
      lastServiceOdometerKm: _toDouble(json['lastServiceOdometerKm']),
      lastServiceDate: json['lastServiceDate'] != null
          ? DateTime.tryParse(json['lastServiceDate'].toString())
          : null,
    );
  }

  static double _toDouble(dynamic val, [double defaultValue = 0.0]) {
    if (val == null) return defaultValue;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? defaultValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaintenanceItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          intervalKm == other.intervalKm &&
          lastServiceOdometerKm == other.lastServiceOdometerKm &&
          lastServiceDate == other.lastServiceDate;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        intervalKm,
        lastServiceOdometerKm,
        lastServiceDate,
      );

  @override
  String toString() =>
      'MaintenanceItem(id: $id, name: $name, intervalKm: $intervalKm, '
      'lastServiceOdo: $lastServiceOdometerKm, lastDate: $lastServiceDate)';
}

/// Vehicle configuration profile storing vehicle parameters, thresholds,
/// and maintenance schedule.
class VehicleProfile {
  final String id;
  final String name;
  final String? vin;
  final int? year;
  final double displacementLiters;
  final FuelType fuelType;
  final double fuelTankCapacityLiters;
  final double idleThrottleBaselinePercent;
  final double wotThrottleBaselinePercent;
  final double nominalVoltage;
  final int redlineRpm;
  final int optimalShiftRpm;
  final int coolantOverheatTempC;
  final int maxHorsepower;
  final int? curbWeightKg;
  final double baseOdometerKm;
  final String? sourceAutoDataUrl;
  final List<MaintenanceItem> maintenanceItems;

  const VehicleProfile({
    required this.id,
    required this.name,
    this.vin,
    this.year,
    this.displacementLiters = 1.5,
    this.fuelType = FuelType.gasoline,
    this.fuelTankCapacityLiters = 45.0,
    this.idleThrottleBaselinePercent = 13.0,
    this.wotThrottleBaselinePercent = 85.0,
    this.nominalVoltage = 14.2,
    this.redlineRpm = 6500,
    this.optimalShiftRpm = 3200,
    this.coolantOverheatTempC = 102,
    this.maxHorsepower = 102,
    this.curbWeightKg = 1015,
    this.baseOdometerKm = 0.0,
    this.sourceAutoDataUrl,
    this.maintenanceItems = const [],
  });

  /// Effective total vehicle odometer including cumulative trip distance.
  double effectiveOdometerKm(double cumulativeTripDistanceKm) =>
      baseOdometerKm + cumulativeTripDistanceKm;

  /// Default maintenance checklist for standard passenger vehicles.
  static List<MaintenanceItem> defaultMaintenanceItems({
    double baseOdometerKm = 150000.0,
  }) =>
      [
        MaintenanceItem(
          id: 'oil_filter',
          name: 'Engine Oil & Filter',
          intervalKm: 10000.0,
          lastServiceOdometerKm: baseOdometerKm,
        ),
        MaintenanceItem(
          id: 'air_cabin_filter',
          name: 'Air & Cabin Filters',
          intervalKm: 15000.0,
          lastServiceOdometerKm: baseOdometerKm,
        ),
        MaintenanceItem(
          id: 'spark_plugs',
          name: 'Spark Plugs',
          intervalKm: 30000.0,
          lastServiceOdometerKm: baseOdometerKm,
        ),
        MaintenanceItem(
          id: 'valve_clearance',
          name: 'Valve Clearance Check',
          intervalKm: 40000.0,
          lastServiceOdometerKm: baseOdometerKm,
        ),
      ];

  /// Preset profile for the project benchmark car: 2007 Suzuki Swift 3 (M15A 1.5L VVT).
  factory VehicleProfile.defaultSuzukiSwiftM15A() {
    const baseOdo = 150000.0;
    return VehicleProfile(
      id: 'default_swift_m15a',
      name: 'Suzuki Swift 3 (M15A 1.5L)',
      year: 2007,
      displacementLiters: 1.5,
      fuelType: FuelType.gasoline,
      fuelTankCapacityLiters: 45.0,
      idleThrottleBaselinePercent: 13.0,
      wotThrottleBaselinePercent: 85.0,
      nominalVoltage: 14.2,
      redlineRpm: 6500,
      optimalShiftRpm: 3200,
      coolantOverheatTempC: 102,
      maxHorsepower: 102,
      curbWeightKg: 1015,
      baseOdometerKm: baseOdo,
      maintenanceItems: defaultMaintenanceItems(baseOdometerKm: baseOdo),
    );
  }

  VehicleProfile copyWith({
    String? id,
    String? name,
    String? vin,
    int? year,
    double? displacementLiters,
    FuelType? fuelType,
    double? fuelTankCapacityLiters,
    double? idleThrottleBaselinePercent,
    double? wotThrottleBaselinePercent,
    double? nominalVoltage,
    int? redlineRpm,
    int? optimalShiftRpm,
    int? coolantOverheatTempC,
    int? maxHorsepower,
    int? curbWeightKg,
    double? baseOdometerKm,
    String? sourceAutoDataUrl,
    List<MaintenanceItem>? maintenanceItems,
  }) {
    return VehicleProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      vin: vin ?? this.vin,
      year: year ?? this.year,
      displacementLiters: displacementLiters ?? this.displacementLiters,
      fuelType: fuelType ?? this.fuelType,
      fuelTankCapacityLiters:
          fuelTankCapacityLiters ?? this.fuelTankCapacityLiters,
      idleThrottleBaselinePercent:
          idleThrottleBaselinePercent ?? this.idleThrottleBaselinePercent,
      wotThrottleBaselinePercent:
          wotThrottleBaselinePercent ?? this.wotThrottleBaselinePercent,
      nominalVoltage: nominalVoltage ?? this.nominalVoltage,
      redlineRpm: redlineRpm ?? this.redlineRpm,
      optimalShiftRpm: optimalShiftRpm ?? this.optimalShiftRpm,
      coolantOverheatTempC: coolantOverheatTempC ?? this.coolantOverheatTempC,
      maxHorsepower: maxHorsepower ?? this.maxHorsepower,
      curbWeightKg: curbWeightKg ?? this.curbWeightKg,
      baseOdometerKm: baseOdometerKm ?? this.baseOdometerKm,
      sourceAutoDataUrl: sourceAutoDataUrl ?? this.sourceAutoDataUrl,
      maintenanceItems: maintenanceItems ?? this.maintenanceItems,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'vin': vin,
        'year': year,
        'displacementLiters': displacementLiters,
        'fuelType': fuelType.name,
        'fuelTankCapacityLiters': fuelTankCapacityLiters,
        'idleThrottleBaselinePercent': idleThrottleBaselinePercent,
        'wotThrottleBaselinePercent': wotThrottleBaselinePercent,
        'nominalVoltage': nominalVoltage,
        'redlineRpm': redlineRpm,
        'optimalShiftRpm': optimalShiftRpm,
        'coolantOverheatTempC': coolantOverheatTempC,
        'maxHorsepower': maxHorsepower,
        'curbWeightKg': curbWeightKg,
        'baseOdometerKm': baseOdometerKm,
        'sourceAutoDataUrl': sourceAutoDataUrl,
        'maintenanceItems':
            maintenanceItems.map((item) => item.toJson()).toList(),
      };

  factory VehicleProfile.fromJson(Map<String, dynamic> json) {
    final parsedItems = <MaintenanceItem>[];
    final rawItems = json['maintenanceItems'];
    if (rawItems is Iterable) {
      for (final item in rawItems) {
        if (item is Map<String, dynamic>) {
          parsedItems.add(MaintenanceItem.fromJson(item));
        } else if (item is Map) {
          parsedItems.add(
              MaintenanceItem.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    return VehicleProfile(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      vin: json['vin']?.toString(),
      year: json['year'] != null ? _toInt(json['year']) : null,
      displacementLiters: _toDouble(json['displacementLiters'], 1.5),
      fuelType: FuelType.fromString(json['fuelType']?.toString()),
      fuelTankCapacityLiters: _toDouble(json['fuelTankCapacityLiters'], 45.0),
      idleThrottleBaselinePercent:
          _toDouble(json['idleThrottleBaselinePercent'], 13.0),
      wotThrottleBaselinePercent:
          _toDouble(json['wotThrottleBaselinePercent'], 85.0),
      nominalVoltage: _toDouble(json['nominalVoltage'], 14.2),
      redlineRpm: _toInt(json['redlineRpm'], 6500),
      optimalShiftRpm: _toInt(json['optimalShiftRpm'], 3200),
      coolantOverheatTempC: _toInt(json['coolantOverheatTempC'], 102),
      maxHorsepower: _toInt(json['maxHorsepower'], 102),
      curbWeightKg: json['curbWeightKg'] != null
          ? _toInt(json['curbWeightKg'], 1015)
          : (json.containsKey('curbWeightKg') ? null : 1015),
      baseOdometerKm: _toDouble(json['baseOdometerKm'], 0.0),
      sourceAutoDataUrl: json['sourceAutoDataUrl']?.toString(),
      maintenanceItems: parsedItems,
    );
  }

  static double _toDouble(dynamic val, [double defaultValue = 0.0]) {
    if (val == null) return defaultValue;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? defaultValue;
  }

  static int _toInt(dynamic val, [int defaultValue = 0]) {
    if (val == null) return defaultValue;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? defaultValue;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          vin == other.vin &&
          year == other.year &&
          displacementLiters == other.displacementLiters &&
          fuelType == other.fuelType &&
          fuelTankCapacityLiters == other.fuelTankCapacityLiters &&
          idleThrottleBaselinePercent == other.idleThrottleBaselinePercent &&
          wotThrottleBaselinePercent == other.wotThrottleBaselinePercent &&
          nominalVoltage == other.nominalVoltage &&
          redlineRpm == other.redlineRpm &&
          optimalShiftRpm == other.optimalShiftRpm &&
          coolantOverheatTempC == other.coolantOverheatTempC &&
          maxHorsepower == other.maxHorsepower &&
          curbWeightKg == other.curbWeightKg &&
          baseOdometerKm == other.baseOdometerKm &&
          sourceAutoDataUrl == other.sourceAutoDataUrl &&
          listEquals(maintenanceItems, other.maintenanceItems);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        vin,
        year,
        displacementLiters,
        fuelType,
        fuelTankCapacityLiters,
        idleThrottleBaselinePercent,
        wotThrottleBaselinePercent,
        nominalVoltage,
        redlineRpm,
        optimalShiftRpm,
        coolantOverheatTempC,
        maxHorsepower,
        curbWeightKg,
        baseOdometerKm,
        sourceAutoDataUrl,
        Object.hashAll(maintenanceItems),
      );

  @override
  String toString() =>
      'VehicleProfile(id: $id, name: $name, year: $year, fuel: ${fuelType.label}, '
      'displacement: ${displacementLiters}L, tank: ${fuelTankCapacityLiters}L, '
      'baseOdo: $baseOdometerKm km, items: ${maintenanceItems.length})';
}
