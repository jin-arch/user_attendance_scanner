abstract final class DateTimeFormats {
  static String dateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String dateOnly(DateTime date) => dateKey(date);

  static String timeOnly(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  static String dayShort(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  static String dayLongUpper(DateTime date) {
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

  static String dateLongUpper(DateTime date) {
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

  /// HRIS API dates like `2026/02/26 07:05:16` → `2026-02-26`.
  static String? dateFromApiValue(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    var dt = DateTime.tryParse(s.replaceAll('/', '-'));
    if (dt == null) {
      final slashMatch = RegExp(
        r'^(\d{4})/(\d{1,2})/(\d{1,2})',
      ).firstMatch(s);
      if (slashMatch != null) {
        dt = DateTime(
          int.parse(slashMatch.group(1)!),
          int.parse(slashMatch.group(2)!),
          int.parse(slashMatch.group(3)!),
        );
      }
    }

    if (dt != null) return dateKey(dt);

    final head = s.length >= 10 ? s.substring(0, 10) : s;
    return head.replaceAll('/', '-');
  }

  /// HRIS API datetimes like `2026/02/26 07:05:16` → `07:05:16`.
  static String formatTimeFromApi(dynamic raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty ||
        text == '-' ||
        text.toLowerCase() == 'null') {
      return '';
    }

    final normalized = text.replaceAll('/', '-');
    final dt = DateTime.tryParse(normalized);
    if (dt != null) return timeOnly(dt);

    if (text.contains(' ')) {
      final timePart = text.split(' ').last.trim();
      if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(timePart)) {
        return timePart.length >= 8 ? timePart.substring(0, 8) : timePart;
      }
    }

    if (RegExp(r'^\d{1,2}:\d{2}').hasMatch(text)) {
      return text.length >= 8 ? text.substring(0, 8) : text;
    }

    return text;
  }
}
