import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_app/constants/app_constants.dart';

void main() {
  group('Thermostat Constants & Command Alignment Tests', () {
    test('AppConstants homeTemperature matches native Siri heating on target (25.0°C)', () {
      expect(AppConstants.homeTemperature, equals(25.0));
    });

    test('Temperature bounds are valid', () {
      expect(AppConstants.minTemperature, equals(10.0));
      expect(AppConstants.maxTemperature, equals(30.0));
      expect(AppConstants.homeTemperature >= AppConstants.minTemperature, isTrue);
      expect(AppConstants.homeTemperature <= AppConstants.maxTemperature, isTrue);
    });
  });
}
