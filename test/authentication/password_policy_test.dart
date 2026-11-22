import 'package:eleven11/features/authentication/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PasswordPolicy', () {
    test('accepts a strong password', () {
      expect(PasswordPolicy.validate('Eleven11!Secure'), isNull);
    });

    test('rejects short passwords and missing character classes', () {
      expect(PasswordPolicy.validate('Ab1!'), isNotNull);
      expect(PasswordPolicy.validate('alllowercase1!'), isNotNull);
      expect(PasswordPolicy.validate('ALLUPPERCASE1!'), isNotNull);
      expect(PasswordPolicy.validate('NoNumber!'), isNotNull);
      expect(PasswordPolicy.validate('NoSymbol123'), isNotNull);
    });
  });
}
