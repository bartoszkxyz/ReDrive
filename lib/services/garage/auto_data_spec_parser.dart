import 'dart:convert';
import 'dart:io';

/// Parsed vehicle specifications from an `auto-data.net` HTML page.
class AutoDataVehicleSpecs {
  final String? title;
  final String? brand;
  final String? model;
  final String? generation;
  final String? engineModification;
  final int? year;
  final double? displacementLiters;
  final int? displacementCc;
  final String? fuelTypeKey; // 'gasoline', 'lpg', 'diesel', 'hybrid'
  final double? fuelTankCapacityLiters;
  final int? maxHorsepower;
  final int? maxPowerRpm;
  final int? redlineRpm;
  final int? curbWeightKg;
  final String? sourceUrl;

  const AutoDataVehicleSpecs({
    this.title,
    this.brand,
    this.model,
    this.generation,
    this.engineModification,
    this.year,
    this.displacementLiters,
    this.displacementCc,
    this.fuelTypeKey,
    this.fuelTankCapacityLiters,
    this.maxHorsepower,
    this.maxPowerRpm,
    this.redlineRpm,
    this.curbWeightKg,
    this.sourceUrl,
  });

  /// Returns true if at least one vehicle specification field was successfully parsed.
  bool get hasAnyParsedSpec =>
      title != null ||
      brand != null ||
      model != null ||
      generation != null ||
      engineModification != null ||
      year != null ||
      displacementLiters != null ||
      displacementCc != null ||
      fuelTypeKey != null ||
      fuelTankCapacityLiters != null ||
      maxHorsepower != null ||
      maxPowerRpm != null ||
      redlineRpm != null ||
      curbWeightKg != null;

  Map<String, dynamic> toJson() => {
        'title': title,
        'brand': brand,
        'model': model,
        'generation': generation,
        'engineModification': engineModification,
        'year': year,
        'displacementLiters': displacementLiters,
        'displacementCc': displacementCc,
        'fuelTypeKey': fuelTypeKey,
        'fuelTankCapacityLiters': fuelTankCapacityLiters,
        'maxHorsepower': maxHorsepower,
        'maxPowerRpm': maxPowerRpm,
        'redlineRpm': redlineRpm,
        'curbWeightKg': curbWeightKg,
        'sourceUrl': sourceUrl,
      };

