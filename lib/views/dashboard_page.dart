import 'package:flutter/material.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    final outerRadius = BorderRadius.circular(w * 0.035);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(w * 0.02),
          child: ClipRRect(
            borderRadius: outerRadius,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/Main BG.png'),
                  fit: BoxFit.cover,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.02,
                  vertical: h * 0.025,
                ),
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTopRow(w, h),
                    ),
                    SizedBox(height: h * 0.022),
                    Expanded(
                      flex: 2,
                      child: _buildBottomTable(w, h),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopRow(double w, double h) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileCard(w, h),
        SizedBox(width: w * 0.018),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTimePanel(w, h),
              SizedBox(height: h * 0.016),
              _buildTodayLogCard(w, h),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(double w, double h) {
    final cardRadius = BorderRadius.circular(w * 0.03);

    return Container(
      width: w * 0.53,
      height: double.infinity,
      decoration: BoxDecoration(
        borderRadius: cardRadius,
        color: const Color(0xFF092238).withValues(alpha: 0.50),
      ),
      child: Row(
        children: [
          // Avatar / photo placeholder
          Container(
            width: w * 0.2,
            decoration: BoxDecoration(
              color: const Color(0xFF28496B),
              borderRadius: BorderRadius.only(
                topLeft: cardRadius.topLeft,
                bottomLeft: cardRadius.bottomLeft,
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
                      colors: [
                        Color(0xFF3FA9F5),
                        Color(0xFF1B75BB),
                      ],
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
            child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.022,
                  vertical: h * 0.024,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTopPill(w, label: 'PORTAL'),
                          ),
                          SizedBox(width: w * 0.012),
                          Expanded(
                            child: _buildTopPill(w, label: 'ENROLL NOW'),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: h * 0.016),
                    Text(
                      'BOLD NI WALLY',
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
                        borderRadius: BorderRadius.circular(w * 0.013),
                      ),
                      child: Text(
                        '250727648',
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
                      'UI/UX Designer',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontStyle: FontStyle.italic,
                        fontSize: w * 0.015,
                        color: Colors.white.withValues(alpha: 0.8),
                        letterSpacing: 1.4,
                      ),
                    ),
                    SizedBox(height: h * 0.006),
                    Text(
                      'INFORMATION TECHNOLOGY | FAST\nDISTRIBUTION CORPORATION',
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
        ],
      ),
    );
  }

  Widget _buildTopPill(double w, {required String label}) {
    final radius = BorderRadius.circular(w * 0.018);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.03,
        vertical: w * 0.0045,
      ),
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFF0E1F33).withValues(alpha: 0.92),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'CEORUSE',
            fontSize: w * 0.013,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.6,
          ),
        ),
      ),
    );
  }

  Widget _buildTimePanel(double w, double h) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.024,
        vertical: h * 0.018,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '03:36 PM',
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
                'MARCH 10, 2026',
                style: TextStyle(
                  fontFamily: 'CEORUSE',
                  fontSize: w * 0.02,
                  color: Colors.white.withValues(alpha: 0.9),
                  letterSpacing: 3,
                  height: 1.1,
                ),
              ),
              SizedBox(height: h * 0.002),
              Text(
                'TUESDAY',
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.024,
        vertical: h * 0.016,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.028),
        color: const Color(0xFF0B2742).withValues(alpha: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Text(
              'TODAYS LOG',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: w * 0.018,
                color: Colors.white,
                letterSpacing: 3,
              ),
            ),
          ),
          SizedBox(height: h * 0.016),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF041528),
              borderRadius: BorderRadius.circular(w * 0.014),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.018,
              vertical: h * 0.01,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                    ),
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
                ),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                          width: 1,
                        ),
                      ),
                    ),
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
                ),
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
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
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.014),
              color: const Color(0xFF0F3455).withValues(alpha: 0.9),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.018,
              vertical: h * 0.01,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'March 10, 2026',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.014,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '8:00AM',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.014,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '6:38PM',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: w * 0.014,
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

    final rows = <_DashboardRow>[
      const _DashboardRow(
        date: 'March 10, 2026',
        day: 'Thursday',
        shift: '8:00AM - 6:30PM',
        timeLogs: '8:00AM | 7:00PM',
        status: 'COMPLETE',
        isComplete: true,
      ),
      const _DashboardRow(
        date: 'March 10, 2026',
        day: 'Wednesday',
        shift: '8:00AM - 6:30PM',
        timeLogs: '8:00AM |',
        status: 'INCOMPLETE',
        isComplete: false,
      ),
      const _DashboardRow(
        date: 'March 10, 2026',
        day: 'Tuesday',
        shift: '8:00AM - 6:30PM',
        timeLogs: '10:00AM | 6:38PM',
        status: 'COMPLETE',
        isComplete: true,
      ),
      const _DashboardRow(
        date: 'March 10, 2026',
        day: 'Monday',
        shift: '8:00AM - 7:00PM',
        timeLogs: '7:00PM |',
        status: 'INCOMPLETE',
        isComplete: false,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.028),
        color: const Color.fromRGBO(4, 17, 27, 1).withValues(alpha: 0.80),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF05080C).withValues(alpha: 0.20),
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
                Expanded(
                  flex: 3,
                  child: Text('Date', style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Day', style: headerStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Shift Description', style: headerStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Time Logs', style: headerStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Status', style: headerStyle),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 0,
              ),
              itemBuilder: (context, index) {
                final row = rows[index];
                return Container(
                  decoration: BoxDecoration(
                    color: index.isEven
                        ? const Color(0xFF071A2B).withValues(alpha: 0.50)
                        : const Color(0xFF071A2B).withValues(alpha: 0.30),
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
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.015,
        vertical: w * 0.005,
      ),
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
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