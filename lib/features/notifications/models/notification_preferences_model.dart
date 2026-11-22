class NotificationPreferences {
  final bool alarmNotificationsEnabled;
  final bool taskRemindersEnabled;
  final bool goalRemindersEnabled;
  final bool motivationEnabled;
  final bool announcementsEnabled;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final String motivationTime;
  final String taskReminderTime;
  final bool pushEnabled;

  const NotificationPreferences({
    this.alarmNotificationsEnabled = true,
    this.taskRemindersEnabled = true,
    this.goalRemindersEnabled = true,
    this.motivationEnabled = true,
    this.announcementsEnabled = true,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.motivationTime = '08:00',
    this.taskReminderTime = '09:00',
    this.pushEnabled = true,
  });

  NotificationPreferences copyWith({
    bool? alarmNotificationsEnabled,
    bool? taskRemindersEnabled,
    bool? goalRemindersEnabled,
    bool? motivationEnabled,
    bool? announcementsEnabled,
    bool? soundEnabled,
    bool? vibrationEnabled,
    String? motivationTime,
    String? taskReminderTime,
    bool? pushEnabled,
  }) {
    return NotificationPreferences(
      alarmNotificationsEnabled:
          alarmNotificationsEnabled ?? this.alarmNotificationsEnabled,
      taskRemindersEnabled: taskRemindersEnabled ?? this.taskRemindersEnabled,
      goalRemindersEnabled: goalRemindersEnabled ?? this.goalRemindersEnabled,
      motivationEnabled: motivationEnabled ?? this.motivationEnabled,
      announcementsEnabled: announcementsEnabled ?? this.announcementsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      motivationTime: motivationTime ?? this.motivationTime,
      taskReminderTime: taskReminderTime ?? this.taskReminderTime,
      pushEnabled: pushEnabled ?? this.pushEnabled,
    );
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      alarmNotificationsEnabled: json['alarm_notifications_enabled'] != false,
      taskRemindersEnabled: json['task_reminders_enabled'] != false,
      goalRemindersEnabled: json['goal_reminders_enabled'] != false,
      motivationEnabled: json['motivation_enabled'] != false,
      announcementsEnabled: json['announcements_enabled'] != false,
      soundEnabled: json['sound_enabled'] != false,
      vibrationEnabled: json['vibration_enabled'] != false,
      motivationTime: json['motivation_time']?.toString() ?? '08:00',
      taskReminderTime: json['task_reminder_time']?.toString() ?? '09:00',
      pushEnabled: json['push_enabled'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'alarm_notifications_enabled': alarmNotificationsEnabled,
      'task_reminders_enabled': taskRemindersEnabled,
      'goal_reminders_enabled': goalRemindersEnabled,
      'motivation_enabled': motivationEnabled,
      'announcements_enabled': announcementsEnabled,
      'sound_enabled': soundEnabled,
      'vibration_enabled': vibrationEnabled,
      'motivation_time': motivationTime,
      'task_reminder_time': taskReminderTime,
      'push_enabled': pushEnabled,
    };
  }
}
