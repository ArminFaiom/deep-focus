import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../services/timer_service.dart';
import '../widgets/custom_icons.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  // Timer state
  TimerMode _mode = TimerMode.focus;
  bool _running = false;
  bool _paused = false;
  bool _completed = false;
  int _remaining = 0;
  int _total = 0;

  final TimerService _timerService = TimerService();

  // Durations (minutes)
  int _focusMin = 25;
  int _breakMin = 5;
  int _longMin = 15;

  // Sessions
  List<Map<String, dynamic>> _sessions = [];

  // Animations
  late AnimationController _ringController;
  late AnimationController _pulseController;
  late AnimationController _modeSwitchController;
  late Animation<double> _modeSwitchAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _initializeTimer();
    _initAnimations();
  }

  void _initAnimations() {
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _modeSwitchController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _modeSwitchAnimation = CurvedAnimation(
      parent: _modeSwitchController,
      curve: Curves.easeOutCubic,
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ringController.dispose();
    _pulseController.dispose();
    _modeSwitchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncTimerState();
    }
  }

  Future<void> _initializeTimer() async {
    _timerService.onTick = (remaining) {
      if (mounted) {
        setState(() => _remaining = remaining);
        _updateRingAnimation();
      }
    };
    _timerService.onComplete = () {
      if (mounted) _handleTimerComplete();
    };
    _timerService.initialize().then((_) => _syncTimerState());
  }

  void _updateRingAnimation() {
    if (_total > 0 && _running && !_paused) {
      final progress = 1.0 - (_remaining / _total);
      _ringController.value = progress;
    }
  }

  Future<void> _syncTimerState() async {
    final state = await _timerService.getTimerState();
    if (state != null && mounted) {
      setState(() {
        _running = state['running'] as bool;
        _paused = state['paused'] as bool;
        _remaining = state['remaining'] as int;
        _total = state['duration'] as int;
        final modeStr = state['mode'] as String;
        _mode = TimerMode.values.firstWhere((m) => m.name == modeStr);
        _completed = !_running && _remaining <= 0 && _total > 0;
      });
      await _timerService.syncStateOnResume();
      _updateRingAnimation();
    }
  }

  // ─── Persistence ─────────────────────────────

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _focusMin = prefs.getInt('focus_min') ?? 25;
      _breakMin = prefs.getInt('break_min') ?? 5;
      _longMin = prefs.getInt('long_min') ?? 15;
      final raw = prefs.getString('sessions');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _sessions = list.cast<Map<String, dynamic>>();
      }
    });
    _resetDisplay();
  }

  Future<void> _saveDurations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('focus_min', _focusMin);
    await prefs.setInt('break_min', _breakMin);
    await prefs.setInt('long_min', _longMin);
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sessions', jsonEncode(_sessions));
  }

  // ─── Computed ────────────────────────────────

  int get _secondsForMode {
    switch (_mode) {
      case TimerMode.focus: return _focusMin * 60;
      case TimerMode.break_: return _breakMin * 60;
      case TimerMode.long: return _longMin * 60;
    }
  }

  String get _label => _mode.label;

  Color get _accentColor => _mode.color;

  String get _todayStr {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  int get _todayMinutes =>
      _sessions.where((s) => s['date'] == _todayStr).fold(0, (sum, s) => sum + (s['duration'] as int));

  int get _todaySessions =>
      _sessions.where((s) => s['date'] == _todayStr).length;

  int get _todayFocusSessions =>
      _sessions.where((s) => s['date'] == _todayStr && s['mode'] == 'focus').length;

  int get _totalMinutes =>
      _sessions.fold(0, (sum, s) => sum + (s['duration'] as int));

  String get _totalDisplay {
    final hours = _totalMinutes ~/ 60;
    final mins = _totalMinutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  int get _streakDays {
    int streak = 0;
    final now = DateTime.now();
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final hasFocus = _sessions.any((s) => s['date'] == key && s['mode'] == 'focus');
      if (hasFocus) {
        streak++;
      } else if (i > 0) {
        break;
      }
    }
    return streak;
  }

  List<_DayData> get _weeklyData {
    final result = <_DayData>[];
    for (int i = 6; i >= 0; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final mins = _sessions
          .where((s) => s['date'] == key)
          .fold(0, (sum, s) => sum + (s['duration'] as int));
      result.add(_DayData(
        ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d.weekday % 7],
        mins ~/ 60,
      ));
    }
    return result;
  }

  // ─── Timer control ───────────────────────────

  void _resetDisplay() {
    _timerService.stopTimer();
    final secs = _secondsForMode;
    setState(() {
      _remaining = secs;
      _total = secs;
      _running = false;
      _paused = false;
      _completed = false;
    });
    _ringController.reset();
  }

  void _startTimer() {
    if (_completed) _resetDisplay();
    if (_running) return;
    final secs = _secondsForMode;
    setState(() {
      _running = true;
      _paused = false;
      _completed = false;
      _remaining = secs;
      _total = secs;
    });
    _ringController.forward(from: 0);
    _timerService.startTimer(durationSeconds: secs, mode: _mode.name);
  }

  Future<void> _handleTimerComplete() async {
    final now = DateTime.now();
    final modeName = _mode.name;
    final completedDuration = _total;

    debugPrint('DeepFocus: handleTimerComplete mode=$modeName dur=$completedDuration');

    // Compute next mode BEFORE setState
    TimerMode? nextMode;
    int nextSecs = 0;
    if (modeName == 'focus') {
      nextMode = TimerMode.break_;
      nextSecs = _breakMin * 60;
    } else if (modeName == 'break_') {
      nextMode = TimerMode.focus;
      nextSecs = _focusMin * 60;
    } else if (modeName == 'long') {
      nextMode = TimerMode.focus;
      nextSecs = _focusMin * 60;
    }

    final session = {
      'date': _todayStr,
      'duration': completedDuration,
      'mode': modeName,
      'timestamp': now.toIso8601String(),
    };
    final newSessions = List<Map<String, dynamic>>.from(_sessions)..add(session);

    final bool autoStart = nextMode != null && nextSecs > 0 && !_paused;

    setState(() {
      _sessions = newSessions;
      _remaining = 0;
      _completed = !autoStart;
      _running = autoStart;
      _paused = false;
      _total = autoStart ? nextSecs : _total;
      if (autoStart) {
        _mode = nextMode!;
        _remaining = nextSecs;
      }
    });

    // Persist immediately
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sessions', jsonEncode(_sessions));
      debugPrint('DeepFocus: saved session, total=${_sessions.length}');
    } catch (e) {
      debugPrint('DeepFocus: save failed: $e');
    }

    // Trigger completion notification
    await _timerService.showCompletedNotification();

    // Auto-start next phase
    if (autoStart) {
      _ringController.forward(from: 0);
      _timerService.startTimer(durationSeconds: nextSecs, mode: _mode.name);
    }
  }

  void _togglePause() {
    if (!_running) return;
    setState(() => _paused = !_paused);
    _timerService.pauseTimer();
    if (_paused) {
      _ringController.stop();
    } else {
      _ringController.forward(from: _ringController.value);
    }
  }

  void _applyPreset(int f, int b, int l) {
    if (_running) return;
    setState(() {
      _focusMin = f;
      _breakMin = b;
      _longMin = l;
    });
    _saveDurations();
    _resetDisplay();
    _modeSwitchController.forward(from: 0);
  }

  void _setDuration(TimerMode mode, int val) {
    if (_running) return;
    val = val.clamp(1, 999);
    setState(() {
      switch (mode) {
        case TimerMode.focus: _focusMin = val;
        case TimerMode.break_: _breakMin = val;
        case TimerMode.long: _longMin = val;
      }
    });
    _saveDurations();
    _resetDisplay();
  }

  String _fmt(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ─── UI Constants ────────────────────────────

  static const _bgColor = Color(0xFF0B0B12);
  static const _cardColor = Color(0xFF15151F);
  static const _cardBorder = Color(0xFF26263A);
  static const _muted = Color(0xFF74748C);
  static const _glassColor = Color(0x1AFFFFFF);
  static const _glassBorder = Color(0x33FFFFFF);

  // ─── Build ──────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.6),
            radius: 1.4,
            colors: [
              _accentColor.withOpacity(0.18),
              _bgColor,
            ],
            stops: const [0.0, 0.7],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 8),
                _buildHeroTimerCard(),
                const SizedBox(height: 16),
                _buildSessionLengthCard(),
                const SizedBox(height: 16),
                _buildInsightsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        children: [
          const AppLogoMark(size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deep Focus',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.4,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _running
                      ? (_paused ? 'Paused' : 'Session in progress…')
                      : 'Stay in the zone',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          if (_streakDays > 0) _buildStreakBadge(),
        ],
      ),
    );
  }

  Widget _buildStreakBadge() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_accentColor.withOpacity(0.2), _accentColor.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, size: 13, color: _accentColor),
          const SizedBox(width: 4),
          Text(
            '$_streakDays',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _accentColor,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Timer Card ─────────────────────────

  Widget _buildHeroTimerCard() {
    final fraction = _total > 0 ? _remaining / _total : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        decoration: BoxDecoration(
          color: _cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 32,
              offset: const Offset(0, 12),
              spreadRadius: -4,
            ),
            BoxShadow(
              color: _accentColor.withOpacity(0.1),
              blurRadius: 24,
              offset: const Offset(0, 0),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          children: [
            _segmentedModeControl(),
            const SizedBox(height: 28),
            _TimerRing(
              fraction: fraction,
              accentColor: _accentColor,
              completed: _completed,
              label: _completed ? 'COMPLETE' : _label,
              time: _fmt(_remaining),
              modeIcon: _buildRingModeIcon(),
            ),
            const SizedBox(height: 18),
            _cycleDots(),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleButton(
                  icon: Icons.restart_alt_rounded,
                  size: 50,
                  primary: false,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _resetDisplay();
                  },
                ),
                const SizedBox(width: 18),
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: (_running && !_paused && !_completed) ? _pulseAnimation.value : 1.0,
                      child: _circleButton(
                        icon: _completed
                            ? Icons.replay_rounded
                            : (_running && !_paused ? Icons.pause_rounded : Icons.play_arrow_rounded),
                        size: 78,
                        primary: true,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _completed ? _startTimer() : (_running ? _togglePause() : _startTimer());
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRingModeIcon() {
    final color = _accentColor.withOpacity(0.9);
    switch (_mode) {
      case TimerMode.focus:
        return FocusIcon(size: 24, color: color, strokeWidth: 2.4);
      case TimerMode.break_:
        return BreakIcon(size: 24, color: color);
      case TimerMode.long:
        return LongBreakIcon(size: 24, color: color);
    }
  }

  Widget _cycleDots() {
    final filled = _cycleFilled;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? _accentColor : const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(4),
            boxShadow: on
                ? [BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 8, spreadRadius: -2)]
                : null,
          ),
        );
      }),
    );
  }

  int get _cycleFilled {
    final n = _todayFocusSessions % 4;
    return (n == 0 && _todayFocusSessions > 0) ? 4 : n;
  }

  Widget _segmentedModeControl() {
    final modes = [TimerMode.focus, TimerMode.break_, TimerMode.long];
    final index = modes.indexOf(_mode);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F17),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / modes.length;
          return SizedBox(
            height: 58,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  left: segW * index,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_accentColor.withOpacity(0.18), _accentColor.withOpacity(0.08)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _accentColor.withOpacity(0.55)),
                      boxShadow: [
                        BoxShadow(
                          color: _accentColor.withOpacity(0.25),
                          blurRadius: 12,
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: modes.map((mode) => _segmentItem(mode, mode.shortLabel)).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _segmentItem(TimerMode mode, String label) {
    final active = _mode == mode;
    final color = active ? _accentColor : _muted;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _running
            ? null
            : () {
                HapticFeedback.selectionClick();
                setState(() {
                  _mode = mode;
                  _resetDisplay();
                });
                _modeSwitchController.forward(from: 0);
              },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: mode.icon(size: 18, color: color, opacity: active ? 1.0 : 0.7, key: ValueKey(mode)),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required double size,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: primary
              ? LinearGradient(
                  colors: [_accentColor, _accentColor.withOpacity(0.72)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: primary ? null : const Color(0xFF1D1D2C),
          border: primary ? null : Border.all(color: _cardBorder),
          boxShadow: primary
              ? [BoxShadow(color: _accentColor.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10))]
              : null,
        ),
        child: Icon(icon, size: primary ? 34 : 24, color: primary ? Colors.white : const Color(0xFFB8B8CC)),
      ),
    );
  }

  // ── Session Length Card ─────────────────────

  Widget _buildSessionLengthCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SESSION LENGTH',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _presetTile(
                  const TomatoIcon(size: 20),
                  'Pomodoro',
                  25, 5, 15,
                ),
                const SizedBox(width: 10),
                _presetTile(
                  const FocusIcon(size: 20, color: Colors.white, strokeWidth: 2.2),
                  'Deep Work',
                  50, 10, 30,
                ),
                const SizedBox(width: 10),
                _presetTile(
                  const Icon(Icons.bolt_rounded, size: 20, color: Colors.white),
                  'Quick',
                  15, 3, 10,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _durationSlider(TimerMode.focus, 'Focus', _focusMin, 1, 120),
            const SizedBox(height: 14),
            _durationSlider(TimerMode.break_, 'Break', _breakMin, 1, 60),
            const SizedBox(height: 14),
            _durationSlider(TimerMode.long, 'Long', _longMin, 1, 120),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: _running ? null : () => _applyPreset(25, 5, 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, size: 13, color: _running ? _muted.withOpacity(0.4) : _muted),
                    const SizedBox(width: 4),
                    Text(
                      'Reset to defaults',
                      style: TextStyle(
                        fontSize: 12,
                        color: _running ? _muted.withOpacity(0.4) : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetTile(Widget icon, String label, int f, int b, int l) {
    final active = _focusMin == f && _breakMin == b && _longMin == l;
    return Expanded(
      child: GestureDetector(
        onTap: _running
            ? null
            : () {
                HapticFeedback.selectionClick();
                _applyPreset(f, b, l);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? _accentColor.withOpacity(0.14) : const Color(0xFF1B1B28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? _accentColor.withOpacity(0.55) : _cardBorder),
            boxShadow: active
                ? [BoxShadow(color: _accentColor.withOpacity(0.15), blurRadius: 12, spreadRadius: -4, offset: const Offset(0, 4))]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationSlider(TimerMode mode, String label, int value, int min, int max) {
    final color = mode.color;
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: mode == TimerMode.focus
              ? FocusIcon(size: 16, color: color, strokeWidth: 2.0)
              : mode.icon(size: 17, color: color, opacity: 0.9),
        ),
        SizedBox(
          width: 52,
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _muted,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: color,
              inactiveTrackColor: const Color(0xFF2A2A3E),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayColor: color.withOpacity(0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
              valueIndicatorColor: color,
              valueIndicatorTextStyle: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              onChanged: _running
                  ? null
                  : (v) {
                      setState(() {
                        final rounded = v.round();
                        switch (mode) {
                          case TimerMode.focus: _focusMin = rounded;
                          case TimerMode.break_: _breakMin = rounded;
                          case TimerMode.long: _longMin = rounded;
                        }
                      });
                    },
              onChangeEnd: _running
                  ? null
                  : (v) => _setDuration(mode, v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  // ── Insights Card ───────────────────────────

  Widget _buildInsightsCard() {
    final data = _weeklyData;
    final maxMins = data.fold<int>(0, (m, d) => m > d.minutes ? m : d.minutes);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'INSIGHTS',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _muted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statTile(Icons.today_rounded, '$_todaySessions', 'Sessions today'),
                _statDivider(),
                _statTile(Icons.schedule_rounded, '${_todayMinutes ~/ 60}m', 'Minutes today'),
                _statDivider(),
                _statTile(Icons.insights_rounded, _totalDisplay, 'All time'),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(Icons.bar_chart_rounded, size: 14, color: _muted),
                const SizedBox(width: 6),
                Text(
                  'This week',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 88,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((d) {
                  final ht = maxMins > 0 ? (d.minutes / maxMins).clamp(0.05, 1.0) : 0.05;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${d.minutes}', style: const TextStyle(fontSize: 9, color: _muted)),
                          const SizedBox(height: 4),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeOutCubic,
                            height: 58 * ht,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              gradient: LinearGradient(
                                colors: [_accentColor, _accentColor.withOpacity(0.28)],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accentColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, -2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(d.day, style: const TextStyle(fontSize: 10, color: _muted)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 17, color: _accentColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 44, color: _cardBorder);
  }
}

// ─── Timer Ring Widget ─────────────────────────────────

class _TimerRing extends StatelessWidget {
  final double fraction;
  final Color accentColor;
  final bool completed;
  final String label;
  final String time;
  final Widget modeIcon;

  const _TimerRing({
    required this.fraction,
    required this.accentColor,
    required this.completed,
    required this.label,
    required this.time,
    required this.modeIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.35),
            blurRadius: 48,
            spreadRadius: -8,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _RingPainter(fraction: 1.0 - fraction, accentColor: accentColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: completed
                    ? Icon(
                        Icons.check_circle_rounded,
                        key: const ValueKey('done'),
                        size: 56,
                        color: accentColor,
                      )
                    : KeyedSubtree(key: const ValueKey('mode'), child: modeIcon),
              ),
              const SizedBox(height: 10),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color accentColor;

  _RingPainter({required this.fraction, required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8.5;

    // Background track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF262638)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 17
        ..strokeCap = StrokeCap.round,
    );

    // Progress arc
    if (fraction > 0) {
      final progressPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -3.14159 / 2,
          endAngle: 3.14159 * 1.5,
          colors: [
            accentColor,
            accentColor.withOpacity(0.6),
            accentColor,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 17
        ..strokeCap = StrokeCap.round;

      final sweepAngle = 2 * 3.14159 * fraction;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2,
        sweepAngle,
        false,
        progressPaint,
      );

      // Glow on progress end
      if (fraction < 1.0) {
        final endAngle = -3.14159 / 2 + sweepAngle;
        final endPoint = Offset(
          center.dx + radius * cos(endAngle),
          center.dy + radius * sin(endAngle),
        );
        final glowPaint = Paint()
          ..color = accentColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(endPoint, 10, glowPaint);
      }
    }
  }

  double cos(double r) => cos(r);
  double sin(double r) => sin(r);

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction || old.accentColor != accentColor;
}

// ─── Value types ─────────────────────────────

class _DayData {
  final String day;
  final int minutes;
  const _DayData(this.day, this.minutes);
}