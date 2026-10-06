import 'package:flutter_test/flutter_test.dart';
import 'package:pitik_app/services/auth_service.dart';

void main() {
  group('AuthService.formatPhoneNumber', () {
    test('formats 08xxx to +62xxx', () {
      expect(AuthService.formatPhoneNumber('08123456789'), '+628123456789');
    });

    test('formats 62xxx to +62xxx', () {
      expect(AuthService.formatPhoneNumber('628123456789'), '+628123456789');
    });

    test('keeps +62xxx unchanged', () {
      expect(AuthService.formatPhoneNumber('+628123456789'), '+628123456789');
    });

    test('formats number with spaces and dashes', () {
      expect(AuthService.formatPhoneNumber('0812-3456-7890'), '+6281234567890');
    });

    test('formats number with leading zero trimmed', () {
      expect(AuthService.formatPhoneNumber('0 812 3456 7890'), '+6281234567890');
    });

    test('handles 10-digit number starting with 8', () {
      expect(AuthService.formatPhoneNumber('81234567890'), '+6281234567890');
    });

    test('handles number with leading zero and 62 prefix', () {
      expect(AuthService.formatPhoneNumber('+628123456789'), '+628123456789');
    });
  });
}