  factory AutoDataVehicleSpecs.fromJson(Map<String, dynamic> json) =>
      AutoDataVehicleSpecs(
        title: json['title'] as String?,
        brand: json['brand'] as String?,
        model: json['model'] as String?,
        generation: json['generation'] as String?,
        engineModification: json['engineModification'] as String?,
        year: (json['year'] as num?)?.toInt(),
        displacementLiters: (json['displacementLiters'] as num?)?.toDouble(),
        displacementCc: (json['displacementCc'] as num?)?.toInt(),
        fuelTypeKey: json['fuelTypeKey'] as String?,
        fuelTankCapacityLiters:
            (json['fuelTankCapacityLiters'] as num?)?.toDouble(),
        maxHorsepower: (json['maxHorsepower'] as num?)?.toInt(),
        maxPowerRpm: (json['maxPowerRpm'] as num?)?.toInt(),
        redlineRpm: (json['redlineRpm'] as num?)?.toInt(),
        curbWeightKg: (json['curbWeightKg'] as num?)?.toInt(),
        sourceUrl: json['sourceUrl'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutoDataVehicleSpecs &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          brand == other.brand &&
          model == other.model &&
          generation == other.generation &&
          engineModification == other.engineModification &&
          year == other.year &&
          displacementLiters == other.displacementLiters &&
          displacementCc == other.displacementCc &&
          fuelTypeKey == other.fuelTypeKey &&
          fuelTankCapacityLiters == other.fuelTankCapacityLiters &&
          maxHorsepower == other.maxHorsepower &&
          maxPowerRpm == other.maxPowerRpm &&
          redlineRpm == other.redlineRpm &&
          curbWeightKg == other.curbWeightKg &&
          sourceUrl == other.sourceUrl;

  @override
  int get hashCode => Object.hash(
        title,
        brand,
        model,
        generation,
        engineModification,
        year,
        displacementLiters,
        displacementCc,
        fuelTypeKey,
        fuelTankCapacityLiters,
        maxHorsepower,
        maxPowerRpm,
        redlineRpm,
        curbWeightKg,
        sourceUrl,
      );

  @override
  String toString() =>
      'AutoDataVehicleSpecs(title: $title, brand: $brand, model: $model, '
      'displacement: ${displacementLiters}L ($displacementCc cc), fuel: $fuelTypeKey, '
      'tank: ${fuelTankCapacityLiters}L, power: ${maxHorsepower}hp @ ${maxPowerRpm}rpm, '
      'redline: ${redlineRpm}rpm, weight: ${curbWeightKg}kg)';
}

/// HTML parser and HTTP fetcher for vehicle specifications from `auto-data.net`.
class AutoDataSpecParser {
  final Future<String> Function(Uri uri)? _defaultHttpFetcher;

  const AutoDataSpecParser({
    Future<String> Function(Uri uri)? httpFetcher,
  }) : _defaultHttpFetcher = httpFetcher;

  /// Validates whether [rawUrl] is a supported `auto-data.net` vehicle URL.
  ///
  /// Returns `true` if [rawUrl] parses as HTTP or HTTPS and the host equals
  /// `'auto-data.net'` or ends with `'.auto-data.net'`.
  static bool isValidAutoDataUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return host == 'auto-data.net' || host.endsWith('.auto-data.net');
  }

  /// Calculates engine displacement in liters from displacement in cubic centimeters ([cc]).
  ///
  /// If [cc] is within 35cc of a 0.1L step (e.g. `1490 cm3` -> `1.5`, `1328 cm3` -> `1.3`,
  /// `1598 cm3` -> `1.6`, `1968 cm3` -> `2.0`), it is rounded to 1 decimal place.
  /// Otherwise, it is rounded to 2 decimal places (e.g. `1349 cm3` -> `1.35`).
  static double calculateDisplacementLiters(int cc) {
    final litersExact = cc / 1000.0;
    final nearestTenth = (litersExact * 10).round() / 10.0;
    final diffFromTenthCc = (cc - (nearestTenth * 1000).round()).abs();
    if (diffFromTenthCc <= 35) {
      return double.parse(nearestTenth.toStringAsFixed(1));
    } else {
      return double.parse(litersExact.toStringAsFixed(2));
    }
  }

  /// Parses specification data from the provided `auto-data.net` [html] markup.
  static AutoDataVehicleSpecs parseHtml(String html, {String? sourceUrl}) {
    // 1. Strip script, style, and comments
    final cleanHtml = html
        .replaceAll(RegExp(r'<script\b[^>]*>[\s\S]*?<\/script>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<style\b[^>]*>[\s\S]*?<\/style>', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');

    // 2. Extract key-value rows from HTML table rows and div rows
    final rowMap = <String, String>{};

    // Table rows: <tr>...<th>Key</th>...<td>Value</td>...</tr>
    final trRegex = RegExp(r'<tr\b[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true);
    for (final trMatch in trRegex.allMatches(cleanHtml)) {
      final trInner = trMatch.group(1)!;
      final cellRegex = RegExp(
        r'<(?:th|td)\b[^>]*>(.*?)</(?:th|td)>',
        caseSensitive: false,
        dotAll: true,
      );
      final cells = cellRegex
          .allMatches(trInner)
          .map((m) => _stripTagsAndDecode(m.group(1)!))
          .where((s) => s.isNotEmpty)
          .toList();
      if (cells.length >= 2) {
        final k = cells[0].toLowerCase();
        rowMap.putIfAbsent(k, () => cells[1]);
      }
    }

    // Modern div rows: <div class="par">Key</div>...<div class="val">Value</div>
    final parValRegex = RegExp(
      r'''<div\b[^>]*class=["'][^"']*\bpar\b[^"']*["'][^>]*>(.*?)</div>\s*<div\b[^>]*class=["'][^"']*\bval\b[^"']*["'][^>]*>(.*?)</div>''',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in parValRegex.allMatches(cleanHtml)) {
      final k = _stripTagsAndDecode(match.group(1)!).toLowerCase();
      final v = _stripTagsAndDecode(match.group(2)!);
      if (k.isNotEmpty && v.isNotEmpty) {
        rowMap.putIfAbsent(k, () => v);
      }
    }

    // Definition lists: <dt>Key</dt><dd>Value</dd>
    final dtDdRegex = RegExp(
      r'<dt\b[^>]*>(.*?)</dt>\s*<dd\b[^>]*>(.*?)</dd>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in dtDdRegex.allMatches(cleanHtml)) {
      final k = _stripTagsAndDecode(match.group(1)!).toLowerCase();
      final v = _stripTagsAndDecode(match.group(2)!);
      if (k.isNotEmpty && v.isNotEmpty) {
        rowMap.putIfAbsent(k, () => v);
      }
    }

    // Helper to query row values
    String? getValue(List<String> candidateKeys) {
      // 1. Exact match
      for (final candidate in candidateKeys) {
        final cLower = candidate.toLowerCase();
        if (rowMap.containsKey(cLower)) {
          return rowMap[cLower];
        }
      }
      // 2. Exact match with trailing punctuation/colons removed
      for (final candidate in candidateKeys) {
        final cLower = candidate.toLowerCase();
        for (final entry in rowMap.entries) {
          final strippedKey = entry.key.replaceAll(RegExp(r'[:_.-]'), '').trim();
          if (strippedKey == cLower) {
            return entry.value;
          }
        }
      }
      // 3. Key starts with candidate + separator
      for (final candidate in candidateKeys) {
        final cLower = candidate.toLowerCase();
        for (final entry in rowMap.entries) {
          if (entry.key.startsWith('$cLower ') ||
              entry.key.startsWith('$cLower(') ||
              entry.key.startsWith('$cLower:')) {
            return entry.value;
          }
        }
      }
      return null;
    }

    // 3. Extract core identity fields
    final brand = getValue(['brand', 'make']);
    final model = getValue(['model']);
    final generation = getValue(['generation']);
    final engineModification = getValue([
      'modification (engine)',
      'modification',
      'engine modification',
      'engine version',
    ]);

    // 4. Extract year from "Start of production" (e.g. "2005 year" or "November, 2004 year" -> 2005 / 2004)
    final startOfProd = getValue([
      'start of production',
      'production start',
      'year of production',
      'model year',
    ]);
    int? year;
    if (startOfProd != null) {
      final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(startOfProd);
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1)!);
      }
    }

    // 5. Extract heading / title tags from HTML
    String? rawH1;
    final h1Match = RegExp(r'<h1\b[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true).firstMatch(cleanHtml);
    if (h1Match != null) {
      var h1Content = h1Match.group(1)!;
      // Remove nested <span> which typically contains "...specs, fuel consumption..."
      h1Content = h1Content.replaceAll(RegExp(r'<span\b[^>]*>[\s\S]*?</span>', caseSensitive: false), ' ');
      rawH1 = _cleanTitleSuffix(_stripTagsAndDecode(h1Content));
    }

    String? rawPageTitle;
    final titleTagMatch = RegExp(r'<title\b[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(cleanHtml);
    if (titleTagMatch != null) {
      rawPageTitle = _cleanTitleSuffix(_stripTagsAndDecode(titleTagMatch.group(1)!));
    }

    // If year was not found in table, attempt to parse 4-digit year from h1 or page title
    if (year == null) {
      final h1YearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawH1 ?? rawPageTitle ?? '');
      if (h1YearMatch != null) {
        year = int.tryParse(h1YearMatch.group(1)!);
      }
    }

    // Compose a clean title: e.g. "2005 Suzuki Swift III 1.5 (102 Hp)"
    String? title;
    if (brand != null && (model != null || generation != null || engineModification != null)) {
      final parts = <String>[];
      if (year != null) {
        parts.add(year.toString());
      }
      if (generation != null && generation.isNotEmpty) {
        final genLower = generation.toLowerCase();
        final brandLower = brand.toLowerCase();
        final modelLower = model?.toLowerCase() ?? '';

        if (genLower.startsWith(brandLower)) {
          parts.add(generation);
        } else if (model != null && genLower.startsWith(modelLower)) {
          parts.add('$brand $generation');
        } else if (model != null && !genLower.contains(modelLower)) {
          parts.add('$brand $model $generation');
        } else {
          parts.add('$brand $generation');
        }
      } else if (model != null) {
        parts.add('$brand $model');
      } else {
        parts.add(brand);
      }

      if (engineModification != null && engineModification.isNotEmpty) {
        parts.add(engineModification);
      }

      final composed = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (composed.isNotEmpty) {
        title = composed;
      }
    }
    title ??= rawH1 ?? rawPageTitle;

    // 6. Extract engine displacement
    final dispRaw = getValue([
      'engine displacement',
      'displacement',
      'what is the engine displacement',
    ]);
    int? displacementCc;
    double? displacementLiters;

    if (dispRaw != null) {
      // Look for cm3 / cc / cm³
      final ccMatch = RegExp(r'(\d{3,5})\s*(?:cm3|cc\b|cm³)', caseSensitive: false).firstMatch(dispRaw);
      if (ccMatch != null) {
        displacementCc = int.tryParse(ccMatch.group(1)!);
        if (displacementCc != null) {
          displacementLiters = calculateDisplacementLiters(displacementCc);
        }
      }
      // Look for direct liters (e.g. "1.5 l" or "1.5L")
      if (displacementLiters == null) {
        final literMatch = RegExp(r'(\d+(?:\.\d+)?)\s*l\b', caseSensitive: false).firstMatch(dispRaw);
        if (literMatch != null) {
          displacementLiters = double.tryParse(literMatch.group(1)!);
          if (displacementLiters != null && displacementCc == null) {
            displacementCc = (displacementLiters * 1000).round();
          }
        }
      }
    }

    // Fallback: Check engine modification for displacement if still missing
    if (displacementLiters == null && engineModification != null) {
      final modDispMatch = RegExp(r'\b([0-9]\.[0-9])\b').firstMatch(engineModification);
      if (modDispMatch != null) {
        displacementLiters = double.tryParse(modDispMatch.group(1)!);
        if (displacementLiters != null && displacementCc == null) {
          displacementCc = (displacementLiters * 1000).round();
        }
      }
    }

    // 7. Extract fuel type key ('gasoline', 'lpg', 'diesel', 'hybrid')
    final fuelRaw = getValue(['fuel type', 'type of fuel', 'fuel']);
    var fuelTypeKey = _parseFuelType(fuelRaw);
    if (fuelTypeKey == null && engineModification != null) {
      fuelTypeKey = _parseFuelType(engineModification);
    }
    if (fuelTypeKey == null && title != null) {
      fuelTypeKey = _parseFuelType(title);
    }

    // 8. Extract fuel tank capacity
    final tankRaw = getValue([
      'fuel tank capacity',
      'fuel tank volume',
      'fuel tank',
      'what is the fuel tank capacity',
    ]);
    double? fuelTankCapacityLiters;
    if (tankRaw != null) {
      final tankMatch = RegExp(r'(\d+(?:\.\d+)?)\s*l\b', caseSensitive: false).firstMatch(tankRaw);
      if (tankMatch != null) {
        fuelTankCapacityLiters = double.tryParse(tankMatch.group(1)!);
      }
    }

    // 9. Extract Power (HP and RPM)
    final powerRaw = getValue([
      'power',
      'maximum power',
      'max power',
      'max. power',
      'what is the power output',
    ]);
    int? maxHorsepower;
    int? maxPowerRpm;
    if (powerRaw != null) {
      // HP
      final hpMatch = RegExp(r'(\d+)\s*(?:hp|bhp|ps)\b', caseSensitive: false).firstMatch(powerRaw);
      if (hpMatch != null) {
        maxHorsepower = int.tryParse(hpMatch.group(1)!);
      }
      // RPM
      final rpmMatch = RegExp(r'@\s*(\d+)', caseSensitive: false).firstMatch(powerRaw);
      if (rpmMatch != null) {
        maxPowerRpm = int.tryParse(rpmMatch.group(1)!);
      } else {
        final altRpmMatch = RegExp(r'(\d{4,5})\s*rpm\b', caseSensitive: false).firstMatch(powerRaw);
        if (altRpmMatch != null) {
          maxPowerRpm = int.tryParse(altRpmMatch.group(1)!);
        }
      }
    }

    // Fallback for HP from modification (e.g. "1.5 (102 Hp)")
    if (maxHorsepower == null && engineModification != null) {
      final modHpMatch = RegExp(
        r'\((\d+)\s*(?:hp|bhp|ps)\)',
        caseSensitive: false,
      ).firstMatch(engineModification);
      if (modHpMatch != null) {
        maxHorsepower = int.tryParse(modHpMatch.group(1)!);
      }
    }

    // 10. Extract Redline RPM / Maximum engine speed
    final maxSpeedRaw = getValue([
      'maximum engine speed',
      'max engine speed',
      'engine redline',
      'redline',
    ]);
    int? redlineRpm;
    if (maxSpeedRaw != null) {
      final speedMatch = RegExp(r'(\d{4,5})').firstMatch(maxSpeedRaw);
      if (speedMatch != null) {
        redlineRpm = int.tryParse(speedMatch.group(1)!);
      }
    }
    // If Maximum engine speed is not explicitly listed, estimate maxPowerRpm + 500
    if (redlineRpm == null && maxPowerRpm != null) {
      redlineRpm = maxPowerRpm + 500;
    }

    // 11. Extract Curb Weight (base weight / first integer if range, e.g. "965-1015 kg" -> 965)
    final weightRaw = getValue([
      'kerb weight',
      'curb weight',
      'what is the kerb weight',
    ]);
    int? curbWeightKg;
    if (weightRaw != null) {
      final weightMatch = RegExp(
        r'(\d{3,5})(?:\s*-\s*\d{3,5})?\s*kg\b',
        caseSensitive: false,
      ).firstMatch(weightRaw);
      if (weightMatch != null) {
        curbWeightKg = int.tryParse(weightMatch.group(1)!);
      }
    }

    return AutoDataVehicleSpecs(
      title: title,
      brand: brand,
      model: model,
      generation: generation,
      engineModification: engineModification,
      year: year,
      displacementLiters: displacementLiters,
      displacementCc: displacementCc,
      fuelTypeKey: fuelTypeKey,
      fuelTankCapacityLiters: fuelTankCapacityLiters,
      maxHorsepower: maxHorsepower,
      maxPowerRpm: maxPowerRpm,
      redlineRpm: redlineRpm,
      curbWeightKg: curbWeightKg,
      sourceUrl: sourceUrl,
    );
  }

  /// Fetches the HTML specification page at [rawUrl] and parses it into [AutoDataVehicleSpecs].
  ///
  /// Validates [rawUrl] via [isValidAutoDataUrl], throwing a [FormatException] if invalid.
  /// Uses [httpFetcher] if provided, or Dart's [HttpClient] with a 10-second timeout and browser User-Agent.
  Future<AutoDataVehicleSpecs> fetchAndParseUrl(
    String rawUrl, {
    Future<String> Function(Uri uri)? httpFetcher,
  }) async {
    final trimmed = rawUrl.trim();
    if (!isValidAutoDataUrl(trimmed)) {
      throw FormatException('Invalid auto-data.net vehicle URL: "$rawUrl"');
    }

    final uri = Uri.parse(trimmed);
    final fetcher = httpFetcher ?? _defaultHttpFetcher ?? _defaultFetch;
    final html = await fetcher(uri);

    return parseHtml(html, sourceUrl: trimmed);
  }

  /// Static convenience helper to fetch and parse in a single invocation.
  static Future<AutoDataVehicleSpecs> fetch(
    String rawUrl, {
    Future<String> Function(Uri uri)? httpFetcher,
  }) =>
      AutoDataSpecParser(httpFetcher: httpFetcher).fetchAndParseUrl(rawUrl);

  /// Default HTTP fetch implementation using [HttpClient].
  static Future<String> _defaultFetch(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');

      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) {
        throw HttpException(
          'Failed to fetch vehicle specs: HTTP ${response.statusCode} ${response.reasonPhrase}',
          uri: uri,
        );
      }
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
      return body;
    } finally {
      client.close(force: true);
    }
  }

