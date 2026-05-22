// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDb {
  static Database? _db;
  static const String _dbFileName = 'biometric_scanner.db';
  static const String _legacyDbFileName = 'biometrics_scanner.db';
  static const String _windowsDbDirectory = r'C:\SQLiteDB';
  static const String _apiBaseUrl =
      'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php/';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';
  static const int _maxTimelogRowsRead = 1200;

  static Map<String, dynamic> _emptyJson() => <String, dynamic>{};

  static List<Map<String, dynamic>> _extractRows(dynamic decoded) {
    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      data =
          decoded['data'] ??
          decoded['sites'] ??
          decoded['result'] ??
          decoded['records'] ??
          decoded['site'] ??
          decoded['employees'] ??
          decoded['timelogs'] ??
          decoded['timelog'] ??
          decoded['logs'] ??
          decoded['results'] ??
          decoded['items'] ??
          decoded;
    }

    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    if (data is Map<String, dynamic>) {
      return [data];
    }

    return const [];
  }

  static Future<List<Map<String, dynamic>>> _getApiRows(
    String endpoint, {
    Map<String, String?> queryParameters = const {},
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final uri = Uri.parse('$_apiBaseUrl$endpoint').replace(
        queryParameters: queryParameters.map(
          (key, value) => MapEntry(key, value ?? ''),
        ),
      );
      final request = await client.getUrl(uri);
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: $body');
      }

      if (body.trim().isEmpty) {
        return const [];
      }

      final decoded = jsonDecode(body);
      return _extractRows(decoded);
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _postJson(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.postUrl(Uri.parse('$_apiBaseUrl$endpoint'));
      final basicToken = base64Encode(
        utf8.encode('$_apiUsername:$_apiPassword'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'FAST-Attendance/1.0');
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basicToken');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode > 299) {
        throw Exception('HTTP ${response.statusCode}: $responseBody');
      }

      if (responseBody.trim().isEmpty) {
        return _emptyJson();
      }

      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return {'data': decoded};
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        fid INTEGER PRIMARY KEY,
        employee_id TEXT NOT NULL,
        employee_name TEXT,
        finger_template BLOB NOT NULL,
        site_id TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employees_site ON employees (site_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_photos (
        employee_id TEXT NOT NULL,
        site_id TEXT NOT NULL,
        photo BLOB NOT NULL,
        PRIMARY KEY (employee_id, site_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employee_photos_site ON employee_photos (site_id)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS attendance_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        employee_id TEXT NOT NULL,
        site_id TEXT NOT NULL,
        attendance_time TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS hris_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        query_params TEXT NOT NULL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS timelog_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id TEXT NOT NULL,
        employee_id TEXT,
        timelog_date TEXT,
        raw_json TEXT NOT NULL,
        UNIQUE(site_id, employee_id, timelog_date)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS site_preferences (
        id INTEGER PRIMARY KEY,
        selected_site_id TEXT NOT NULL,
        selected_site_name TEXT,
        last_updated TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sites_cache (
        site_id TEXT PRIMARY KEY,
        site_name TEXT NOT NULL,
        last_updated TEXT NOT NULL
      )
    ''');

    await _ensureTimelogCacheColumns(db);
    await _ensureAttendanceQueueColumns(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_timelog_cache_lookup ON timelog_cache (site_id, employee_id, timelog_date)',
    );
  }

  static Future<void> _ensureAttendanceQueueColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(attendance_queue)');
    final names = cols.map((c) => c['name']?.toString()).toSet();
    if (!names.contains('record_type')) {
      await db.execute(
        "ALTER TABLE attendance_queue ADD COLUMN record_type TEXT NOT NULL DEFAULT 'attendance'",
      );
    }
    if (!names.contains('payload_json')) {
      await db.execute(
        'ALTER TABLE attendance_queue ADD COLUMN payload_json TEXT',
      );
    }
  }

  static Future<void> _ensureTimelogCacheColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(timelog_cache)');
    final hasTimelogDate = cols.any((c) => c['name'] == 'timelog_date');
    if (!hasTimelogDate) {
      await db.execute(
        'ALTER TABLE timelog_cache ADD COLUMN timelog_date TEXT',
      );
    }
  }

  static bool _isBlank(dynamic v) {
    if (v == null) return true;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ||
          s == '00:00:00' ||
          s == '00:00' ||
          s == '0' ||
          s == '-' ||
          s.toLowerCase() == 'null' ||
          s.toLowerCase() == 'n/a' ||
          s.toLowerCase() == 'na' ||
          s.toLowerCase() == 'none' ||
          s.toLowerCase() == 'empty';
    }
    return false;
  }

  static String? _normalizeDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;

    final dt = DateTime.tryParse(s);
    if (dt != null) {
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }

    return s.length >= 10 ? s.substring(0, 10) : s;
  }

  static String? _extractTimelogDate(Map<String, dynamic> timelogData) {
    final raw =
        timelogData['timelog'] ??
        timelogData['timeLogDate'] ??
        timelogData['timelog_date'] ??
        timelogData['date'];
    return _normalizeDate(raw);
  }

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    // sqflite_common_ffi required on desktop (Windows / Linux)
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    String path;
    String legacyPath;
    if (!kIsWeb && Platform.isWindows) {
      final windowsDir = Directory(_windowsDbDirectory);
      if (!await windowsDir.exists()) {
        await windowsDir.create(recursive: true);
      }
      path = p.join(_windowsDbDirectory, _dbFileName);
      legacyPath = p.join(_windowsDbDirectory, _legacyDbFileName);
    } else {
      final dbPath = await getDatabasesPath();
      path = p.join(dbPath, _dbFileName);
      legacyPath = p.join(dbPath, _legacyDbFileName);
    }

    final currentFile = File(path);
    final legacyFile = File(legacyPath);
    if (!await currentFile.exists() && await legacyFile.exists()) {
      await legacyFile.copy(path);
    }

    return openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await _ensureSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
      },
      onOpen: (db) async {
        await _ensureSchema(db);
      },
    );
  }

  /// Insert or replace a single employee record.
  static Future<void> upsertEmployee({
    required int fid,
    required String employeeId,
    required String? employeeName,
    required Uint8List template,
    required String siteId,
  }) async {
    final database = await db;
    await database.insert('employees', {
      'fid': fid,
      'employee_id': employeeId,
      'employee_name': employeeName,
      'finger_template': template,
      'site_id': siteId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Insert or replace an employee selfie photo.
  static Future<void> upsertEmployeePhoto({
    required String employeeId,
    required String siteId,
    required Uint8List photo,
  }) async {
    final database = await db;
    await database.insert('employee_photos', {
      'employee_id': employeeId,
      'site_id': siteId,
      'photo': photo,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Fetch a selfie photo for an employee (if any).
  static Future<Uint8List?> getEmployeePhoto({
    required String employeeId,
    required String siteId,
  }) async {
    final database = await db;
    final rows = await database.query(
      'employee_photos',
      columns: ['photo'],
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['photo'];
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  /// Merge API employees with local enrollments - preserves locally enrolled employees
  static Future<void> mergeEmployeesFromApi({
    required String siteId,
    required List<Map<String, dynamic>> apiEmployees,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      // Get list of employee_ids from API to delete only those (preserve local enrollments)
      final apiEmployeeIds = apiEmployees
          .map((e) => e['employee_id'] as String)
          .toSet();

      // Delete only API-provided employees, keep locally enrolled ones
      for (final empId in apiEmployeeIds) {
        await txn.delete(
          'employees',
          where: 'site_id = ? AND employee_id = ?',
          whereArgs: [siteId, empId],
        );
      }

      if (apiEmployees.isEmpty) {
        return;
      }

      // Insert API employees
      final batch = txn.batch();
      for (final row in apiEmployees) {
        batch.insert('employees', {
          'fid': row['fid'],
          'employee_id': row['employee_id'],
          'employee_name': row['employee_name'],
          'finger_template': row['finger_template'],
          'site_id': siteId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  static Future<void> replaceEmployeesBySite({
    required String siteId,
    required List<Map<String, dynamic>> employees,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('employees', where: 'site_id = ?', whereArgs: [siteId]);

      if (employees.isEmpty) {
        return;
      }

      final batch = txn.batch();
      for (final row in employees) {
        batch.insert('employees', {
          'fid': row['fid'],
          'employee_id': row['employee_id'],
          'employee_name': row['employee_name'],
          'finger_template': row['finger_template'],
          'site_id': siteId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// Fetch all employees for a given site.
  static Future<List<Map<String, dynamic>>> getEmployeesBySite(
    String siteId,
  ) async {
    final database = await db;
    return database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
  }

  /// Remove all cached employees for a site (called before a fresh sync).
  static Future<void> deleteEmployeesBySite(String siteId) async {
    final database = await db;
    await database.delete(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
    await database.delete(
      'employee_photos',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
  }

  static Future<int> queueAttendance({
    required String employeeId,
    required String siteId,
    required String attendanceTime,
    String recordType = 'attendance',
    String? payloadJson,
  }) async {
    return queuePendingRecord(
      employeeId: employeeId,
      siteId: siteId,
      attendanceTime: attendanceTime,
      recordType: recordType,
      payloadJson: payloadJson,
    );
  }

  static Future<int> queuePendingRecord({
    required String employeeId,
    required String siteId,
    required String attendanceTime,
    String recordType = 'attendance',
    String? payloadJson,
  }) async {
    final database = await db;
    final normalizedEmployeeId = employeeId.trim();
    final normalizedType = recordType.trim().toLowerCase();

    final existing = await database.query(
      'attendance_queue',
      columns: ['id'],
      where:
          'employee_id = ? AND site_id = ? AND attendance_time = ? AND record_type = ? AND synced = 0',
      whereArgs: [
        normalizedEmployeeId,
        siteId,
        attendanceTime,
        normalizedType,
      ],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingId = existing.first['id'] as int? ?? 0;
      debugPrint(
        '[ATTENDANCE_QUEUE] Duplicate pending skipped: type=$normalizedType id=$existingId',
      );
      return existingId;
    }

    return database.insert('attendance_queue', {
      'employee_id': normalizedEmployeeId,
      'site_id': siteId,
      'attendance_time': attendanceTime,
      'record_type': normalizedType,
      'payload_json': payloadJson,
      'synced': 0,
    });
  }

  static Future<int> queueFingerprintUpdate({
    required String employeeId,
    required String siteId,
  }) async {
    return queuePendingRecord(
      employeeId: employeeId,
      siteId: siteId,
      attendanceTime: DateTime.now().toIso8601String(),
      recordType: 'fingerprint',
      payloadJson: jsonEncode({'employee_id': employeeId, 'site_id': siteId}),
    );
  }

  /// Build API thumb payloads from the latest left/right templates in local DB.
  static Future<(String, String)?> getEmployeeThumbTemplatesForApi({
    required String employeeId,
    required String siteId,
  }) async {
    final rows = await getEmployeesBySite(siteId);
    String? leftB64;
    String? rightB64;

    int leftFid = _stableFingerprintId(employeeId, 'left');
    int rightFid = _stableFingerprintId(employeeId, 'right');

    for (final row in rows) {
      if (row['employee_id']?.toString().trim() != employeeId.trim()) continue;
      final fid = row['fid'] as int?;
      final raw = row['finger_template'];
      Uint8List? bytes;
      if (raw is Uint8List) {
        bytes = raw;
      } else if (raw is List<int>) {
        bytes = Uint8List.fromList(raw);
      }
      if (bytes == null || bytes.isEmpty) continue;
      final b64 = base64Encode(bytes);
      if (fid == leftFid) leftB64 = b64;
      if (fid == rightFid) rightB64 = b64;
    }

    if (leftB64 == null || rightB64 == null) return null;
    return (leftB64, rightB64);
  }

  static int _stableFingerprintId(String employeeId, String thumbKey) {
    var hash = 0x811C9DC5;
    final input = '$employeeId:$thumbKey';
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  static Future<Map<String, dynamic>?> getTimelogPayloadForPendingAttendance({
    required String employeeId,
    required String siteId,
    required String attendanceTime,
  }) async {
    final parsed = DateTime.tryParse(attendanceTime);
    final dayKey = parsed != null
        ? '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}'
        : attendanceTime.split('T').first;

    final cached = await getTimelogForEmployeeOnDate(
      siteId: siteId,
      employeeId: employeeId,
      date: dayKey,
    );
    if (cached == null) return null;

    return {
      'timeLogId': cached['timelogID'] ?? cached['timeLogID'] ?? '',
      'timeLogDate': cached['timeLogDate'] ?? cached['timelog'] ?? dayKey,
      'remarks': cached['remarks'] ?? cached['remark'] ?? 'SUCCESS',
      'schedule': cached['schedule'] ?? cached['schedCode'] ?? 'AUTO',
      'code': cached['code'] ?? 'IN_AM',
      'timeInMorning': cached['timeInMorning'],
      'timeOutMorning': cached['timeOutMorning'],
      'timeInAfternoon': cached['timeInAfternoon'],
      'timeOutAfternoon': cached['timeOutAfternoon'],
    };
  }

  static Future<List<Map<String, dynamic>>> getPendingAttendance() async {
    final database = await db;
    return database.query(
      'attendance_queue',
      where: 'synced = ?',
      whereArgs: const [0],
      orderBy: 'id ASC',
    );
  }

  static Future<void> markAttendanceSynced(int id) async {
    final database = await db;
    await database.update(
      'attendance_queue',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> queueHrisRequest({
    required String endpoint,
    required Map<String, String> queryParams,
  }) async {
    final database = await db;
    return database.insert('hris_queue', {
      'endpoint': endpoint,
      'query_params': jsonEncode(queryParams),
      'synced': 0,
    });
  }

  static Future<List<Map<String, dynamic>>> getPendingHrisRequests() async {
    final database = await db;
    return database.query(
      'hris_queue',
      where: 'synced = ?',
      whereArgs: const [0],
      orderBy: 'id ASC',
    );
  }

  static Future<void> markHrisRequestSynced(int id) async {
    final database = await db;
    await database.update(
      'hris_queue',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> replaceTimelogCache({
    required String siteId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final database = await db;

    final registeredEmployees = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id'],
    );

    final registeredIds = registeredEmployees
        .map((row) => row['employee_id'].toString())
        .toSet();

    debugPrint(
      '[TIMELOG_CACHE] Processing ${rows.length} rows for ${registeredIds.length} enrolled employees',
    );

    if (rows.isEmpty) return;

    final filteredTimelogs = <Map<String, dynamic>>[];
    int skippedCount = 0;

    for (final row in rows) {
      final employeeId =
          (row['employee_id'] ??
                  row['companyID'] ??
                  row['employeeID'] ??
                  row['EMPLOYEEID'])
              ?.toString();

      if (employeeId == null || !registeredIds.contains(employeeId)) {
        skippedCount++;
        continue;
      }

      final timelogDate = _normalizeDate(
        row['timelog'] ??
            row['timeLogDate'] ??
            row['timelog_date'] ??
            row['date'],
      );
      final payload = Map<String, dynamic>.from(row);

      if (timelogDate != null) {
        payload['timelog_date'] = timelogDate;
        payload['timeLogDate'] ??= timelogDate;
        payload['timelog'] ??= timelogDate;
      }

      filteredTimelogs.add(payload);
    }

    await batchSaveTimelogs(siteId: siteId, timelogDataList: filteredTimelogs);

    debugPrint(
      '[TIMELOG_CACHE] Upserted: ${filteredTimelogs.length}, Skipped: $skippedCount',
    );
  }

  static Future<Map<String, dynamic>?> getLatestTimelogForEmployee({
    required String siteId,
    required String employeeId,
  }) async {
    final database = await db;
    final rows = await database.query(
      'timelog_cache',
      columns: ['raw_json'],
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: "COALESCE(timelog_date, '') DESC, id DESC",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['raw_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Offline-first: load today's timelog for an employee (not the latest row globally).
  static Future<Map<String, dynamic>?> getTimelogForEmployeeOnDate({
    required String siteId,
    required String employeeId,
    required String date,
  }) async {
    final normalizedDate = _normalizeDate(date);
    if (normalizedDate == null) return null;

    final database = await db;
    var rows = await database.query(
      'timelog_cache',
      columns: ['raw_json'],
      where: 'site_id = ? AND employee_id = ? AND timelog_date = ?',
      whereArgs: [siteId, employeeId, normalizedDate],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      final candidates = await database.query(
        'timelog_cache',
        columns: ['raw_json'],
        where: 'site_id = ? AND employee_id = ?',
        whereArgs: [siteId, employeeId],
        orderBy: 'id DESC',
        limit: 20,
      );
      for (final row in candidates) {
        final raw = row['raw_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic> &&
              _normalizeDate(_extractTimelogDate(decoded)) == normalizedDate) {
            return decoded;
          }
        } catch (_) {}
      }
      return null;
    }

    final raw = rows.first['raw_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getTimelogHistoryForEmployee({
    required String siteId,
    required String employeeId,
    int limit = 10,
  }) async {
    final database = await db;
    final rows = await database.query(
      'timelog_cache',
      columns: ['raw_json'],
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: "COALESCE(timelog_date, '') DESC, id DESC",
      limit: limit,
    );

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['raw_json'] as String?;
      if (raw == null || raw.isEmpty) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          results.add(decoded);
        }
      } catch (_) {}
    }

    return results;
  }

  /// Save or update a single timelog record in cache
  ///
  /// Important: We keep a *single row per (siteId, employeeId, timelog_date)* so
  /// scanning updates the existing cache instead of creating "new data".
  static Future<void> saveTimelog({
    required String siteId,
    required String employeeId,
    required Map<String, dynamic> timelogData,
  }) async {
    final database = await db;

    final timelogDate = _extractTimelogDate(timelogData);

    print('[SAVE_DB] ===== START saveTimelog =====');
    print(
      '[SAVE_DB] siteId="$siteId" employeeId="$employeeId" timelogDate="$timelogDate"',
    );

    // Find existing row for the same day (preferred) otherwise fallback to latest.
    List<Map<String, Object?>> existingRows;
    if (timelogDate != null) {
      existingRows = await database.query(
        'timelog_cache',
        where: 'site_id = ? AND employee_id = ? AND timelog_date = ?',
        whereArgs: [siteId, employeeId, timelogDate],
        orderBy: 'id DESC',
        limit: 1,
      );

      // Back-compat: older rows may have timelog_date NULL, so try matching by
      // decoding raw_json from the latest few rows.
      if (existingRows.isEmpty) {
        final candidates = await database.query(
          'timelog_cache',
          where: 'site_id = ? AND employee_id = ?',
          whereArgs: [siteId, employeeId],
          orderBy: 'id DESC',
          limit: 10,
        );

        for (final row in candidates) {
          final raw = row['raw_json'] as String?;
          if (raw == null || raw.isEmpty) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              final d = _extractTimelogDate(decoded);
              if (d == timelogDate) {
                existingRows = [row];
                break;
              }
            }
          } catch (_) {}
        }
      }
    } else {
      existingRows = await database.query(
        'timelog_cache',
        where: 'site_id = ? AND employee_id = ?',
        whereArgs: [siteId, employeeId],
        orderBy: "COALESCE(timelog_date, '') DESC, id DESC",
        limit: 1,
      );
    }

    Map<String, dynamic> merged = <String, dynamic>{};
    int? existingId;
    if (existingRows.isNotEmpty) {
      existingId = (existingRows.first['id'] as int?);
      final raw = existingRows.first['raw_json'] as String?;
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            merged.addAll(decoded);
          }
        } catch (_) {}
      }
    }

    // Merge: only overwrite with non-blank values so we don't lose earlier times.
    for (final entry in timelogData.entries) {
      if (!_isBlank(entry.value)) {
        merged[entry.key] = entry.value;
      }
    }
    merged['employee_id'] ??= employeeId;

    final payload = jsonEncode(merged);

    if (existingId != null) {
      await database.update(
        'timelog_cache',
        {
          'site_id': siteId,
          'employee_id': employeeId,
          'timelog_date': timelogDate ?? _extractTimelogDate(merged),
          'raw_json': payload,
        },
        where: 'id = ?',
        whereArgs: [existingId],
      );

      // Remove any duplicates for the same key (can happen from earlier debug code).
      if (timelogDate != null) {
        await database.delete(
          'timelog_cache',
          where:
              'site_id = ? AND employee_id = ? AND timelog_date = ? AND id <> ?',
          whereArgs: [siteId, employeeId, timelogDate, existingId],
        );
      }

      print('[SAVE_DB] Updated timelog_cache id=$existingId');
    } else {
      final newId = await database.insert('timelog_cache', {
        'site_id': siteId,
        'employee_id': employeeId,
        'timelog_date': timelogDate,
        'raw_json': payload,
      });

      // Clean up duplicates for the same key right away.
      if (timelogDate != null) {
        await database.delete(
          'timelog_cache',
          where:
              'site_id = ? AND employee_id = ? AND timelog_date = ? AND id <> ?',
          whereArgs: [siteId, employeeId, timelogDate, newId],
        );
      }

      print('[SAVE_DB] Inserted timelog_cache id=$newId');
    }

    print('[SAVE_DB] ===== END saveTimelog =====');
  }

  /// Batch save or update multiple timelog records in cache using upsert/merge
  ///
  /// This is the preferred method for bulk operations as it uses batching
  /// and performs merge logic to preserve existing data while updating changed fields.
  static Future<void> batchSaveTimelogs({
    required String siteId,
    required List<Map<String, dynamic>> timelogDataList,
  }) async {
    final database = await db;

    if (timelogDataList.isEmpty) {
      debugPrint('[BATCH_SAVE_DB] No timelogs to save');
      return;
    }

    debugPrint('[BATCH_SAVE_DB] ===== START batchSaveTimelogs =====');
    debugPrint(
      '[BATCH_SAVE_DB] Processing ${timelogDataList.length} timelogs for site $siteId',
    );

    // Keep lookups bounded by key instead of loading all site rows into memory.
    final existingCache = <String, Map<String, dynamic>?>{};

    final batch = database.batch();
    int updateCount = 0;
    int insertCount = 0;

    for (final timelogData in timelogDataList) {
      final employeeId =
          (timelogData['employee_id'] ??
                  timelogData['companyID'] ??
                  timelogData['employeeID'] ??
                  timelogData['EMPLOYEEID'])
              ?.toString()
              .trim() ??
          '';

      if (employeeId.isEmpty) {
        debugPrint('[BATCH_SAVE_DB] Skipping timelog with empty employee_id');
        continue;
      }

      final timelogDate = _extractTimelogDate(timelogData);
      final key = timelogDate != null ? '$employeeId|$timelogDate' : employeeId;
      final existing = existingCache.containsKey(key)
          ? existingCache[key]
          : await _findExistingTimelogRow(
              database: database,
              siteId: siteId,
              employeeId: employeeId,
              timelogDate: timelogDate,
            );
      existingCache[key] = existing;

      Map<String, dynamic> merged = <String, dynamic>{};

      if (existing != null && existing['raw_json'] != null) {
        try {
          final decoded = jsonDecode(existing['raw_json'] as String);
          if (decoded is Map<String, dynamic>) {
            merged.addAll(decoded);
          }
        } catch (e) {
          debugPrint('[BATCH_SAVE_DB] Error decoding existing JSON: $e');
        }
      }

      // Merge: only overwrite with non-blank values
      for (final entry in timelogData.entries) {
        if (!_isBlank(entry.value)) {
          merged[entry.key] = entry.value;
        }
      }
      merged['employee_id'] ??= employeeId;

      final payload = jsonEncode(merged);

      if (existing != null) {
        // Update existing record
        final existingId = existing['id'];
        batch.update(
          'timelog_cache',
          {
            'site_id': siteId,
            'employee_id': employeeId,
            'timelog_date': timelogDate ?? _extractTimelogDate(merged),
            'raw_json': payload,
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );
        updateCount++;
      } else {
        // Insert new record
        batch.insert('timelog_cache', {
          'site_id': siteId,
          'employee_id': employeeId,
          'timelog_date': timelogDate,
          'raw_json': payload,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        insertCount++;
      }
    }

    await batch.commit(noResult: true);

    debugPrint('[BATCH_SAVE_DB] ===== COMPLETE =====');
    debugPrint('[BATCH_SAVE_DB] Updated: $updateCount, Inserted: $insertCount');
    debugPrint('[BATCH_SAVE_DB] ===== END batchSaveTimelogs =====');
  }

  static Future<Map<String, dynamic>?> _findExistingTimelogRow({
    required Database database,
    required String siteId,
    required String employeeId,
    required String? timelogDate,
  }) async {
    if (timelogDate != null && timelogDate.isNotEmpty) {
      final rows = await database.query(
        'timelog_cache',
        columns: ['id', 'raw_json'],
        where: 'site_id = ? AND employee_id = ? AND timelog_date = ?',
        whereArgs: [siteId, employeeId, timelogDate],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first;
      }

      // Back-compat lookup when old rows have null timelog_date.
      final fallbackRows = await database.query(
        'timelog_cache',
        columns: ['id', 'raw_json'],
        where: 'site_id = ? AND employee_id = ?',
        whereArgs: [siteId, employeeId],
        orderBy: 'id DESC',
        limit: 20,
      );

      for (final row in fallbackRows) {
        final raw = row['raw_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final date = _extractTimelogDate(decoded);
            if (date == timelogDate) {
              return row;
            }
          }
        } catch (_) {}
      }

      return null;
    }

    final rows = await database.query(
      'timelog_cache',
      columns: ['id', 'raw_json'],
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isNotEmpty ? rows.first : null;
  }

  /// Debug method to dump all timelog_cache records
  static Future<void> debugDumpAllTimelogs() async {
    final database = await db;
    final rows = await database.query('timelog_cache');
    print('[DEBUG_DUMP] ===== ALL TIMELOG_CACHE RECORDS =====');
    print('[DEBUG_DUMP] Total rows: ${rows.length}');
    for (final row in rows) {
      print(
        '[DEBUG_DUMP] id=${row['id']}, site_id=${row['site_id']}, employee_id=${row['employee_id']}',
      );
      print('[DEBUG_DUMP]   raw_json: ${row['raw_json']}');
    }
    print('[DEBUG_DUMP] ===== END DUMP =====');
  }

  /// Validate that timelog_cache only contains enrolled employees for a site
  static Future<Map<String, dynamic>> validateTimelogCache(
    String siteId,
  ) async {
    final database = await db;

    // Get enrolled employees
    final enrolledEmployees = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id'],
    );

    final enrolledIds = enrolledEmployees
        .map((row) => row['employee_id'].toString())
        .toSet();

    // Get cached timelog employees
    final cachedEmployees = await database.query(
      'timelog_cache',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id'],
      distinct: true,
    );

    final cachedIds = cachedEmployees
        .map((row) => row['employee_id'].toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    // Find discrepancies
    final unenrolledButCached = cachedIds.difference(enrolledIds);
    final enrolledButNotCached = enrolledIds.difference(cachedIds);

    final result = {
      'site_id': siteId,
      'enrolled_employees': enrolledIds.length,
      'cached_employees': cachedIds.length,
      'unenrolled_but_cached': unenrolledButCached.toList(),
      'enrolled_but_not_cached': enrolledButNotCached.toList(),
      'is_valid': unenrolledButCached.isEmpty,
    };

    debugPrint('[VALIDATE_CACHE] Site $siteId validation: $result');

    if (unenrolledButCached.isNotEmpty) {
      debugPrint(
        '[VALIDATE_CACHE] WARNING: Found ${unenrolledButCached.length} unenrolled employees with cached attendance!',
      );
    }

    return result;
  }

  /// Clean up invalid timelog cache entries (null employee_id or unenrolled employees)
  static Future<int> cleanupTimelogCache(String siteId) async {
    final database = await db;

    // Get enrolled employees
    final enrolledEmployees = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id'],
    );

    final enrolledIds = enrolledEmployees
        .map((row) => row['employee_id'].toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    int deleteCount = 0;

    if (enrolledIds.isEmpty) {
      // No enrolled employees - delete all records for this site
      deleteCount = await database.delete(
        'timelog_cache',
        where: 'site_id = ?',
        whereArgs: [siteId],
      );
      debugPrint(
        '[CLEANUP_CACHE] Deleted all $deleteCount records (no enrolled employees)',
      );
    } else {
      // Delete records with null employee_id
      final nullDeleted = await database.delete(
        'timelog_cache',
        where: 'site_id = ? AND employee_id IS NULL',
        whereArgs: [siteId],
      );

      // Delete records for unenrolled employees
      final placeholders = List.filled(enrolledIds.length, '?').join(', ');
      final unenrolledDeleted = await database.rawDelete(
        'DELETE FROM timelog_cache WHERE site_id = ? AND employee_id NOT IN ($placeholders)',
        [siteId, ...enrolledIds],
      );

      deleteCount = nullDeleted + unenrolledDeleted;
      debugPrint(
        '[CLEANUP_CACHE] Deleted $nullDeleted null records + $unenrolledDeleted unenrolled = $deleteCount total',
      );
    }

    return deleteCount;
  }

  static Future<int> getEmployeeCountBySite(String siteId) async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM employees WHERE site_id = ?',
      [siteId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  /// Get formatted attendance logs for display (proper Time In/Out detection)
  static Future<List<Map<String, dynamic>>> getAttendanceLogsForSite(
    String siteId,
  ) async {
    final database = await db;

    // Bound reads to avoid loading excessive raw_json rows into CursorWindow.
    final rows = await database.query(
      'timelog_cache',
      columns: ['id', 'employee_id', 'raw_json'],
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'id DESC',
      limit: _maxTimelogRowsRead,
    );

    // Get all employees for this site to lookup names
    final employeeRows = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );

    final employeeMap = <String, String>{};
    for (final empRow in employeeRows) {
      final empId = empRow['employee_id']?.toString() ?? '';
      final empName = empRow['employee_name']?.toString() ?? '';
      if (empId.isNotEmpty && empName.isNotEmpty) {
        employeeMap[empId] = empName;
      }
    }

    final logs = <Map<String, dynamic>>[];

    for (final row in rows) {
      try {
        final rawJson = row['raw_json'] as String?;
        if (rawJson == null || rawJson.isEmpty) continue;

        final timelogData = jsonDecode(rawJson) as Map<String, dynamic>;

        // If raw_json already contains the parsed API format, use it directly
        if (timelogData.containsKey('employee_id') &&
            timelogData.containsKey('type') &&
            timelogData.containsKey('timestamp')) {
          // Enrich with employee name from lookup
          final empId = timelogData['employee_id']?.toString() ?? '';
          if (empId.isNotEmpty && employeeMap.containsKey(empId)) {
            timelogData['employee_name'] = employeeMap[empId];
          }
          logs.add(timelogData);
        } else {
          // Otherwise, try to extract attendance entries from old format
          String? employeeId = row['employee_id'] as String?;
          if (employeeId == null || employeeId.isEmpty) {
            employeeId =
                (timelogData['employee_id'] ??
                        timelogData['companyID'] ??
                        timelogData['employeeID'] ??
                        timelogData['EMPLOYEEID'])
                    ?.toString();
          }

          if (employeeId != null && employeeId.isNotEmpty) {
            // Enrich with employee name from lookup
            if (employeeMap.containsKey(employeeId)) {
              timelogData['employee_name'] = employeeMap[employeeId];
            }
            final entries = _extractAttendanceEntries(timelogData, employeeId);
            logs.addAll(entries);
          }
        }
      } catch (e) {
        debugPrint('[LOGS] Error parsing timelog record ${row['id']}: $e');
      }
    }

    // Sort by timestamp (newest first)
    logs.sort((a, b) {
      final aTime =
          DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime(1970);
      final bTime =
          DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    debugPrint('[LOGS] Returning ${logs.length} total logs for site $siteId');

    return logs;
  }

  /// Extract individual attendance entries from a timelog record
  static List<Map<String, dynamic>> _extractAttendanceEntries(
    Map<String, dynamic> timelogData,
    String? employeeId,
  ) {
    final entries = <Map<String, dynamic>>[];

    // Extract employee name from the data or use ID
    String employeeName = 'Employee $employeeId';
    try {
      // Try to get employee details from the stored data
      if (timelogData.containsKey('employee_name')) {
        employeeName = timelogData['employee_name'].toString();
      } else if (employeeId != null && employeeId.isNotEmpty) {
        employeeName = 'Employee $employeeId';
      }
    } catch (e) {
      employeeName = 'Employee $employeeId';
    }

    // Create entries for each time slot that has data (support both camelCase and UPPERCASE)
    final timeSlots = [
      {
        'field': ['timeInMorning', 'TIMEINMORNING'],
        'type': 'Time In',
        'period': 'Morning',
      },
      {
        'field': ['timeOutMorning', 'TIMEOUTMORNING'],
        'type': 'Time Out',
        'period': 'Morning',
      },
      {
        'field': ['timeInAfternoon', 'TIMEINAFTERNOON'],
        'type': 'Time In',
        'period': 'Afternoon',
      },
      {
        'field': ['timeOutAfternoon', 'TIMEOUTAFTERNOON'],
        'type': 'Time Out',
        'period': 'Afternoon',
      },
    ];

    for (final slot in timeSlots) {
      String? timeValue;

      // Try both camelCase and UPPERCASE field names
      for (final fieldName in (slot['field'] as List<String>)) {
        timeValue = timelogData[fieldName]?.toString();
        if (!_isBlank(timeValue)) {
          break;
        }
      }

      if (!_isBlank(timeValue)) {
        // timeValue may be full datetime or HH:MM:SS with date on the record
        String timestamp = timeValue!;
        String? timeOnly;

        final logDate = _normalizeDate(
          timelogData['timeLogDate'] ??
              timelogData['timelog_date'] ??
              timelogData['timelog'],
        );

        try {
          // Convert "2026/02/20 08:38:42" to ISO format and extract parts
          if (timeValue.contains('/')) {
            final parts = timeValue.split(' ');
            if (parts.length >= 2) {
              final datePart = parts[0].replaceAll('/', '-');
              final timePart = parts[1];
              timestamp = '${datePart}T$timePart';
              timeOnly = timePart.substring(0, timePart.length >= 5 ? 5 : timePart.length);
            }
          } else if (logDate != null && timeValue.contains(':')) {
            timestamp = '${logDate}T$timeValue';
            timeOnly = timeValue.length >= 5 ? timeValue.substring(0, 5) : timeValue;
          }
        } catch (e) {
          debugPrint('[ATTENDANCE] Error parsing time: $e');
        }

        entries.add({
          'employee_id': employeeId ?? '',
          'employee_name': employeeName,
          'type': slot['type'],
          'period': slot['period'],
          'timestamp': timestamp,
          'time_only': timeOnly ?? timeValue,
        });
      }
    }

    return entries;
  }

  /// Save employees from API to local database using batch insert
  static Future<void> saveEmployeesForSite(
    String siteId,
    List<Map<String, dynamic>> employees,
  ) async {
    final database = await db;
    // Upsert employees instead of deleting all then inserting.
    // This uses batch inserts with ConflictAlgorithm.replace to perform
    // an insert-or-replace behaviour per row, keeping local enrollments intact.
    if (employees.isEmpty) {
      debugPrint('[LOCAL_DB] No employees to save for site $siteId');
      return;
    }

    final batch = database.batch();
    for (final employee in employees) {
      batch.insert('employees', {
        'fid': employee['fid'] ?? employee['finger_id'],
        'employee_id': employee['employee_id'],
        'employee_name': employee['employee_name'],
        'finger_template':
            employee['finger_template'] ??
            employee['template'] ??
            employee['raw_data'],
        'site_id': siteId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
    debugPrint(
      '[LOCAL_DB] Upserted ${employees.length} employees for site $siteId',
    );
  }

  /// Save attendance logs from API to local database using batch insert
  static Future<void> saveAttendanceLogsForSite(
    String siteId,
    List<Map<String, dynamic>> logs,
  ) async {
    if (logs.isEmpty) {
      debugPrint('[LOCAL_DB] No timelogs to save for site $siteId');
      return;
    }

    final database = await db;
    final registeredEmployees = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id'],
    );
    final registeredIds = registeredEmployees
        .map((row) => row['employee_id'].toString())
        .toSet();

    final filteredTimelogs = <Map<String, dynamic>>[];
    int skippedCount = 0;

    for (final log in logs) {
      final employeeId =
          (log['employee_id'] ??
                  log['employeeId'] ??
                  log['employeeID'] ??
                  log['EMPLOYEEID'] ??
                  log['companyID'])
              .toString()
              .trim();

      if (employeeId.isEmpty || !registeredIds.contains(employeeId)) {
        skippedCount++;
        continue;
      }

      final payload = Map<String, dynamic>.from(log);
      final dateOnly = _normalizeDate(
        payload['timelog'] ??
            payload['timeLogDate'] ??
            payload['timelog_date'] ??
            payload['datecaptured'] ??
            payload['datelog'] ??
            payload['date'] ??
            payload['timestamp'],
      );

      if (dateOnly != null) {
        payload['timelog_date'] = dateOnly;
        payload['timeLogDate'] ??= dateOnly;
        payload['timelog'] ??= dateOnly;
      }
      payload['employee_id'] = employeeId;

      final hasAnyAttendanceField =
          !_isBlank(payload['timeInMorning']) ||
          !_isBlank(payload['timeOutMorning']) ||
          !_isBlank(payload['timeInAfternoon']) ||
          !_isBlank(payload['timeOutAfternoon']) ||
          !_isBlank(payload['TIMEINMORNING']) ||
          !_isBlank(payload['TIMEOUTMORNING']) ||
          !_isBlank(payload['TIMEINAFTERNOON']) ||
          !_isBlank(payload['TIMEOUTAFTERNOON']);

      if (!hasAnyAttendanceField) {
        final type = payload['type']?.toString().toLowerCase() ?? '';
        final parsedTs = DateTime.tryParse(
          payload['timestamp']?.toString() ?? '',
        );
        final hh = parsedTs?.hour.toString().padLeft(2, '0');
        final mm = parsedTs?.minute.toString().padLeft(2, '0');
        final ss = parsedTs?.second.toString().padLeft(2, '0');
        final inferredTime =
            (payload['time_only']?.toString().trim().isNotEmpty ?? false)
            ? payload['time_only'].toString().trim()
            : ((hh != null && mm != null && ss != null) ? '$hh:$mm:$ss' : null);

        if (inferredTime != null && inferredTime.isNotEmpty) {
          String? fullDatetime;
          if (parsedTs != null) {
            fullDatetime =
                '${parsedTs.year}/${parsedTs.month.toString().padLeft(2, '0')}/${parsedTs.day.toString().padLeft(2, '0')} ${parsedTs.hour.toString().padLeft(2, '0')}:${parsedTs.minute.toString().padLeft(2, '0')}:${parsedTs.second.toString().padLeft(2, '0')}';
          } else if (dateOnly != null) {
            final parts = dateOnly.split('-');
            if (parts.length == 3) {
              fullDatetime =
                  '${parts[0]}/${parts[1].padLeft(2, '0')}/${parts[2].padLeft(2, '0')} $inferredTime';
            } else {
              fullDatetime = '$dateOnly $inferredTime';
            }
          } else {
            fullDatetime = inferredTime;
          }

          if (type.contains('out')) {
            payload['timeOutMorning'] = fullDatetime;
          } else {
            payload['timeInMorning'] = fullDatetime;
          }
          payload['timestamp'] ??= parsedTs?.toIso8601String() ?? fullDatetime;
          payload['timelog'] ??=
              dateOnly ?? _normalizeDate(payload['timestamp']);
        }
      }

      filteredTimelogs.add(payload);
    }

    await batchSaveTimelogs(siteId: siteId, timelogDataList: filteredTimelogs);
    debugPrint(
      '[LOCAL_DB] Merged ${filteredTimelogs.length} attendance logs for site $siteId (skipped $skippedCount)',
    );
  }

  /// Get attendance logs for a specific employee
  static Future<List<Map<String, dynamic>>> getAttendanceLogsForEmployee(
    String employeeId,
    String siteId,
  ) async {
    final database = await db;

    final timelogEntries = await database.query(
      'timelog_cache',
      columns: ['id', 'employee_id', 'raw_json'],
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
      orderBy: 'id DESC',
      limit: _maxTimelogRowsRead,
    );

    final logs = <Map<String, dynamic>>[];
    final seenDates = <String>{};

    for (final entry in timelogEntries) {
      try {
        final rawJson = entry['raw_json'] as String?;
        if (rawJson == null || rawJson.isEmpty) {
          debugPrint('[LOCAL_DB] Skipping entry with no raw_json');
          continue;
        }

        final timelogData = jsonDecode(rawJson) as Map<String, dynamic>;
        final rowDate = _normalizeDate(
          timelogData['timeLogDate'] ??
              timelogData['timelog_date'] ??
              timelogData['timelog'],
        );
        if (rowDate != null) {
          if (seenDates.contains(rowDate)) {
            continue;
          }
          seenDates.add(rowDate);
        }

        // Check if data is in new format (has 'type', 'time_only', 'timestamp' fields)
        if (timelogData.containsKey('type') ||
            timelogData.containsKey('time_only') ||
            timelogData.containsKey('timestamp')) {
          // New format: each entry is already a complete log record
          final empId =
              (timelogData['employee_id'] ??
                      timelogData['employeeId'] ??
                      timelogData['employeeID'] ??
                      timelogData['companyID'] ??
                      '')
                  ?.toString() ??
              '';
          if (empId.toLowerCase().trim() == employeeId.toLowerCase().trim()) {
            // Extract time from timestamp if time_only is missing
            String timeOnly =
                (timelogData['time_only'] ??
                        timelogData['timeOnly'] ??
                        timelogData['time'] ??
                        timelogData['Time'] ??
                        '')
                    ?.toString() ??
                '';
            String timestamp =
                (timelogData['timestamp'] ??
                        timelogData['timelog'] ??
                        timelogData['TIMELOG'] ??
                        timelogData['date'] ??
                        timelogData['datetime'] ??
                        '')
                    ?.toString() ??
                '';

            if (timeOnly.isEmpty && timestamp.isNotEmpty) {
              try {
                final dt = DateTime.parse(timestamp);
                timeOnly =
                    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } catch (e) {
                if (timestamp.contains(' ')) {
                  final parts = timestamp.split(' ');
                  if (parts.length >= 2) {
                    timeOnly = parts[1].substring(
                      0,
                      parts[1].length >= 5 ? 5 : parts[1].length,
                    );
                  }
                }
              }
            }

            logs.add({
              'employee_id': empId,
              'employee_name':
                  (timelogData['employee_name'] ??
                          timelogData['employeeName'] ??
                          timelogData['EMPLOYEE_NAME'] ??
                          timelogData['name'] ??
                          timelogData['Name'] ??
                          'Unknown')
                      ?.toString() ??
                  'Unknown',
              'type':
                  (timelogData['type'] ??
                          timelogData['attendance_type'] ??
                          timelogData['CODE'] ??
                          timelogData['code'] ??
                          '')
                      ?.toString() ??
                  '',
              'time_only': timeOnly,
              'timestamp': timestamp,
              'period':
                  (timelogData['period'] ??
                          timelogData['periodType'] ??
                          timelogData['shift'] ??
                          '')
                      ?.toString() ??
                  '',
            });
          }
        } else {
          // Old format: extract attendance entries from timelog record
          final entries = _extractAttendanceEntries(timelogData, employeeId);
          logs.addAll(entries);
        }
      } catch (e) {
        debugPrint('[LOCAL_DB] Error parsing timelog entry: $e');
      }
    }

    // Sort by timestamp (newest first)
    logs.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
      final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return logs;
  }

  static Future<void> pruneToSite(String siteId) async {
    final database = await db;

    await database.delete(
      'employees',
      where: 'site_id != ?',
      whereArgs: [siteId],
    );
    await database.delete(
      'employee_photos',
      where: 'site_id != ?',
      whereArgs: [siteId],
    );

    await database.delete(
      'timelog_cache',
      where: 'site_id != ?',
      whereArgs: [siteId],
    );

    await database.delete(
      'attendance_queue',
      where: 'site_id != ?',
      whereArgs: [siteId],
    );

    final pendingRequests = await database.query(
      'hris_queue',
      columns: ['id', 'query_params'],
      where: 'synced = ?',
      whereArgs: const [0],
    );

    for (final row in pendingRequests) {
      final id = row['id'] as int;
      final raw = row['query_params'] as String?;
      if (raw == null || raw.isEmpty) {
        await database.delete('hris_queue', where: 'id = ?', whereArgs: [id]);
        continue;
      }

      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final requestSiteId =
            decoded['siteID']?.toString() ??
            decoded['site_id']?.toString() ??
            decoded['siteId']?.toString();

        if (requestSiteId != null && requestSiteId != siteId) {
          await database.delete('hris_queue', where: 'id = ?', whereArgs: [id]);
        }
      } catch (_) {
        await database.delete('hris_queue', where: 'id = ?', whereArgs: [id]);
      }
    }
  }

  // ADDITIONAL METHODS FOR REPOSITORY PATTERN SUPPORT

  /// Insert attendance record into queue (alias for queueAttendance)
  static Future<void> insertAttendanceQueue({
    required String employeeId,
    required String employeeName,
    required String siteId,
    required String attendanceType,
    required DateTime timestamp,
  }) async {
    await queueAttendance(
      employeeId: employeeId,
      siteId: siteId,
      attendanceTime: timestamp.toIso8601String(),
    );
  }

  /// Get pending attendance records from queue (alias)
  static Future<List<Map<String, dynamic>>> getPendingAttendanceQueue() async {
    return await getPendingAttendance();
  }

  /// Sync pending HRIS queue to server (alias)
  static Future<void> syncPendingHrisQueue() async {
    final pendingRows = await getPendingHrisRequests();
    if (pendingRows.isEmpty) return;

    // Process pending requests (implementation from original home_page.dart)
    for (final row in pendingRows) {
      try {
        final id = row['id'];
        await markHrisRequestSynced(id);
      } catch (e) {
        debugPrint('Failed to sync HRIS request: $e');
      }
    }
  }

  /// Delete specific employee by ID and site
  static Future<void> deleteEmployee(String employeeId, String siteId) async {
    final database = await db;
    await database.delete(
      'employees',
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
    );
    await database.delete(
      'employee_photos',
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
    );
  }

  /// Delete only fingerprint templates for an employee (keeps photo intact).
  static Future<void> deleteEmployeeFingerprints({
    required String employeeId,
    required String siteId,
  }) async {
    final database = await db;
    await database.delete(
      'employees',
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
    );
  }

  /// Close the database (call on app exit if needed).
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // Missing methods needed by HomePageService
  static Future<void> cacheTimeLogs(
    String siteId,
    List<Map<String, dynamic>> logs,
  ) async {
    await saveAttendanceLogsForSite(siteId, logs);
  }

  static Future<List<Map<String, dynamic>>> getEmployeeLogsForDate(
    String employeeId,
    String siteId,
    DateTime date,
  ) async {
    final database = await db;
    final dayKey =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final rows = await database.query(
      'timelog_cache',
      columns: ['raw_json'],
      where: 'employee_id = ? AND site_id = ? AND timelog_date = ?',
      whereArgs: [employeeId, siteId, dayKey],
      orderBy: 'id DESC',
    );

    final entries = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['raw_json'] as String?;
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          entries.addAll(_extractAttendanceEntries(decoded, employeeId));
        }
      } catch (_) {}
    }

    return entries;
  }

  static Future<void> insertTimeLog(Map<String, dynamic> timelog) async {
    final siteId = (timelog['siteId'] ?? timelog['site_id'])?.toString().trim();
    final employeeId = (timelog['employeeId'] ?? timelog['employee_id'])
        ?.toString()
        .trim();

    if (siteId == null ||
        siteId.isEmpty ||
        employeeId == null ||
        employeeId.isEmpty) {
      throw Exception('insertTimeLog requires siteId and employeeId');
    }

    final payload = Map<String, dynamic>.from(timelog);
    payload['employee_id'] = employeeId;

    final timestampText = payload['timestamp']?.toString();
    final parsedTimestamp = timestampText != null
        ? DateTime.tryParse(timestampText)
        : null;
    final normalizedDate = _normalizeDate(
      payload['timelog'] ??
          payload['timeLogDate'] ??
          payload['timelog_date'] ??
          parsedTimestamp?.toIso8601String(),
    );
    if (normalizedDate != null) {
      payload['timelog_date'] = normalizedDate;
      payload['timeLogDate'] ??= normalizedDate;
      payload['timelog'] ??= normalizedDate;
    }

    // Format timestamp as expected by _extractAttendanceEntries: "YYYY/MM/DD HH:MM:SS"
    String? formattedTimestamp;
    if (parsedTimestamp != null) {
      final year = parsedTimestamp.year.toString();
      final month = parsedTimestamp.month.toString().padLeft(2, '0');
      final day = parsedTimestamp.day.toString().padLeft(2, '0');
      final hour = parsedTimestamp.hour.toString().padLeft(2, '0');
      final minute = parsedTimestamp.minute.toString().padLeft(2, '0');
      final second = parsedTimestamp.second.toString().padLeft(2, '0');
      formattedTimestamp = '$year/$month/$day $hour:$minute:$second';
    }

    final type = payload['type']?.toString().toLowerCase() ?? '';
    final hasAnyAttendanceField =
        !_isBlank(payload['timeInMorning']) ||
        !_isBlank(payload['timeOutMorning']) ||
        !_isBlank(payload['timeInAfternoon']) ||
        !_isBlank(payload['timeOutAfternoon']);

    if (!hasAnyAttendanceField && formattedTimestamp != null) {
      if (type.contains('out')) {
        payload['timeOutMorning'] = formattedTimestamp;
      } else {
        payload['timeInMorning'] = formattedTimestamp;
      }
    }

    await saveTimelog(
      siteId: siteId,
      employeeId: employeeId,
      timelogData: payload,
    );
  }

  static Future<void> deleteEmployeePhoto(
    String employeeId,
    String siteId,
  ) async {
    final db = await _open();
    await db.delete(
      'employee_photos',
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
    );
  }

  /// Save selected site preference (batch insert compatible)
  static Future<void> saveSelectedSite({
    required String siteId,
    required String? siteName,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      final batch = txn.batch();

      // Clear existing preference
      batch.delete('site_preferences');

      // Insert new preference
      batch.insert('site_preferences', {
        'id': 1,
        'selected_site_id': siteId,
        'selected_site_name': siteName ?? '',
        'last_updated': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await batch.commit(noResult: true);
    });

    debugPrint('[SITE_PREFS] Saved selected site: $siteId ($siteName)');
  }

  /// Get currently selected site
  static Future<Map<String, dynamic>?> getSelectedSite() async {
    final database = await db;
    final rows = await database.query(
      'site_preferences',
      orderBy: 'last_updated DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      debugPrint('[SITE_PREFS] No selected site found');
      return null;
    }

    debugPrint(
      '[SITE_PREFS] Retrieved selected site: ${rows.first['selected_site_id']}',
    );
    return rows.first;
  }

  /// Get currently selected site ID
  static Future<String?> getSelectedSiteId() async {
    final selectedSite = await getSelectedSite();
    return selectedSite?['selected_site_id']?.toString();
  }

  /// Batch insert operation: save selected site and sync with employee data
  static Future<void> batchSaveSiteWithEmployees({
    required String siteId,
    required String? siteName,
    required List<Map<String, dynamic>> employees,
  }) async {
    final database = await db;
    await database.transaction((txn) async {
      final batch = txn.batch();

      // Clear existing preferences and replace with new one
      batch.delete('site_preferences');
      batch.insert('site_preferences', {
        'id': 1,
        'selected_site_id': siteId,
        'selected_site_name': siteName ?? '',
        'last_updated': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Batch insert all employees for this site
      for (final emp in employees) {
        batch.insert('employees', {
          'fid': emp['fid'],
          'employee_id': emp['employee_id'],
          'employee_name': emp['employee_name'],
          'finger_template': emp['finger_template'],
          'site_id': siteId,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await batch.commit(noResult: true);
    });

    debugPrint(
      '[BATCH_SITE] Saved site preference and ${employees.length} employees',
    );
  }

  /// Clear selected site preference
  static Future<void> clearSelectedSite() async {
    final database = await db;
    await database.delete('site_preferences');
    debugPrint('[SITE_PREFS] Cleared selected site');
  }

  /// Save sites to local cache
  static Future<void> saveSitesToCache(List<Map<String, dynamic>> sites) async {
    final database = await db;
    await database.transaction((txn) async {
      final batch = txn.batch();
      
      // Clear existing sites cache
      batch.delete('sites_cache');
      
      // Insert new sites
      for (final site in sites) {
        final siteId = (site['site_id'] ?? site['SITEID'] ?? site['id'] ?? site['siteid'] ?? site['site_code'] ?? site['code'])?.toString() ?? '';
        final siteName = (site['site_name'] ?? site['SITENAME'] ?? site['name'] ?? site['site'] ?? site['title'])?.toString() ?? '';
        
        if (siteId.isNotEmpty && siteName.isNotEmpty) {
          batch.insert('sites_cache', {
            'site_id': siteId,
            'site_name': siteName,
            'last_updated': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      
      await batch.commit(noResult: true);
    });
    
    debugPrint('[SITES_CACHE] Saved ${sites.length} sites to local cache');
  }

  /// Get sites from local cache (OFFLINE-FIRST)
  static Future<List<Map<String, dynamic>>> getSitesFromCache() async {
    final database = await db;
    final rows = await database.query('sites_cache', orderBy: 'site_name ASC');
    
    debugPrint('[SITES_CACHE] Retrieved ${rows.length} sites from local cache');
    return rows;
  }

  static Future<List<Map<String, dynamic>>> fetchSitesFromApi() async {
    return _getApiRows('get/site/all');
  }

  static Future<List<Map<String, dynamic>>> fetchEmployeesBySiteFromApi(
    String siteId,
  ) async {
    return _getApiRows(
      'get/employee/perSite',
      queryParameters: {'siteID': siteId},
    );
  }

  static Future<List<Map<String, dynamic>>> fetchTimelogsBySiteFromApi(
    String siteId,
  ) async {
    return _getApiRows(
      'get/timelog/lastweek/perSite',
      queryParameters: {'siteID': siteId},
    );
  }

  static Future<Map<String, dynamic>> updateEmployeeThumbDetails({
    required String employeeId,
    required String leftFingerThumb,
    required String rightFingerThumb,
  }) async {
    return _postJson('update/employee/thumbDetails', {
      'employeeID': employeeId,
      'leftFingerThumb': leftFingerThumb,
      'rightFingerThumb': rightFingerThumb,
    });
  }

  static Future<Map<String, dynamic>> submitAttendanceTimeIn({
    required String? passedID,
    required String timeLogId,
    required String remarks,
    required String timeLog,
    required String timeInMorning,
    required String? timeInAfternoon,
    required String code,
  }) async {
    final rows = await _getApiRows(
      'update/timeLog/timeIn',
      queryParameters: {
        'passedID': passedID ?? 'null',
        'timelogID': timeLogId,
        'remarks': remarks,
        'timelog': timeLog,
        'timeInMorning': timeInMorning,
        'timeInAfternoon': timeInAfternoon,
        'code': code,
      },
    );
    return rows.isNotEmpty ? rows.first : _emptyJson();
  }

  static Future<Map<String, dynamic>> submitAttendanceTimeOut({
    required String? passedID,
    required String timeLogId,
    required String remarks,
    required String timeLog,
    required String timeOutMorning,
    required String? timeOutAfternoon,
    required String code,
  }) async {
    final rows = await _getApiRows(
      'update/timeLog/timeOut',
      queryParameters: {
        'passedID': passedID ?? 'null',
        'timelogID': timeLogId,
        'remarks': remarks,
        'timelog': timeLog,
        'timeOutMorning': timeOutMorning,
        'timeOutAfternoon': timeOutAfternoon,
        'code': code,
      },
    );
    return rows.isNotEmpty ? rows.first : _emptyJson();
  }

  static Future<Map<String, dynamic>> submitHrisLogTransaction({
    required String? passedID,
    required String companyID,
    required String datelog,
    required String logTime,
    required String logType,
    required String logId,
  }) async {
    final rows = await _getApiRows(
      'insert/hris/logs/transaction',
      queryParameters: {
        'passedID': passedID ?? 'null',
        'companyID': companyID,
        'datelog': datelog,
        'log_time': logTime,
        'log_type': logType,
        'logID': logId,
      },
    );
    return rows.isNotEmpty ? rows.first : _emptyJson();
  }

  static Future<Map<String, dynamic>> submitInsertTimeLog({
    required String siteId,
    required String employeeId,
    required String timeLogId,
    required String timeLog,
    required String remarks,
    required String schedule,
    required String timeInMorning,
    required String timeInAfternoon,
    required String dateCaptured,
    required String code,
  }) async {
    final rows = await _getApiRows(
      'insert/timeLog',
      queryParameters: {
        'siteID': siteId,
        'employeeID': employeeId,
        'timelogID': timeLogId,
        'timelog': timeLog,
        'remarks': remarks,
        'schedule': schedule,
        'timeinmorning': timeInMorning,
        'timeinafternoon': timeInAfternoon,
        'datecaptured': dateCaptured,
        'code': code,
      },
    );
    return rows.isNotEmpty ? rows.first : _emptyJson();
  }

  static Future<void> submitAttendanceSync({
    required String siteId,
    required String employeeId,
    required String timeLogId,
    required String timeLog,
    required String remarks,
    required String schedule,
    required String code,
    String? timeInMorning,
    String? timeOutMorning,
    String? timeInAfternoon,
    String? timeOutAfternoon,
  }) async {
    final logTime = _militaryTimeFromDateTimeString(timeLog);
    final isTimeOut = code.toUpperCase().startsWith('OUT');

    await submitHrisLogTransaction(
      passedID: null,
      companyID: employeeId,
      datelog: timeLog,
      logTime: logTime,
      logType: code,
      logId: timeLogId,
    );

    await submitInsertTimeLog(
      siteId: siteId,
      employeeId: employeeId,
      timeLogId: timeLogId,
      timeLog: timeLog,
      remarks: remarks,
      schedule: schedule,
      timeInMorning: timeInMorning ?? '',
      timeInAfternoon: timeInAfternoon ?? '',
      dateCaptured: timeLog,
      code: code,
    );

    if (isTimeOut) {
      await submitAttendanceTimeOut(
        passedID: null,
        timeLogId: timeLogId,
        remarks: remarks,
        timeLog: timeLog,
        timeOutMorning: timeOutMorning ?? '',
        timeOutAfternoon: timeOutAfternoon,
        code: code,
      );
    } else {
      await submitAttendanceTimeIn(
        passedID: null,
        timeLogId: timeLogId,
        remarks: remarks,
        timeLog: timeLog,
        timeInMorning: timeInMorning ?? '',
        timeInAfternoon: timeInAfternoon,
        code: code,
      );
    }
  }

  static String _militaryTimeFromDateTimeString(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      final parts = value.split(' ');
      if (parts.length >= 2) {
        return parts[1];
      }
      return value;
    }

    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    final second = parsed.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  static Future<List<Map<String, dynamic>>> getEmployeesWithPendingRecords(
    String siteId,
  ) async {
    final database = await db;
    return database.rawQuery(
      '''
      SELECT
        a.employee_id AS employee_id,
        MAX(COALESCE(e.employee_name, 'Unknown')) AS employee_name,
        COUNT(DISTINCT a.id) AS pending_count,
        MAX(a.attendance_time) AS last_attendance_time
      FROM attendance_queue a
      LEFT JOIN employees e
        ON e.employee_id = a.employee_id AND e.site_id = a.site_id
      WHERE a.site_id = ? AND a.synced = 0
      GROUP BY a.employee_id
      ORDER BY pending_count DESC, last_attendance_time DESC
      ''',
      [siteId],
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingAttendanceByEmployee({
    required String employeeId,
    required String siteId,
  }) async {
    final database = await db;
    return database.rawQuery(
      '''
      SELECT
        a.id,
        a.employee_id,
        (
          SELECT e.employee_name
          FROM employees e
          WHERE e.employee_id = a.employee_id AND e.site_id = a.site_id
          LIMIT 1
        ) AS employee_name,
        a.attendance_time,
        a.record_type,
        a.payload_json,
        a.synced
      FROM attendance_queue a
      WHERE a.site_id = ? AND a.employee_id = ? AND a.synced = 0
      GROUP BY a.id
      ORDER BY a.id ASC
      ''',
      [siteId, employeeId],
    );
  }

  static Future<void> markMultipleAttendanceSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await database.rawUpdate(
      'UPDATE attendance_queue SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }
}
