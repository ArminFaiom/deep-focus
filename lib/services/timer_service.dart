import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static const _TAG = '[TimerSvc]';
  static const _completionNotificationId = 2;
  static const _progressNotificationId = 1;

  Timer? _ticker;
  int _remainingSeconds = 0;
  int _durationSeconds = 0;
  String _currentMode = 'focus';

  // Callbacks
  Function(int remaining)? onTick;
  Function()? onComplete;

  Future<void> initialize() async {
    try {
      // Initialize timezone data for scheduled notifications
      tz.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _notifications.initialize(initSettings);

      final plugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        // Timer progress channel (low priority, no sound)
        await plugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'timer_channel', 'Timer',
            description: 'Focus timer notifications',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
        // Completion channel — high priority with sound
        await plugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'session_complete', 'Session Complete',
            description: 'Session completion notifications',
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
            sound: RawResourceAndroidNotificationSound('chime'),
          ),
        );
      }

      await _requestNotificationPermission();

      // Check if the app was launched by a notification tap
      final launchDetails = await _notifications.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        debugPrint('$_TAG app launched from notification');
      }

      debugPrint('$_TAG initialized with sound channels + scheduled notifications');
    } catch (e, st) {
      debugPrint('$_TAG init failed: $e\n$st');
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final plugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (plugin != null) {
        final granted = await plugin.requestNotificationsPermission();
        debugPrint('$_TAG notification permission granted: $granted');
      }
    } catch (e) {
      debugPrint('$_TAG permission request error: $e');
    }
  }

  Future<void> startTimer({
    required int durationSeconds,
    required String mode,
  }) async {
    debugPrint('$_TAG startTimer: $mode for ${durationSeconds}s');
    _remainingSeconds = durationSeconds;
    _durationSeconds = durationSeconds;
    _currentMode = mode;

    final prefs = await SharedPreferences.getInstance();
    final startTime = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('timer_start', startTime);
    await prefs.setInt('timer_duration', durationSeconds);
    await prefs.setString('timer_mode', mode);
    await prefs.setBool('timer_running', true);
    await prefs.setBool('timer_paused', false);

    // Cancel any previously scheduled completion notification
    await _notifications.cancel(_completionNotificationId);

    // Schedule the completion notification via AlarmManager
    // This fires even if the app is killed/backgrounded
    await _scheduleCompletionNotification(mode, durationSeconds);

    _startTicker();
    _showProgressNotification(mode, durationSeconds);
  }

  /// Schedule a local notification at the exact time the timer expires.
  /// Uses Android's AlarmManager via zonedSchedule — fires even when app is dead.
  Future<void> _scheduleCompletionNotification(String mode, int durationSeconds) async {
    try {
      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(seconds: durationSeconds));
      final modeLabel = mode == 'focus' ? 'Focus' : mode == 'break_' ? 'Break' : 'Long Break';

      await _notifications.zonedSchedule(
        _completionNotificationId,
        'Deep Focus',
        '$modeLabel session complete! Take a break!',
        scheduledTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'session_complete', 'Session Complete',
            channelDescription: 'Session completion notifications',
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
            ongoing: false,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 200, 150, 300, 200, 600]),
            playSound: true,
            sound: RawResourceAndroidNotificationSound('chime'),
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint('$_TAG scheduled completion notification for ${scheduledTime.toIso8601String()}');
    } catch (e) {
      debugPrint('$_TAG schedule completion failed: $e');
    }
  }

  Future<void> pauseTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isPaused = prefs.getBool('timer_paused') ?? false;

    if (!isPaused) {
      _ticker?.cancel();
      // Cancel the scheduled completion notification — we'll reschedule on resume
      await _notifications.cancel(_completionNotificationId);
      await prefs.setInt('timer_remaining', _remainingSeconds);
      await prefs.setBool('timer_paused', true);
      await prefs.setInt('timer_pause_time', DateTime.now().millisecondsSinceEpoch);
      await _notifications.cancel(_progressNotificationId);
    } else {
      final pauseTime = prefs.getInt('timer_pause_time') ?? DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = DateTime.now().millisecondsSinceEpoch - pauseTime;
      final oldStart = prefs.getInt('timer_start') ?? DateTime.now().millisecondsSinceEpoch;

      await prefs.setInt('timer_start', oldStart + pauseDuration);
      await prefs.setBool('timer_paused', false);
      await prefs.remove('timer_pause_time');

      // Reschedule completion notification for the remaining time
      await _scheduleCompletionNotification(_currentMode, _remainingSeconds);

      _startTicker();
      _showProgressNotification(_currentMode, _remainingSeconds);
    }
  }

  Future<void> stopTimer() async {
    debugPrint('$_TAG stopTimer');
    _ticker?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('timer_start');
    await prefs.remove('timer_duration');
    await prefs.remove('timer_mode');
    await prefs.remove('timer_remaining');
    await prefs.remove('timer_pause_time');
    await prefs.setBool('timer_running', false);
    await prefs.setBool('timer_paused', false);
    await _notifications.cancel(_progressNotificationId);
    await _notifications.cancel(_completionNotificationId);
  }

  void _startTicker() {
    _ticker?.cancel();
    debugPrint('$_TAG ticker started, _remainingSeconds=$_remainingSeconds');
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
      }
      onTick?.call(_remainingSeconds);
      if (_remainingSeconds <= 0) {
        _ticker?.cancel();
        debugPrint('$_TAG ticker hit 0 — firing onComplete');
        // Cancel the scheduled notification since we're completing in-app
        _notifications.cancel(_completionNotificationId);
        onComplete?.call();
      }
    });
  }

  Future<Map<String, dynamic>?> getTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    final running = prefs.getBool('timer_running') ?? false;
    if (!running) return null;

    final startTime = prefs.getInt('timer_start') ?? 0;
    final duration = prefs.getInt('timer_duration') ?? 0;
    final paused = prefs.getBool('timer_paused') ?? false;
    final mode = prefs.getString('timer_mode') ?? 'focus';

    int remaining;
    if (paused) {
      remaining = prefs.getInt('timer_remaining') ?? duration;
    } else {
      final elapsed = ((DateTime.now().millisecondsSinceEpoch - startTime) / 1000).round();
      remaining = (duration - elapsed).clamp(0, duration);
    }

    return {
      'running': running,
      'paused': paused,
      'mode': mode,
      'duration': duration,
      'remaining': remaining,
    };
  }

  Future<void> syncStateOnResume() async {
    final state = await getTimerState();
    if (state == null) return;

    _currentMode = state['mode'] as String;
    _durationSeconds = state['duration'] as int;
    _remainingSeconds = state['remaining'] as int;

    if (_remainingSeconds <= 0 && state['running'] == true && state['paused'] == false) {
      _ticker?.cancel();
      // Timer expired while app was backgrounded — fire completion now
      // The scheduled notification already fired, but we still need to
      // update UI state, save the session, and auto-start next phase
      onComplete?.call();
      return;
    }

    if (state['running'] == true && state['paused'] == false) {
      _startTicker();
    }
  }

  Future<void> _showProgressNotification(String mode, int totalSeconds) async {
    try {
      final modeLabel = mode == 'focus' ? 'Focus' : mode == 'break_' ? 'Break' : 'Long Break';
      await _notifications.show(
        _progressNotificationId,
        'Deep Focus',
        '$modeLabel timer running…',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_channel', 'Timer',
            channelDescription: 'Focus timer notifications',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('$_TAG progress notif failed: $e');
    }
  }

  Future<void> showCompletedNotification() async {
    try {
      final vibrationPattern = Int64List.fromList([0, 200, 150, 300, 200, 600]);

      await _notifications.show(
        _completionNotificationId,
        'Deep Focus',
        '$_currentMode session complete! Take a break!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            'session_complete', 'Session Complete',
            channelDescription: 'Session completion notifications',
            importance: Importance.high,
            priority: Priority.high,
            autoCancel: true,
            ongoing: false,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            vibrationPattern: vibrationPattern,
            playSound: true,
            sound: RawResourceAndroidNotificationSound('chime'),
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
          ),
        ),
      );

      debugPrint('$_TAG completion notification sent with sound');
    } catch (e) {
      debugPrint('$_TAG completion notif failed: $e');
    }
  }
}
