import 'dart:async';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();
  static const _TAG = '[TimerSvc]';

  // Separate IDs so progress / in-app completion / AlarmManager don't cancel each other
  static const _progressNotificationId = 1;
  static const _completionNotificationId = 2;   // in-app completion (show())
  static const _scheduledCompletionId = 3;       // scheduled via AlarmManager (background)

  // Fresh channel ID — Android freezes sound settings after first create
  static const _completionChannelId = 'session_complete_v4';

  Timer? _ticker;
  int _remainingSeconds = 0;
  int _durationSeconds = 0;
  String _currentMode = 'focus';
  bool _initialized = false;

  // Callbacks
  Function(int remaining)? onTick;
  Function()? onComplete;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      // Keep local as system-local if available; fall back to UTC (relative offsets still work)
      try {
        final name = DateTime.now().timeZoneName;
        // timezone package needs IANA names; relative scheduling still works with UTC
        debugPrint('$_TAG device tz name=$name offset=${DateTime.now().timeZoneOffset}');
      } catch (_) {}

      // Audio: play even in silent-ish scenarios while app is alive
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
      // Low latency path for short chime
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);

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
        await plugin.createNotificationChannel(
          const AndroidNotificationChannel(
            'timer_channel', 'Timer',
            description: 'Focus timer notifications',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ),
        );
        await plugin.createNotificationChannel(
          AndroidNotificationChannel(
            _completionChannelId, 'Session Complete',
            description: 'Session completion notifications with chime',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            sound: const RawResourceAndroidNotificationSound('chime'),
            // Critical so heads-up + sound are more likely while app is open
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );

        // Exact alarms (needed for zonedSchedule reliability on Android 12+)
        try {
          final canExact = await plugin.canScheduleExactNotifications();
          debugPrint('$_TAG canScheduleExactNotifications=$canExact');
          if (canExact == false) {
            await plugin.requestExactAlarmsPermission();
          }
        } catch (e) {
          debugPrint('$_TAG exact alarm permission: $e');
        }
      }

      await _requestNotificationPermission();
      _initialized = true;
      debugPrint('$_TAG initialized OK (channel=$_completionChannelId)');
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

  /// Play the completion chime from app assets.
  /// This is the reliable path when the app process is alive (foreground / backgrounded but not killed).
  /// Android often suppresses notification sounds while the app is in the foreground —
  /// so we must NOT rely on notification sound alone.
  Future<void> playCompletionSound() async {
    try {
      // Stop any previous play so rapid completions don't stack
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/chime.ogg'));
      // Also fire a short haptic + system alert as extra feedback
      try {
        await HapticFeedback.heavyImpact();
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      debugPrint('$_TAG playCompletionSound OK');
    } catch (e) {
      debugPrint('$_TAG playCompletionSound failed: $e — trying notification-only fallback');
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

    // Ticker first — never block timer start on notification scheduling
    _startTicker();
    _showProgressNotification(mode, durationSeconds);

    // Schedule background completion alarm (ID 3).
    // Do NOT cancel ID 2 (in-app completion) — previous phase may still be showing.
    // zonedSchedule on the same ID replaces any previous schedule for ID 3.
    _scheduleCompletionNotification(mode, durationSeconds);
  }

  /// Schedule a local notification at the exact time the timer expires.
  /// Fires from AlarmManager even when the app process is dead.
  Future<void> _scheduleCompletionNotification(String mode, int durationSeconds) async {
    try {
      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(seconds: durationSeconds));
      final modeLabel = mode == 'focus' ? 'Focus' : mode == 'break_' ? 'Break' : 'Long Break';

      await _notifications.zonedSchedule(
        _scheduledCompletionId,
        'Deep Focus',
        '$modeLabel session complete! Take a break!',
        scheduledTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _completionChannelId, 'Session Complete',
            channelDescription: 'Session completion notifications with chime',
            importance: Importance.max,
            priority: Priority.max,
            autoCancel: true,
            ongoing: false,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 200, 150, 300, 200, 600]),
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('chime'),
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            visibility: NotificationVisibility.public,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('$_TAG scheduled completion for ${scheduledTime.toIso8601String()}');
    } catch (e) {
      debugPrint('$_TAG schedule completion failed: $e — will rely on in-app ticker + audio');
    }
  }

  Future<void> pauseTimer() async {
    final prefs = await SharedPreferences.getInstance();
    final isPaused = prefs.getBool('timer_paused') ?? false;

    if (!isPaused) {
      _ticker?.cancel();
      await _notifications.cancel(_scheduledCompletionId);
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

      _scheduleCompletionNotification(_currentMode, _remainingSeconds);

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
    await _notifications.cancel(_scheduledCompletionId);
    // Leave completion notification (ID 2) alone if user just finished — only clear on explicit stop mid-run
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
        // App process is alive: cancel AlarmManager ID 3 so we don't double-chime.
        // Sound comes from audioplayers (playCompletionSound) which is reliable
        // while the process is alive — including when backgrounded but not killed.
        // When the process is dead, only ID 3 fires (no ticker).
        _notifications.cancel(_progressNotificationId);
        _notifications.cancel(_scheduledCompletionId);
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
      // Timer expired while app was backgrounded.
      // AlarmManager may have already shown the notification; still update UI / auto-start.
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

  /// Fire completion feedback: ALWAYS play audio first, then show notification banner.
  Future<void> showCompletedNotification() async {
    // 1) Sound first — independent of Android notification policy
    await playCompletionSound();

    try {
      final vibrationPattern = Int64List.fromList([0, 200, 150, 300, 200, 600]);
      final modeLabel = _currentMode == 'focus' ? 'Focus' : _currentMode == 'break_' ? 'Break' : 'Long Break';

      await _notifications.show(
        _completionNotificationId,
        'Deep Focus',
        '$modeLabel session complete! Take a break!',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _completionChannelId, 'Session Complete',
            channelDescription: 'Session completion notifications with chime',
            importance: Importance.max,
            priority: Priority.max,
            autoCancel: true,
            ongoing: false,
            icon: '@mipmap/ic_launcher',
            enableVibration: true,
            vibrationPattern: vibrationPattern,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('chime'),
            category: AndroidNotificationCategory.alarm,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            visibility: NotificationVisibility.public,
            // OnlyCancelNotification so we don't kill sound by overwriting mid-play
            onlyAlertOnce: false,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );

      debugPrint('$_TAG completion notification sent (ID=$_completionNotificationId)');
    } catch (e) {
      debugPrint('$_TAG completion notif failed: $e');
    }
  }

  void dispose() {
    _ticker?.cancel();
    _audioPlayer.dispose();
  }
}
