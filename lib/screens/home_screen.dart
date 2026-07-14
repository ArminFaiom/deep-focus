import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../services/timer_service.dart';
import '../widgets/app_icons.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _initializeTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncTimerState();
    }
  }

  Future<void> _initializeTimer() async {
    // Set callbacks synchronously FIRST so Start works immediately
    _timerService.onTick = (remaining) {
      if (mounted) setState(() => _remaining = remaining);
    };
    _timerService.onComplete = () {
      if (mounted) _handleTimerComplete();
    };
    // Then init the notification plugin in background
    _timerService.initialize().then((_) => _syncTimerState());
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
      });
      await _timerService.syncStateOnResume();
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

  String get _label {
    switch (_mode) {
      case TimerMode.focus: return 'FOCUS';
      case TimerMode.break_: return 'BREAK';
      case TimerMode.long: return 'LONG BREAK';
    }
  }

  Color get _accentColor => _colorForMode(_mode);

  Color _colorForMode(TimerMode mode) {
    switch (mode) {
      case TimerMode.focus: return const Color(0xFF7C5CFC);
      case TimerMode.break_: return const Color(0xFF34D399);
      case TimerMode.long: return const Color(0xFF2DD4BF);
    }
  }

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

  /// How many of the 4 pomodoro-cycle dots are filled today.
  int get _cycleFilled {
    final n = _todayFocusSessions % 4;
    return (n == 0 && _todayFocusSessions > 0) ? 4 : n;
  }

  String get _totalDisplay {
    final mins = _totalMinutes ~/ 60;
    if (mins < 60) return '${mins}m';
    return '${(mins / 60).toStringAsFixed(1)}h';
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
        ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.weekday % 7],
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
  }

  void _startTimer() {
    if (_completed) {
      _resetDisplay();
    }
    if (_running) return;
    final secs = _secondsForMode;
    setState(() {
      _running = true;
      _paused = false;
      _completed = false;
      _remaining = secs;
      _total = secs;
    });
    _timerService.startTimer(
      durationSeconds: secs,
      mode: _mode.name,
    );
  }

  Future<void> _handleTimerComplete() async {
    // Single source of truth for what happens when timer hits 0
    final now = DateTime.now();
    final modeName = _mode.name;
    final completedDuration = _total;

    debugPrint('DeepFocus: handleTimerComplete mode=$modeName dur=$completedDuration');

    // Compute next mode + duration BEFORE setState (avoids mid-build races)
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

    // Build the session record and update in-memory list
    final session = {
      'date': _todayStr,
      'duration': completedDuration,
      'mode': modeName,
      'timestamp': now.toIso8601String(),
    };
    final newSessions = List<Map<String, dynamic>>.from(_sessions)..add(session);

    // Two paths:
    //  - nextMode set AND duration configured (>0): auto-start next phase
    //  - otherwise: stay in 00:00 "complete" state, wait for user tap
    bool autoStart = nextMode != null && nextSecs > 0 && !_paused;

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

    // Persist immediately (await), don't fire-and-forget
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sessions', jsonEncode(_sessions));
      debugPrint('DeepFocus: saved session, total count=${_sessions.length}');
    } catch (e) {
      debugPrint('DeepFocus: save failed: $e');
    }

    // If auto-starting, kick the new timer
    if (autoStart) {
      _timerService.startTimer(
        durationSeconds: nextSecs,
        mode: _mode.name,
      );
    }
  }

  void _togglePause() {
    if (!_running) return;
    setState(() => _paused = !_paused);
    _timerService.pauseTimer();
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

  // ─── UI ──────────────────────────────────────

  static const _cardColor = Color(0xFF15151F);
  static const _cardBorder = Color(0xFF26263A);
  static const _muted = Color(0xFF74748C);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.7),
            radius: 1.3,
            colors: [_accentColor.withOpacity(0.14), const Color(0xFF0B0B12)],
            stops: const [0.0, 0.75],
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
          const AppLogoMark(size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Deep Focus',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.4, height: 1.1),
                ),
                Text(
                  _running ? (_paused ? 'Paused' : 'Session in progress…') : 'Stay in the zone',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero timer card ─────────────────────────

  Widget _buildHeroTimerCard() {
    final fraction = _total > 0 ? _remaining / _total : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 26),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _cardBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 10))],
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
                _circleButton(
                  icon: _completed
                      ? Icons.replay_rounded
                      : (_running && !_paused ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  size: 74,
                  primary: true,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _completed ? _startTimer() : (_running ? _togglePause() : _startTimer());
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
        return FocusMarkIcon(size: 22, color: color, strokeWidth: 2.2);
      case TimerMode.break_:
        return Icon(Icons.local_cafe_rounded, size: 22, color: color);
      case TimerMode.long:
        return Icon(Icons.self_improvement_rounded, size: 22, color: color);
    }
  }

  Widget _cycleDots() {
    final filled = _cycleFilled;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 16 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? _accentColor : const Color(0xFF2A2A3E),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  Widget _segmentedModeControl() {
    final modes = [TimerMode.focus, TimerMode.break_, TimerMode.long];
    final index = modes.indexOf(_mode);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segW = constraints.maxWidth / modes.length;
          return SizedBox(
            height: 58,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  left: segW * index,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accentColor.withOpacity(0.55)),
                      boxShadow: [BoxShadow(color: _accentColor.withOpacity(0.25), blurRadius: 10, spreadRadius: -2)],
                    ),
                  ),
                ),
                Row(
                  children: [
                    _segmentItem(TimerMode.focus, 'Focus'),
                    _segmentItem(TimerMode.break_, 'Break'),
                    _segmentItem(TimerMode.long, 'Long'),
                  ],
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
    Widget icon;
    switch (mode) {
      case TimerMode.focus:
        icon = FocusMarkIcon(size: 16, color: color, strokeWidth: 2.0);
      case TimerMode.break_:
        icon = Icon(Icons.local_cafe_rounded, size: 17, color: color);
      case TimerMode.long:
        icon = Icon(Icons.self_improvement_rounded, size: 17, color: color);
    }
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _running ? null : () {
          HapticFeedback.selectionClick();
          setState(() { _mode = mode; _resetDisplay(); });
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _circleButton({required IconData icon, required double size, required bool primary, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: primary
              ? LinearGradient(colors: [_accentColor, _accentColor.withOpacity(0.72)], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: primary ? null : const Color(0xFF1D1D2C),
          border: primary ? null : Border.all(color: _cardBorder),
          boxShadow: primary
              ? [BoxShadow(color: _accentColor.withOpacity(0.45), blurRadius: 20, offset: const Offset(0, 8))]
              : null,
        ),
        child: Icon(icon, size: primary ? 32 : 22, color: primary ? Colors.white : const Color(0xFFB8B8CC)),
      ),
    );
  }

  // ── Session length card ─────────────────────

  Widget _buildSessionLengthCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SESSION LENGTH', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _muted, letterSpacing: 1.2)),
            const SizedBox(height: 14),
            Row(
              children: [
                _presetTile(const TomatoIcon(size: 20), 'Pomodoro', 25, 5, 15),
                const SizedBox(width: 10),
                _presetTile(const Icon(Icons.psychology_outlined, size: 20, color: Colors.white), 'Deep', 50, 10, 30),
                const SizedBox(width: 10),
                _presetTile(const Icon(Icons.bolt_rounded, size: 20, color: Colors.white), 'Quick', 15, 3, 10),
              ],
            ),
            const SizedBox(height: 22),
            _durationSlider(Icons.center_focus_strong_rounded, 'Focus', TimerMode.focus, _focusMin, 1, 120, (v) => _setDuration(TimerMode.focus, v)),
            const SizedBox(height: 14),
            _durationSlider(Icons.local_cafe_rounded, 'Break', TimerMode.break_, _breakMin, 1, 60, (v) => _setDuration(TimerMode.break_, v)),
            const SizedBox(height: 14),
            _durationSlider(Icons.self_improvement_rounded, 'Long', TimerMode.long, _longMin, 1, 120, (v) => _setDuration(TimerMode.long, v)),
            const SizedBox(height: 14),
            Center(
              child: GestureDetector(
                onTap: _running ? null : () => _applyPreset(25, 5, 15),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, size: 13, color: _muted),
                  SizedBox(width: 4),
                  Text('Reset to defaults', style: TextStyle(fontSize: 12, color: _muted)),
                ]),
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
        onTap: _running ? null : () {
          HapticFeedback.selectionClick();
          _applyPreset(f, b, l);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF7C5CFC).withOpacity(0.14) : const Color(0xFF1B1B28),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? const Color(0xFF7C5CFC).withOpacity(0.55) : _cardBorder),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? Colors.white : _muted)),
          ]),
        ),
      ),
    );
  }

  Widget _durationSlider(IconData fallbackIcon, String label, TimerMode mode, int value, int min, int max, ValueChanged<int> onChanged) {
    final color = _colorForMode(mode);
    return Row(
      children: [
        SizedBox(
          width: 26,
          child: mode == TimerMode.focus
              ? FocusMarkIcon(size: 15, color: color, strokeWidth: 1.8)
              : Icon(fallbackIcon, size: 16, color: color),
        ),
        SizedBox(width: 52, child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _muted, letterSpacing: 0.5))),
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
            ),
            child: Slider(
              value: value.toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              onChanged: _running ? null : (v) {
                setState(() {
                  final rounded = v.round();
                  switch (mode) {
                    case TimerMode.focus: _focusMin = rounded;
                    case TimerMode.break_: _breakMin = rounded;
                    case TimerMode.long: _longMin = rounded;
                  }
                });
              },
              onChangeEnd: _running ? null : (v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'monospace'))),
      ],
    );
  }

  // ── Insights card ───────────────────────────

  Widget _buildInsightsCard() {
    final data = _weeklyData;
    final maxMins = data.fold<int>(0, (m, d) => m > d.minutes ? m : d.minutes);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('INSIGHTS', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _muted, letterSpacing: 1.2)),
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
            Row(children: const [
              Icon(Icons.bar_chart_rounded, size: 14, color: _muted),
              SizedBox(width: 6),
              Text('This week', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: data.map((d) {
                  final ht = maxMins > 0 ? (d.minutes / maxMins).clamp(0.03, 1.0) : 0.03;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('${d.minutes}', style: const TextStyle(fontSize: 9, color: _muted)),
                          const SizedBox(height: 4),
                          Container(
                            height: 56 * ht,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: LinearGradient(colors: [_accentColor, _accentColor.withOpacity(0.28)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
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
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: _muted)),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(width: 1, height: 44, color: _cardBorder);
  }
}

// ─── Widgets ─────────────────────────────────

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
      width: 240,
      height: 240,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: accentColor.withOpacity(0.30), blurRadius: 44, spreadRadius: -6)],
      ),
      child: CustomPaint(
        painter: _RingPainter(fraction: 1.0 - fraction, accentColor: accentColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: completed
                    ? Icon(Icons.check_circle_rounded, key: const ValueKey('done'), size: 52, color: accentColor)
                    : KeyedSubtree(key: const ValueKey('mode'), child: modeIcon),
              ),
              const SizedBox(height: 10),
              Text(time, style: const TextStyle(fontSize: 46, fontWeight: FontWeight.w300, color: Colors.white, fontFamily: 'monospace', letterSpacing: 2)),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accentColor, letterSpacing: 2)),
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
    final radius = (size.width / 2) - 17;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF262638)..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, -fraction * 6.2832, false,
      Paint()
        ..shader = LinearGradient(colors: [accentColor, accentColor.withOpacity(0.6)]).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.fraction != fraction || old.accentColor != accentColor;
}

// ─── Value types ─────────────────────────────

class _DayData {
  final String day;
  final int minutes;
  const _DayData(this.day, this.minutes);
}

enum TimerMode { focus, break_, long }
