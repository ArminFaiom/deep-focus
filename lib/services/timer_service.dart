import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class TimerService {
  static final TimerService _instance = TimerService._internal();
  factory TimerService() => _instance;
  TimerService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static const _TAG = '[TimerSvc]';
  
  Timer? _ticker;
  int _remainingSeconds = 0;
  int _durationSeconds = 0;
  String _currentMode = 'focus';

  // Callbacks
  Function(int remaining)? onTick;
  Function()? onComplete;

  Future<void> initialize() async {
    try {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notifications.initialize(initSettings);
      debugPrint('$_TAG initialized');
    } catch (e, st) {
      debugPrint('$_TAG init failed: $e\n$st');
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

    _startTicker();
    _showProgressNotification(mode, durationSeconds);
  }

  Future<void> pauseTimer() async {
    final prefs = await SharedPreferences.getInstance();
    // We don't track _isPaused in service because UI handles it now
    final isPaused = prefs.getBool('timer_paused') ?? false;
    
    if (!isPaused) {
      _ticker?.cancel();
      await prefs.setInt('timer_remaining', _remainingSeconds);
      await prefs.setBool('timer_paused', true);
      await prefs.setInt('timer_pause_time', DateTime.now().millisecondsSinceEpoch);
      await _notifications.cancel(1);
    } else {
      final pauseTime = prefs.getInt('timer_pause_time') ?? DateTime.now().millisecondsSinceEpoch;
      final pauseDuration = DateTime.now().millisecondsSinceEpoch - pauseTime;
      final oldStart = prefs.getInt('timer_start') ?? 0;
      
      await prefs.setInt('timer_start', oldStart + pauseDuration);
      await prefs.setBool('timer_paused', false);
      await prefs.remove('timer_pause_time');
      
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
    await _notifications.cancel(1);
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
        1,
        'Deep Focus',
        '$modeLabel timer running...',
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

  Future<void> _showCompletionNotification() async {
    try {
      await _notifications.show(
        2,
        'Deep Focus',
        '$_currentMode session complete! 🎉',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'timer_channel', 'Timer',
            channelDescription: 'Focus timer notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('$_TAG completion notif failed: $e');
    }
  }

  // Public — for triggering completion notification from outside
  Future<void> showCompletedNotification() async => _showCompletionNotification();
}
