class NotificationOwnership {
  const NotificationOwnership._();

  static bool matchesAuthenticatedUser({
    required Object? recipientUserId,
    required String? authenticatedUserId,
  }) {
    if (authenticatedUserId == null || authenticatedUserId.trim().isEmpty) {
      return false;
    }
    if (recipientUserId is! String || recipientUserId.trim().isEmpty) {
      return false;
    }
    return recipientUserId.trim() == authenticatedUserId;
  }

  static Map<String, dynamic> localTapPayload({
    required String recipientUserId,
    required String type,
    required String title,
    required String body,
    required String sourceEventId,
    required Map<String, dynamic> data,
  }) => {
    'userId': recipientUserId,
    'type': type,
    'title': title,
    'body': body,
    'sourceEventId': sourceEventId,
    'data': data,
  };
}
