import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:redrive/services/garage/auto_data_spec_parser.dart';

void main() {
  group('AutoDataSpecParser URL Validation', () {
    test('accepts valid HTTPS and HTTP auto-data.net URLs', () {
      expect(
        AutoDataSpecParser.isValidAutoDataUrl(
          'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
        ),
        isTrue,
      );
      expect(
        AutoDataSpecParser.isValidAutoDataUrl(
          'http://auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
        ),
        isTrue,
      );
      expect(
        AutoDataSpecParser.isValidAutoDataUrl(
          'https://m.auto-data.net/en/car-profile-1234',
        ),
        isTrue,
      );
    });

    test('trims whitespace around valid URLs', () {
      expect(
        AutoDataSpecParser.isValidAutoDataUrl(
          '   https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357 \n  ',
        ),
        isTrue,
      );
    });

    test('rejects non-auto-data domains and subdomains of attacker domains', () {
      expect(
        AutoDataSpecParser.isValidAutoDataUrl('https://example.com/car'),
        isFalse,
      );
      expect(
        AutoDataSpecParser.isValidAutoDataUrl('https://auto-data.net.attacker.com/en/car'),
        isFalse,
      );
      expect(
        AutoDataSpecParser.isValidAutoDataUrl('https://not-auto-data.net/car'),
        isFalse,
      );
    });

    test('rejects non-HTTP schemes and malformed strings', () {
      expect(
        AutoDataSpecParser.isValidAutoDataUrl('ftp://www.auto-data.net/car'),
        isFalse,
      );
      expect(
        AutoDataSpecParser.isValidAutoDataUrl('www.auto-data.net/car'), // Missing scheme
        isFalse,
      );
      expect(AutoDataSpecParser.isValidAutoDataUrl(''), isFalse);
      expect(AutoDataSpecParser.isValidAutoDataUrl('   '), isFalse);
      expect(AutoDataSpecParser.isValidAutoDataUrl('random string'), isFalse);
    });
  });

  group('AutoDataSpecParser Displacement Calculation', () {
    test('rounds cm3 within 35cc of a 0.1L step to 1 decimal place', () {
      expect(AutoDataSpecParser.calculateDisplacementLiters(1490), equals(1.5));
      expect(AutoDataSpecParser.calculateDisplacementLiters(1328), equals(1.3));
      expect(AutoDataSpecParser.calculateDisplacementLiters(1598), equals(1.6));
      expect(AutoDataSpecParser.calculateDisplacementLiters(1968), equals(2.0));
      expect(AutoDataSpecParser.calculateDisplacementLiters(1781), equals(1.8));
      expect(AutoDataSpecParser.calculateDisplacementLiters(999), equals(1.0));
    });

    test('rounds cm3 outside 35cc of a 0.1L step to 2 decimal places', () {
      expect(AutoDataSpecParser.calculateDisplacementLiters(1350), equals(1.35));
      expect(AutoDataSpecParser.calculateDisplacementLiters(1242), equals(1.24));
    });
  });

  group('AutoDataSpecParser Suzuki Swift III 1.5 M15A HTML Fixture', () {
    const suzukiSwiftHtml = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>2005 Suzuki Swift III 1.5 (102 Hp) | Technical specs, data, fuel consumption, Dimensions</title>
  <script type="text/javascript">
    var tracking = "ignore me";
  </script>
  <style>
    body { font-family: sans-serif; }
  </style>
</head>
<body>
  <h1>
    <img src="/img/logos/Suzuki.png" alt="Suzuki" />
    Suzuki Swift III 1.5 (102 Hp)
    <span>2005, 2006, 2007: specs, Fuel consumption</span>
  </h1>
  <table class="cardetails">
    <tbody>
      <tr>
        <th scope="row"><strong>Brand</strong></th>
        <td><a href="/en/suzuki">Suzuki</a></td>
      </tr>
      <tr>
        <th scope="row">Model</th>
        <td>Swift</td>
      </tr>
      <tr>
        <th scope="row">Generation</th>
        <td>Swift III</td>
      </tr>
      <tr>
        <th scope="row">Modification (Engine)</th>
        <td>1.5 (102 Hp)</td>
      </tr>
      <tr>
        <th scope="row">Start of production</th>
        <td>2005 year</td>
      </tr>
      <tr>
        <th scope="row">Powertrain Architecture</th>
        <td>Internal Combustion engine</td>
      </tr>
      <tr>
        <th scope="row">Fuel Type</th>
        <td>Petrol (Gasoline)</td>
      </tr>
      <tr>
        <th scope="row">Power</th>
        <td>102&nbsp;Hp @ 6000&nbsp;rpm.</td>
      </tr>
      <tr>
        <th scope="row">Engine displacement</th>
        <td>1490 cm<sup>3</sup> &nbsp; | &nbsp; 90.93 cu. in.</td>
      </tr>
      <tr>
        <th scope="row">Fuel tank capacity</th>
        <td>45 l</td>
      </tr>
      <tr>
        <th scope="row">Kerb Weight</th>
        <td>1015 kg</td>
      </tr>
    </tbody>
  </table>
</body>
</html>
''';

    test('accurately parses all specifications from table markup', () {
      final specs = AutoDataSpecParser.parseHtml(
        suzukiSwiftHtml,
        sourceUrl: 'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
      );

      expect(specs.hasAnyParsedSpec, isTrue);
      expect(specs.brand, equals('Suzuki'));
      expect(specs.model, equals('Swift'));
      expect(specs.generation, equals('Swift III'));
      expect(specs.engineModification, equals('1.5 (102 Hp)'));
      expect(specs.year, equals(2005));
      expect(specs.title, equals('2005 Suzuki Swift III 1.5 (102 Hp)'));
      expect(specs.fuelTypeKey, equals('gasoline'));
      expect(specs.displacementCc, equals(1490));
      expect(specs.displacementLiters, equals(1.5));
      expect(specs.fuelTankCapacityLiters, equals(45.0));
      expect(specs.maxHorsepower, equals(102));
      expect(specs.maxPowerRpm, equals(6000));
      // Redline estimated as maxPowerRpm + 500 since "Maximum engine speed" is omitted
      expect(specs.redlineRpm, equals(6500));
      expect(specs.curbWeightKg, equals(1015));
      expect(
        specs.sourceUrl,
        equals('https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357'),
      );
    });
  });

  group('AutoDataSpecParser LPG Bi-Fuel HTML Fixture', () {
    const lpgBiFuelHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>2020 Dacia Duster II 1.0 TCe (100 Hp) ECO-G (LPG) - Auto-Data.net</title>
</head>
<body>
  <h1>Dacia Duster II 1.0 TCe (100 Hp) ECO-G (LPG)</h1>
  <table>
    <tr><th>Brand:</th><td>Dacia</td></tr>
    <tr><th>Model:</th><td>Duster</td></tr>
    <tr><th>Generation:</th><td>Duster II</td></tr>
    <tr><th>Modification (Engine):</th><td>1.0 TCe (100 Hp) ECO-G (LPG)</td></tr>
    <tr><th>Start of production:</th><td>January, 2020</td></tr>
    <tr><th>Fuel Type:</th><td>Petrol / LPG (Bi-fuel)</td></tr>
    <tr><th>Power:</th><td>100 Hp @ 5000 rpm</td></tr>
    <tr><th>Maximum engine speed:</th><td>6000 rpm</td></tr>
    <tr><th>Engine displacement:</th><td>999 cm3</td></tr>
    <tr><th>Fuel tank capacity:</th><td>50 l</td></tr>
    <tr><th>Kerb Weight:</th><td>1259&ndash;1312 kg</td></tr>
  </table>
</body>
</html>
''';

    test('extracts LPG fuel type, explicit redline RPM, and base weight from range', () {
      final specs = AutoDataSpecParser.parseHtml(
        lpgBiFuelHtml,
        sourceUrl: 'https://www.auto-data.net/en/dacia-duster-ii-1.0-tce-100hp-ecog-38291',
      );

      expect(specs.hasAnyParsedSpec, isTrue);
      expect(specs.brand, equals('Dacia'));
      expect(specs.model, equals('Duster'));
      expect(specs.generation, equals('Duster II'));
      expect(specs.engineModification, equals('1.0 TCe (100 Hp) ECO-G (LPG)'));
      expect(specs.year, equals(2020));
      expect(specs.title, equals('2020 Dacia Duster II 1.0 TCe (100 Hp) ECO-G (LPG)'));
      expect(specs.fuelTypeKey, equals('lpg'));
      expect(specs.displacementCc, equals(999));
      expect(specs.displacementLiters, equals(1.0));
      expect(specs.fuelTankCapacityLiters, equals(50.0));
      expect(specs.maxHorsepower, equals(100));
      expect(specs.maxPowerRpm, equals(5000));
      // Explicit Maximum engine speed table row overrides estimate
      expect(specs.redlineRpm, equals(6000));
      // First integer of range "1259-1312 kg" taken as base curb weight
      expect(specs.curbWeightKg, equals(1259));
    });
  });

  group('AutoDataSpecParser Diesel HTML Fixture', () {
    const dieselGolfHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>2012 Volkswagen Golf VII 2.0 TDI (150 Hp) | Technical Specs</title>
</head>
<body>
  <h1>Volkswagen Golf VII 2.0 TDI (150 Hp)</h1>
  <table>
    <tr><th>Brand</th><td>Volkswagen</td></tr>
    <tr><th>Model</th><td>Golf</td></tr>
    <tr><th>Generation</th><td>Golf VII</td></tr>
    <tr><th>Modification (Engine)</th><td>2.0 TDI (150 Hp)</td></tr>
    <tr><th>Start of production</th><td>August, 2012 year</td></tr>
    <tr><th>Fuel Type</th><td>Diesel</td></tr>
    <tr><th>Power</th><td>150 Hp @ 3500-4000 rpm</td></tr>
    <tr><th>Engine displacement</th><td>1968 cm3</td></tr>
    <tr><th>Fuel tank capacity</th><td>50 l</td></tr>
    <tr><th>Kerb Weight</th><td>1354 kg</td></tr>
  </table>
</body>
</html>
''';

    test('extracts diesel fuel type, RPM from range, and rounded 2.0L displacement', () {
      final specs = AutoDataSpecParser.parseHtml(dieselGolfHtml);

      expect(specs.brand, equals('Volkswagen'));
      expect(specs.model, equals('Golf'));
      expect(specs.generation, equals('Golf VII'));
      expect(specs.engineModification, equals('2.0 TDI (150 Hp)'));
      expect(specs.year, equals(2012));
      expect(specs.title, equals('2012 Volkswagen Golf VII 2.0 TDI (150 Hp)'));
      expect(specs.fuelTypeKey, equals('diesel'));
      expect(specs.displacementCc, equals(1968));
      expect(specs.displacementLiters, equals(2.0));
      expect(specs.maxHorsepower, equals(150));
      expect(specs.maxPowerRpm, equals(3500));
      expect(specs.redlineRpm, equals(4000)); // 3500 + 500
      expect(specs.curbWeightKg, equals(1354));
    });
  });

  group('AutoDataSpecParser Modern Div-based Template Fixture', () {
    const modernDivHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>2008 Suzuki Swift III 1.3 (92 Hp) | Technical specs</title>
</head>
<body>
  <h1>Suzuki Swift III 1.3 (92 Hp)</h1>
  <div class="cardetails">
    <div class="row"><div class="par">Brand</div><div class="val">Suzuki</div></div>
    <div class="row"><div class="par">Model</div><div class="val">Swift</div></div>
    <div class="row"><div class="par">Generation</div><div class="val">Swift III</div></div>
    <div class="row"><div class="par">Modification (Engine)</div><div class="val">1.3 (92 Hp)</div></div>
    <div class="row"><div class="par">Start of production</div><div class="val">2005 year</div></div>
    <div class="row"><div class="par">Fuel Type</div><div class="val">Gasoline</div></div>
    <div class="row"><div class="par">Power</div><div class="val">92 Hp @ 5800 rpm</div></div>
    <div class="row"><div class="par">Engine displacement</div><div class="val">1328 cm3</div></div>
    <div class="row"><div class="par">Fuel tank capacity</div><div class="val">45 l</div></div>
    <div class="row"><div class="par">Kerb Weight</div><div class="val">965-1005 kg</div></div>
  </div>
</body>
</html>
''';

    test('extracts specs accurately from modern auto-data div.par / div.val layout', () {
      final specs = AutoDataSpecParser.parseHtml(modernDivHtml);

      expect(specs.brand, equals('Suzuki'));
      expect(specs.model, equals('Swift'));
      expect(specs.generation, equals('Swift III'));
      expect(specs.engineModification, equals('1.3 (92 Hp)'));
      expect(specs.year, equals(2005));
      expect(specs.title, equals('2005 Suzuki Swift III 1.3 (92 Hp)'));
      expect(specs.fuelTypeKey, equals('gasoline'));
      expect(specs.displacementCc, equals(1328));
      expect(specs.displacementLiters, equals(1.3)); // 1328cc -> 1.3L
      expect(specs.maxHorsepower, equals(92));
      expect(specs.maxPowerRpm, equals(5800));
      expect(specs.redlineRpm, equals(6300));
      expect(specs.curbWeightKg, equals(965));
    });
  });

  group('AutoDataSpecParser Fallbacks & Edge Cases', () {
    test('falls back to h1 or title when table rows are minimal', () {
      const minimalHtml = '''
<!DOCTYPE html>
<html>
<head>
  <title>2018 Toyota Yaris 1.5 Hybrid (100 Hp) - Auto-Data.net</title>
</head>
<body>
  <h1>2018 Toyota Yaris 1.5 Hybrid (100 Hp)</h1>
  <table>
    <tr><th>Fuel Type</th><td>Hybrid (Petrol/Electric)</td></tr>
    <tr><th>Fuel tank capacity</th><td>36 l</td></tr>
  </table>
</body>
</html>
''';

      final specs = AutoDataSpecParser.parseHtml(minimalHtml);

      expect(specs.title, equals('2018 Toyota Yaris 1.5 Hybrid (100 Hp)'));
      expect(specs.year, equals(2018));
      expect(specs.fuelTypeKey, equals('hybrid'));
      expect(specs.fuelTankCapacityLiters, equals(36.0));
      expect(specs.hasAnyParsedSpec, isTrue);
    });

    test('returns hasAnyParsedSpec as false when HTML contains no vehicle data', () {
      const emptyHtml = '<html><body><p>404 Page Not Found</p></body></html>';
      final specs = AutoDataSpecParser.parseHtml(emptyHtml);

      expect(specs.hasAnyParsedSpec, isFalse);
      expect(specs.brand, isNull);
      expect(specs.displacementLiters, isNull);
    });
  });

  group('AutoDataSpecParser HTTP Fetching & Mocking', () {
    const sampleHtml = '''
<html>
<body>
  <h1>Suzuki Swift III 1.5 (102 Hp)</h1>
  <table>
    <tr><th>Brand</th><td>Suzuki</td></tr>
    <tr><th>Model</th><td>Swift</td></tr>
    <tr><th>Generation</th><td>Swift III</td></tr>
    <tr><th>Modification (Engine)</th><td>1.5 (102 Hp)</td></tr>
    <tr><th>Engine displacement</th><td>1490 cm3</td></tr>
    <tr><th>Fuel Type</th><td>Petrol</td></tr>
  </table>
</body>
</html>
''';

    test('fetches and parses with custom httpFetcher injected in method call', () async {
      Uri? capturedUri;
      Future<String> mockFetcher(Uri uri) async {
        capturedUri = uri;
        return sampleHtml;
      }

      final parser = const AutoDataSpecParser();
      final specs = await parser.fetchAndParseUrl(
        'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
        httpFetcher: mockFetcher,
      );

      expect(capturedUri, isNotNull);
      expect(capturedUri!.host, equals('www.auto-data.net'));
      expect(
        capturedUri!.path,
        equals('/en/suzuki-swift-iii-1.5-102hp-4357'),
      );
      expect(specs.brand, equals('Suzuki'));
      expect(specs.displacementLiters, equals(1.5));
      expect(specs.fuelTypeKey, equals('gasoline'));
      expect(
        specs.sourceUrl,
        equals('https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357'),
      );
    });

    test('fetches and parses with constructor injected defaultHttpFetcher', () async {
      final parser = AutoDataSpecParser(
        httpFetcher: (uri) async => sampleHtml,
      );

      final specs = await parser.fetchAndParseUrl(
        'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
      );

      expect(specs.brand, equals('Suzuki'));
      expect(specs.displacementLiters, equals(1.5));
    });

    test('static AutoDataSpecParser.fetch helper forwards to fetchAndParseUrl', () async {
      final specs = await AutoDataSpecParser.fetch(
        'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
        httpFetcher: (uri) async => sampleHtml,
      );

      expect(specs.brand, equals('Suzuki'));
      expect(specs.displacementLiters, equals(1.5));
    });

    test('throws FormatException on invalid URL without invoking fetcher', () async {
      var fetcherCalled = false;
      final parser = AutoDataSpecParser(
        httpFetcher: (uri) async {
          fetcherCalled = true;
          return sampleHtml;
        },
      );

      expect(
        () => parser.fetchAndParseUrl('https://evil-site.com/car'),
        throwsA(isA<FormatException>()),
      );
      expect(fetcherCalled, isFalse);
    });

    test('propagates HTTP or network exception thrown by fetcher', () async {
      final parser = AutoDataSpecParser(
        httpFetcher: (uri) async => throw const HttpException('404 Not Found'),
      );

      expect(
        () => parser.fetchAndParseUrl('https://www.auto-data.net/en/car-not-found'),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('AutoDataVehicleSpecs JSON Serialization & Equality', () {
    test('toJson and fromJson preserve all fields', () {
      const original = AutoDataVehicleSpecs(
        title: '2005 Suzuki Swift III 1.5 (102 Hp)',
        brand: 'Suzuki',
        model: 'Swift',
        generation: 'Swift III',
        engineModification: '1.5 (102 Hp)',
        year: 2005,
        displacementLiters: 1.5,
        displacementCc: 1490,
        fuelTypeKey: 'gasoline',
        fuelTankCapacityLiters: 45.0,
        maxHorsepower: 102,
        maxPowerRpm: 6000,
        redlineRpm: 6500,
        curbWeightKg: 1015,
        sourceUrl: 'https://www.auto-data.net/en/suzuki-swift-iii-1.5-102hp-4357',
      );

      final json = original.toJson();
      final restored = AutoDataVehicleSpecs.fromJson(json);

      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
      expect(restored.title, equals('2005 Suzuki Swift III 1.5 (102 Hp)'));
      expect(restored.hasAnyParsedSpec, isTrue);
    });

    test('toString includes formatted vehicle specs', () {
      const specs = AutoDataVehicleSpecs(
        title: 'Suzuki Swift 1.5',
        brand: 'Suzuki',
        model: 'Swift',
        displacementLiters: 1.5,
        displacementCc: 1490,
        fuelTypeKey: 'gasoline',
        fuelTankCapacityLiters: 45.0,
        maxHorsepower: 102,
        maxPowerRpm: 6000,
        redlineRpm: 6500,
        curbWeightKg: 1015,
      );

      final str = specs.toString();
      expect(str, contains('Suzuki Swift 1.5'));
      expect(str, contains('1.5L (1490 cc)'));
      expect(str, contains('102hp @ 6000rpm'));
    });
  });
}
