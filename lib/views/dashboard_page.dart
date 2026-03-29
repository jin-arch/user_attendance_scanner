import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'enrollment_page.dart';
import '../services/local_db.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.matchedAt,
    this.siteId,
    this.onPortalTap,
    this.onEnrollNowTap,
  });

  final String? employeeId;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? matchedAt;
  final String? siteId;
  final VoidCallback? onPortalTap;
  final VoidCallback? onEnrollNowTap;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<_DashboardRow> _rows = const [];
  bool _loadingRows = true;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;
  bool _shownScanStatusModal = false;

  @override
  void initState() {
    super.initState();
    _loadRows();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _loadRows();
      }
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showScanStatusModalIfNeeded();
    });
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final attendanceChanged = oldWidget.attendanceType != widget.attendanceType;
    final matchTimeChanged = oldWidget.matchedAt != widget.matchedAt;
    final employeeChanged = oldWidget.employeeId != widget.employeeId;

    if (attendanceChanged || matchTimeChanged || employeeChanged) {
      _shownScanStatusModal = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showScanStatusModalIfNeeded();
      });
      unawaited(_loadRows());
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRows() async {
    final siteId = widget.siteId;
    final employeeId = widget.employeeId;
    if (siteId == null ||
        siteId.isEmpty ||
        employeeId == null ||
        employeeId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loadingRows = false;
      });
      return;
    }

    try {
      final history = await LocalDb.getTimelogHistoryForEmployee(
        siteId: siteId,
        employeeId: employeeId,
        limit: 10,
      );
      final seenDays = <String>{};
      final deduped = <Map<String, dynamic>>[];
      for (final row in history) {
        final key = _dateKeyFromRow(row);
        if (key.isNotEmpty && seenDays.contains(key)) {
          continue;
        }
        if (key.isNotEmpty) {
          seenDays.add(key);
        }
        deduped.add(row);
      }
      if (!mounted) return;
      setState(() {
        _rows = deduped.map(_rowFromTimelog).toList();
        _loadingRows = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loadingRows = false;
      });
    }
  }

  String _pickFirst(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return '';
  }

  bool _isBlank(String value) {
    final text = value.trim();
    return text.isEmpty ||
        text == '00:00:00' ||
        text == '0' ||
        text.toLowerCase() == 'null';
  }

  DateTime? _parseDate(String text) =>
      text.isEmpty ? null : DateTime.tryParse(text);

  String _dateKeyFromRow(Map<String, dynamic> row) {
    final raw = _pickFirst(row, [
      'timelog',
      'timeLogDate',
      'timelog_date',
      'datecaptured',
      'datelog',
    ]);
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }

  String _formatDate(DateTime date) {
    const months = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatDay(DateTime date) {
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    return days[date.weekday - 1];
  }

  _DashboardRow _rowFromTimelog(Map<String, dynamic> row) {
    final dateText = _pickFirst(row, [
      'timelog',
      'timeLogDate',
      'timelog_date',
      'datecaptured',
      'datelog',
    ]);
    final parsedDate = _parseDate(dateText);
    final timeInMorning = _pickFirst(row, [
      'timeInMorning',
      'timeinmorning',
      'time_in_morning',
      'time_in',
    ]);
    final timeOutMorning = _pickFirst(row, [
      'timeOutMorning',
      'timeoutmorning',
      'time_out_morning',
      'time_out',
    ]);
    final timeInAfternoon = _pickFirst(row, [
      'timeInAfternoon',
      'timeinafternoon',
      'time_in_afternoon',
    ]);
    final timeOutAfternoon = _pickFirst(row, [
      'timeOutAfternoon',
      'timeoutafternoon',
      'time_out_afternoon',
    ]);
    final firstIn = !_isBlank(timeInMorning)
        ? timeInMorning
        : (!_isBlank(timeInAfternoon) ? timeInAfternoon : '-');
    final lastOut = !_isBlank(timeOutAfternoon)
        ? timeOutAfternoon
        : (!_isBlank(timeOutMorning) ? timeOutMorning : '-');
    final hasIn = !_isBlank(timeInMorning) || !_isBlank(timeInAfternoon);
    final hasOut = !_isBlank(timeOutMorning) || !_isBlank(timeOutAfternoon);
    final status = hasIn && hasOut
        ? 'COMPLETE'
        : (hasIn ? 'INCOMPLETE' : 'NO LOG');

    return _DashboardRow(
      date: parsedDate != null
          ? _formatDate(parsedDate)
          : (dateText.isEmpty ? '-' : dateText),
      day: parsedDate != null ? _formatDay(parsedDate) : '-',
      shift: _pickFirst(row, ['schedule', 'schedCode']).isEmpty
          ? '-'
          : _pickFirst(row, ['schedule', 'schedCode']),
      timeLogs: '$firstIn | $lastOut',
      status: status,
      isComplete: status == 'COMPLETE',
    );
  }

  void _showScanStatusModalIfNeeded() {
    if (_shownScanStatusModal) return;
    final typeRaw = (widget.attendanceType ?? '').trim();
    if (typeRaw.isEmpty) return;
    _shownScanStatusModal = true;
    final type = typeRaw.toUpperCase();

    late final _ScanStatusDialogModel model;
    if (type == 'TIME IN') {
      model = const _ScanStatusDialogModel(
        title: 'TIME IN SUCESSFUL',
        message:
            'Your time in has been recorded successfully. Wishing you a productive day!',
        buttonLabel: 'PROCEED',
        theme: _ScanStatusTheme.success,
      );
    } else if (type == 'TIME OUT') {
      model = const _ScanStatusDialogModel(
        title: 'TIME OUT SUCESSFUL',
        message:
            'Your time has been recorded successfully. Wishing you a productive day!',
        buttonLabel: 'PROCEED',
        theme: _ScanStatusTheme.success,
      );
    } else if (type == 'ALREADY TIME IN') {
      model = const _ScanStatusDialogModel(
        title: 'ALREADY TIMED IN',
        message: 'You have already timed in for today.',
        buttonLabel: 'OKIEEE',
        theme: _ScanStatusTheme.info,
      );
    } else if (type == 'ALREADY TIME OUT') {
      model = const _ScanStatusDialogModel(
        title: 'ALREADY TIMED OUT',
        message: 'You have already timed out for today.',
        buttonLabel: 'OKIEEE',
        theme: _ScanStatusTheme.info,
      );
    } else if (type == 'TIME IN UNSUCCESSFUL') {
      model = const _ScanStatusDialogModel(
        title: 'TIME IN UNSUCCESSFUL',
        message: 'We couldn\'t process your request. Please try again.',
        buttonLabel: 'RETRY',
        theme: _ScanStatusTheme.error,
      );
    } else if (type == 'TIME OUT UNSUCCESSFUL') {
      model = const _ScanStatusDialogModel(
        title: 'TIME OUT UNSUCCESSFUL',
        message: 'We couldn\'t process your request. Please try again.',
        buttonLabel: 'RETRY',
        theme: _ScanStatusTheme.error,
      );
    } else {
      model = const _ScanStatusDialogModel(
        title: 'TIME UNSUCCESSFUL',
        message: 'We couldn\'t process your request. Please try again.',
        buttonLabel: 'RETRY',
        theme: _ScanStatusTheme.error,
      );
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ScanStatusDialog(model: model),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final outerRadius = BorderRadius.circular(w * 0.035);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/Main BG.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(w * 0.005),
            child: ClipRRect(
              borderRadius: outerRadius,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/images/Main BG.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cw = constraints.maxWidth;
                        final ch = constraints.maxHeight;
                        final ps = (cw * 0.06).clamp(32.0, 56.0);
                        return Stack(
                          children: [
                            _particle(cw, ch, 0.08, 0.15, ps * 1.2, 0),
                            _particle(cw, ch, 0.12, 0.08, ps * 0.5, 0.3),
                            _particle(cw, ch, 0.18, 0.5, ps * 0.9, 0.6),
                            _particle(cw, ch, 0.75, 0.45, ps * 1.1, 0.2),
                            _particle(cw, ch, 0.5, 0.2, ps * 0.55, 0.5),
                            _particle(cw, ch, 0.08, 0.7, ps * 1.0, 0.8),
                            _particle(cw, ch, 0.28, 0.35, ps * 0.45, 0.15),
                            _particle(cw, ch, 0.72, 0.3, ps * 0.9, 0.45),
                            _particle(cw, ch, 0.38, 0.78, ps * 0.6, 0.7),
                            _particle(cw, ch, 0.88, 0.6, ps * 1.15, 0.25),
                            _particle(cw, ch, 0.05, 0.42, ps * 0.5, 0.9),
                            _particle(cw, ch, 0.62, 0.48, ps * 0.75, 0.35),
                            _particle(cw, ch, 0.15, 0.85, ps * 0.7, 0.12),
                            _particle(cw, ch, 0.95, 0.12, ps * 0.8, 0.55),
                            _particle(cw, ch, 0.33, 0.11, ps * 0.6, 0.77),
                            _particle(cw, ch, 0.60, 0.88, ps * 1.0, 0.41),
                            _particle(cw, ch, 0.81, 0.22, ps * 0.5, 0.63),
                            _particle(cw, ch, 0.44, 0.59, ps * 0.9, 0.29),
                            _particle(cw, ch, 0.21, 0.66, ps * 0.8, 0.84),
                            _particle(cw, ch, 0.57, 0.33, ps * 0.7, 0.18),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: w * 0.02,
                      vertical: h * 0.025,
                    ),
                    child: Column(
                      children: [
                        Expanded(flex: 3, child: _buildTopRow(w, h)),
                        SizedBox(height: h * 0.022),
                        Expanded(flex: 2, child: _buildBottomTable(w, h)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _particle(
    double w,
    double h,
    double fracLeft,
    double fracTop,
    double sizePx,
    double phase,
  ) {
    return Positioned(
      left: w * fracLeft - sizePx / 2,
      top: h * fracTop - sizePx / 2,
      width: sizePx,
      height: sizePx,
      child: _DashboardRisingFadeParticle(
        size: sizePx,
        phase: phase,
        assetPath: 'assets/icons/square-particles-fx.svg',
      ),
    );
  }

  Widget _buildTopRow(double w, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileCard(w, h),
        SizedBox(width: w * 0.010),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTimePanel(w, h),
              SizedBox(height: h * 0.03),
              _buildTodayLogCard(w, h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(double w, double h) {
    final cardRadius = BorderRadius.circular(w * 0.023);
    final expandedPanelColor = const Color(0xFF092238).withValues(alpha: 0.50);

    return ClipRRect(
      borderRadius: cardRadius,
      child: Container(
        width: w * 0.55,
        height: double.infinity,
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              width: w * 0.2,
              decoration: BoxDecoration(
                color: const Color(0xFF092238).withValues(alpha: 0.7),
                borderRadius: BorderRadius.only(
                  topLeft: cardRadius.topLeft,
                  bottomLeft: cardRadius.bottomLeft,
                  topRight: cardRadius.topRight,
                ),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: w * 0.11,
                    height: w * 0.11,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: 3,
                      ),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3FA9F5), Color(0xFF1B75BB)],
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  SizedBox(height: h * 0.012),
                  Text(
                    'PROFILE',
                    style: TextStyle(
                      fontFamily: 'CEORUSE',
                      fontSize: w * 0.012,
                      color: Colors.white.withValues(alpha: 0.8),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      w * 0.010,
                      h * 0.016,
                      w * 0.005,
                      h * 0.024,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap: widget.onPortalTap,
                            child: _buildTopPill(
                              w,
                              label: 'PORTAL',
                              active: false,
                            ),
                          ),
                        ),
                        SizedBox(width: w * 0.005),
                        Expanded(
                          flex: 1,
                          child: GestureDetector(
                            onTap:
                                widget.onEnrollNowTap ??
                                () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => EnrollmentPage(
                                        employeeId: widget.employeeId,
                                        employeeName: widget.employeeName,
                                        siteId: widget.siteId,
                                      ),
                                    ),
                                  );
                                },
                            child: _buildTopPill(
                              w,
                              label: 'ENROLL NOW',
                              active: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          top: -(w * 0.02),
                          left: 0.1,
                          child: ClipPath(
                            clipper: const _TopLeftCurvedNotchClipper(),
                            child: Container(
                              width: w * 0.039,
                              height: w * 0.020,
                              color: expandedPanelColor,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: expandedPanelColor,
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(w * 0.03),
                                bottomRight: Radius.circular(w * 0.03),
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                w * 0.022,
                                h * 0.016,
                                w * 0.022,
                                h * 0.024,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (widget.employeeName ?? 'UNKNOWN USER')
                                        .toUpperCase(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'TRTCENZODEMO',
                                      fontSize: w * 0.027,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                  SizedBox(height: h * 0.012),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: w * 0.013,
                                      vertical: h * 0.004,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1D7CFF),
                                      borderRadius: BorderRadius.circular(
                                        w * 0.013,
                                      ),
                                    ),
                                    child: Text(
                                      widget.employeeId ?? 'N/A',
                                      style: TextStyle(
                                        fontFamily: 'CEORUSE',
                                        fontSize: w * 0.013,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: h * 0.012),
                                  Text(
                                    widget.attendanceType ?? 'RECORDED',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontStyle: FontStyle.italic,
                                      fontSize: w * 0.015,
                                      color: Colors.white.withValues(
                                        alpha: 0.8,
                                      ),
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  SizedBox(height: h * 0.006),
                                  Text(
                                    'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: w * 0.014,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 1.7,
                                      height: 1.25,
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPill(double w, {required String label, bool active = false}) {
    final radius = BorderRadius.circular(w * 0.018);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.01, vertical: w * 0.01),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: active
            ? const Color(0xFF0E1F33).withValues(alpha: 0.50)
            : const Color(0xFF0E1F33).withValues(alpha: 0.50),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: w * 0.012,
            color: Colors.white,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildTimePanel(double w, double h) {
    final now = _now;
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.020, vertical: h * 0.050),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${hour.toString().padLeft(2, '0')}:$minute $period',
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.042,
                  color: Colors.white,
                  letterSpacing: 4,
                  height: 1,
                ),
              ),
              SizedBox(height: h * 0.006),
              Text(
                _formatDate(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.020,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                _formatDay(now),
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.014,
                  color: Colors.white.withValues(alpha: 0.7),
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTodayLogCard(double w, double h) {
    final now = widget.matchedAt ?? DateTime.now();
    final todayDate = _formatDate(now);
    final todayLog = _rows.isNotEmpty
        ? _rows.first.timeLogs.split('|')
        : const ['-', '-'];
    final todayIn = todayLog.isNotEmpty ? todayLog.first.trim() : '-';
    final todayOut = todayLog.length > 1 ? todayLog[1].trim() : '-';
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: w * 0.38,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(w * 0.028),
            color: const Color(0xFF0B2742).withValues(alpha: 0.70),
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: h * 0.014),
                child: Text(
                  'TODAYS LOG',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: w * 0.020,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Container(
                color: const Color(0xFF081A2E).withValues(alpha: 0.50),
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.016,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Date',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'IN',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'OUT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.014,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.014,
                  vertical: h * 0.018,
                ),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 255, 255).withValues(alpha: 0.40),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(w * 0.028),
                    bottomRight: Radius.circular(w * 0.028),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        todayDate,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayIn,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        todayOut,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: w * 0.010,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomTable(double w, double h) {
    final headerStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.014,
      fontWeight: FontWeight.bold,
      color: Colors.white.withValues(alpha: 0.85),
      letterSpacing: 2,
    );

    final cellStyle = TextStyle(
      fontFamily: 'Poppins',
      fontSize: w * 0.013,
      color: Colors.white,
      letterSpacing: 1.4,
    );

    final rows = _rows;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.028),
        color: const Color.fromRGBO(4, 17, 27, 1).withValues(alpha: 0.50),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05080C).withValues(alpha: 0.30),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(w * 0.028),
                topRight: Radius.circular(w * 0.028),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.024,
              vertical: h * 0.016,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(flex: 3, child: Text('Date', style: headerStyle)),
                Expanded(flex: 2, child: Text('Day', style: headerStyle)),
                Expanded(flex: 3, child: Text('Workhours', style: headerStyle)),
                Expanded(flex: 3, child: Text('Time Logs', style: headerStyle)),
                Expanded(flex: 2, child: Text('Status', style: headerStyle)),
              ],
            ),
          ),
          Expanded(
            child: _loadingRows
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                ? Center(
                    child: Text(
                      'No timelog history found',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: w * 0.014,
                        color: Colors.white70,
                        letterSpacing: 1.2,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return Container(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? const Color(0xFF071A2B).withValues(alpha: 0.50)
                              : const Color.fromARGB(255, 147, 158, 168).withValues(alpha: 0.30),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.024,
                          vertical: h * 0.008,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(row.date, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(row.day, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.shift, style: cellStyle),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(row.timeLogs, style: cellStyle),
                            ),
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _buildStatusChip(w, row),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox.shrink(),
                    itemCount: rows.length,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(double w, _DashboardRow row) {
    final color = row.isComplete
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFFC107);
    final bg = row.isComplete
        ? const Color(0xFF162D1D)
        : const Color(0xFF2E2611);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.015, vertical: w * 0.005),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.018),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.01,
            height: w * 0.01,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: w * 0.008),
          Text(
            row.status,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: w * 0.010,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardRow {
  const _DashboardRow({
    required this.date,
    required this.day,
    required this.shift,
    required this.timeLogs,
    required this.status,
    required this.isComplete,
  });

  final String date;
  final String day;
  final String shift;
  final String timeLogs;
  final String status;
  final bool isComplete;
}

class _TopLeftCurvedNotchClipper extends CustomClipper<Path> {
  const _TopLeftCurvedNotchClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..quadraticBezierTo(size.width * 0.10, size.height * 0.92, 0, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _DashboardRisingFadeParticle extends StatefulWidget {
  const _DashboardRisingFadeParticle({
    required this.size,
    required this.assetPath,
    this.phase = 0.0,
  });

  final double size;
  final String assetPath;
  final double phase;

  @override
  State<_DashboardRisingFadeParticle> createState() =>
      _DashboardRisingFadeParticleState();
}

class _DashboardRisingFadeParticleState
    extends State<_DashboardRisingFadeParticle>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _opacity;
  Animation<double>? _translateY;
  Animation<double>? _scale;

  static const double _riseDistance = 48.0;
  static const Duration _duration = Duration(milliseconds: 2600);

  @override
  void initState() {
    super.initState();
    final controller = AnimationController(vsync: this, duration: _duration);
    final curve = CurvedAnimation(parent: controller, curve: Curves.easeOut);
    _controller = controller;
    _opacity = Tween<double>(begin: 0.50, end: 0.0).animate(curve);
    _translateY = Tween<double>(begin: 0.0, end: -_riseDistance).animate(curve);
    _scale = Tween<double>(begin: 1.0, end: 0.8).animate(curve);
    controller.value = widget.phase;
    controller.repeat();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final opacity = _opacity;
    final translateY = _translateY;
    final scale = _scale;
    if (controller == null ||
        opacity == null ||
        translateY == null ||
        scale == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, translateY.value),
          child: Opacity(
            opacity: opacity.value,
            child: Transform.scale(
              scale: scale.value,
              alignment: Alignment.center,
              child: SvgPicture.asset(
                widget.assetPath,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
                colorFilter: const ColorFilter.mode(
                  Color(0xFF5FCFFF),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _ScanStatusTheme { success, info, error }

class _ScanStatusDialogModel {
  const _ScanStatusDialogModel({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.theme,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final _ScanStatusTheme theme;
}

class _ScanStatusDialog extends StatelessWidget {
  const _ScanStatusDialog({required this.model});

  final _ScanStatusDialogModel model;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    Color ringOuter;
    Color ringInner;
    Color iconBg;
    IconData icon;
    Color buttonBg;
    Color buttonBorder;
    Color buttonText;

    switch (model.theme) {
      case _ScanStatusTheme.success:
        ringOuter = const Color(0xFFE5FEEA);
        ringInner = const Color(0xFFC9FBD4);
        iconBg = const Color(0xFF8EF4A5);
        icon = Icons.check;
        buttonBg = const Color(0xFFA3FFAE);
        buttonBorder = const Color(0xFF60D56E);
        buttonText = const Color(0xFF2E8C39);
        break;
      case _ScanStatusTheme.info:
        ringOuter = const Color(0xFFE8F4FF);
        ringInner = const Color(0xFFD7ECFF);
        iconBg = const Color(0xFFAED7FF);
        icon = Icons.access_time;
        buttonBg = const Color(0xFFAED3FF);
        buttonBorder = const Color(0xFF5AA6FF);
        buttonText = const Color(0xFF1D7DE9);
        break;
      case _ScanStatusTheme.error:
        ringOuter = const Color(0xFFFFEBEB);
        ringInner = const Color(0xFFFFD4D4);
        iconBg = const Color(0xFFFFA6A6);
        icon = Icons.close;
        buttonBg = const Color(0xFFFFB3B3);
        buttonBorder = const Color(0xFFFF6B6B);
        buttonText = const Color(0xFFB33A3A);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: w * 0.74,
        constraints: BoxConstraints(maxWidth: 760, minHeight: h * 0.22),
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.03,
          vertical: h * 0.025,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: ringOuter, shape: BoxShape.circle),
              child: Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: ringInner,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.black87, size: 16),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: h * 0.014),
            Text(
              model.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: Color(0xFF10152A),
              ),
            ),
            SizedBox(height: h * 0.008),
            Text(
              model.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 24,
                color: Color(0xFF4A516A),
                height: 1.25,
              ),
            ),
            SizedBox(height: h * 0.018),
            SizedBox(
              width: w * 0.26,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonBg,
                  foregroundColor: buttonText,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: buttonBorder),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  model.buttonLabel,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
