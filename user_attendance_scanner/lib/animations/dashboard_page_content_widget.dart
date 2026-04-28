part of '../views/dashboard_page.dart';

class _DashboardPageContent extends StatefulWidget {
  const _DashboardPageContent({
    this.employeeId,
    this.employeeName,
    this.attendanceType,
    this.matchedAt,
    this.siteId,
    this.onPortalTap,
    this.onEnrollNowTap,
    this.resultType,
    this.timeIn,
    this.timeOut,
  });

  final String? employeeId;
  final String? employeeName;
  final String? attendanceType;
  final DateTime? matchedAt;
  final String? siteId;
  final VoidCallback? onPortalTap;
  final VoidCallback? onEnrollNowTap;
  final String? resultType;
  final String? timeIn;
  final String? timeOut;

  @override
  State<_DashboardPageContent> createState() => _DashboardPageState();
}
