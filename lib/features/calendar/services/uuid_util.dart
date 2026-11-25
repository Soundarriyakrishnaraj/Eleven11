// lib/features/calendar/services/uuid_util.dart

import 'dart:math';

/// Generates RFC 4122 compliant version 4 UUIDs using cryptographically
/// secure random numbers where available.
class UuidUtil {
  static final Random _random = Random.secure();

  static String generateV4() {
    final values = List<int>.generate(16, (i) => _random.nextInt(256));

    // Set version to 4 -> 0100xxxx
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to IETF variant -> 10xxxxxx
    values[8] = (values[8] & 0x3f) | 0x80;

    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  static bool isValidUuid(String? value) {
    if (value == null) return false;
    final regex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return regex.hasMatch(value);
  }
}