  /// Maps raw fuel type strings to canonical keys: 'gasoline', 'lpg', 'diesel', 'hybrid'.
  static String? _parseFuelType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final upper = raw.toUpperCase();
    if (upper.contains('LPG') ||
        upper.contains('AUTOGAS') ||
        upper.contains('BI-FUEL') ||
        upper.contains('BIFUEL') ||
        upper.contains('CNG')) {
      return 'lpg';
    }
    if (upper.contains('DIESEL')) {
      return 'diesel';
    }
    if (upper.contains('HYBRID') ||
        upper.contains('ELECTRO') ||
        upper.contains('ELECTRIC') ||
        upper.contains('PHEV') ||
        upper.contains('MHEV')) {
      return 'hybrid';
    }
    if (upper.contains('PETROL') ||
        upper.contains('GASOLINE') ||
        upper.contains('BENZIN') ||
        upper.contains('ESSENCE')) {
      return 'gasoline';
    }
    return null;
  }

  /// Removes common suffixes from page titles and heading tags.
  static String _cleanTitleSuffix(String text) {
    var s = text;
    final pipeIdx = s.indexOf('|');
    if (pipeIdx != -1) {
      s = s.substring(0, pipeIdx).trim();
    }
    s = s.replaceAll(RegExp(r'\s*-\s*Auto-Data(?:\.net)?\b', caseSensitive: false), '').trim();
    return s;
  }

  /// Strips HTML tags, converts line breaks to spaces, and decodes HTML entities.
  static String _stripTagsAndDecode(String text) {
    var t = text.replaceAll(RegExp(r'<\s*br\s*/?>|<\s*/p\s*>', caseSensitive: false), ' ');
    // Retain numerical values in superscripts (e.g. cm<sup>3</sup> -> cm3)
    t = t.replaceAllMapped(
      RegExp(r'<sup\b[^>]*>(.*?)</sup>', caseSensitive: false),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = _decodeHtmlEntities(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// Decodes common HTML entities into their character equivalents.
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&ndash;', '-')
        .replaceAll('&mdash;', '-')
        .replaceAll('&minus;', '-')
        .replaceAll('&bull;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&sup3;', '3')
        .replaceAll('&sup2;', '2')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
          final code = int.tryParse(match.group(1)!);
          return code != null ? String.fromCharCode(code) : match.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
          final code = int.tryParse(match.group(1)!, radix: 16);
          return code != null ? String.fromCharCode(code) : match.group(0)!;
        });
  }
}
