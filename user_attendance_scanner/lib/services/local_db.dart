// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalDb {
  static Database? _db;
  static const String _dbFileName = 'biometric_scanner.db';
  static const String _legacyDbFileName = 'biometrics_scanner.db';
  static const String _windowsDbDirectory = r'C:\SQLiteDB';

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
        'CREATE INDEX IF NOT EXISTS idx_employees_site ON employees (site_id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employee_photos (
        employee_id TEXT NOT NULL,
        site_id TEXT NOT NULL,
        photo BLOB NOT NULL,
        PRIMARY KEY (employee_id, site_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_employee_photos_site ON employee_photos (site_id)');

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
        raw_json TEXT NOT NULL
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

    await _ensureTimelogCacheColumns(db);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_timelog_cache_lookup ON timelog_cache (site_id, employee_id, timelog_date)',
    );
  }

  static Future<void> _ensureTimelogCacheColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(timelog_cache)');
    final hasTimelogDate = cols.any((c) => c['name'] == 'timelog_date');
    if (!hasTimelogDate) {
      await db.execute('ALTER TABLE timelog_cache ADD COLUMN timelog_date TEXT');
    }
  }

  static bool _isBlank(dynamic v) {
    if (v == null) return true;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty || s.toLowerCase() == 'null';
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
    final raw = timelogData['timelog'] ??
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
      version: 4,
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
    await database.insert(
      'employees',
      {
        'fid': fid,
        'employee_id': employeeId,
        'employee_name': employeeName,
        'finger_template': template,
        'site_id': siteId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  
  /// Insert or replace an employee selfie photo.
  static Future<void> upsertEmployeePhoto({
    required String employeeId,
    required String siteId,
    required Uint8List photo,
  }) async {
    final database = await db;
    await database.insert(
      'employee_photos',
      {
        'employee_id': employeeId,
        'site_id': siteId,
        'photo': photo,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
        batch.insert(
          'employees',
          {
            'fid': row['fid'],
            'employee_id': row['employee_id'],
            'employee_name': row['employee_name'],
            'finger_template': row['finger_template'],
            'site_id': siteId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
      await txn.delete(
        'employees',
        where: 'site_id = ?',
        whereArgs: [siteId],
      );

      if (employees.isEmpty) {
        return;
      }

      final batch = txn.batch();
      for (final row in employees) {
        batch.insert(
          'employees',
          {
            'fid': row['fid'],
            'employee_id': row['employee_id'],
            'employee_name': row['employee_name'],
            'finger_template': row['finger_template'],
            'site_id': siteId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Fetch all employees for a given site.
  static Future<List<Map<String, dynamic>>> getEmployeesBySite(
      String siteId) async {
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
  }) async {
    final database = await db;
    return database.insert(
      'attendance_queue',
      {
        'employee_id': employeeId,
        'site_id': siteId,
        'attendance_time': attendanceTime,
        'synced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    return database.insert(
      'hris_queue',
      {
        'endpoint': endpoint,
        'query_params': jsonEncode(queryParams),
        'synced': 0,
      },
    );
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

    // Get list of employees registered/enrolled on THIS device for THIS site
    final registeredEmployees = await database.query(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
      columns: ['employee_id', 'employee_name'],
    );

    final registeredIds = registeredEmployees
        .map((row) => row['employee_id'].toString())
        .toSet();

    debugPrint('[TIMELOG_CACHE] ===== TIMELOG SYNC START =====');
    debugPrint('[TIMELOG_CACHE] Site $siteId has ${registeredIds.length} registered employees');
    debugPrint('[TIMELOG_CACHE] Registered employee IDs: $registeredIds');
    debugPrint('[TIMELOG_CACHE] API returned ${rows.length} timelog rows');

    if (rows.isEmpty) {
      debugPrint('[TIMELOG_CACHE] WARNING: API returned 0 rows. Check API endpoint and siteID.');
      return;
    }

    // Log first few API rows for debugging
    for (int i = 0; i < rows.take(3).length; i++) {
      debugPrint('[TIMELOG_CACHE] API row $i: ${rows[i]}');
    }

    int upsertCount = 0;
    int skippedCount = 0;
    final List<String> skippedEmployeeIds = [];

    for (final row in rows) {
      final employeeId = (row['employee_id'] ??
              row['companyID'] ??
              row['employeeID'] ??
              row['EMPLOYEEID'])
          ?.toString();

      if (employeeId == null || !registeredIds.contains(employeeId)) {
        if (employeeId != null) {
          skippedEmployeeIds.add(employeeId);
          skippedCount++;
          debugPrint(
              '[TIMELOG_CACHE] Skipping employee $employeeId (ID not in enrolled list)');
        }
        continue;
      }

      // Ensure the record carries a normalized date field we can match on.
      final timelogDate = _normalizeDate(
        row['timelog'] ?? row['timeLogDate'] ?? row['timelog_date'] ?? row['date'],
      );

      final payload = Map<String, dynamic>.from(row);
      if (timelogDate != null) {
        payload['timelog_date'] = timelogDate;
        payload['timeLogDate'] ??= timelogDate;
        payload['timelog'] ??= timelogDate;
      }

      await saveTimelog(
        siteId: siteId,
        employeeId: employeeId,
        timelogData: payload,
      );
      upsertCount++;
    }

    debugPrint('[TIMELOG_CACHE] ===== TIMELOG SYNC COMPLETE =====');
    debugPrint('[TIMELOG_CACHE] Upserted: $upsertCount records for enrolled employees');
    debugPrint('[TIMELOG_CACHE] Skipped: $skippedCount records - Employee IDs: $skippedEmployeeIds');
    if (skippedCount > 0) {
      debugPrint('[TIMELOG_CACHE] ACTION: Ensure these employees are enrolled/synced before fetching timelogs');
    }
  }

  static Future<Map<String, dynamic>?> getLatestTimelogForEmployee({
    required String siteId,
    required String employeeId,
  }) async {
    final database = await db;
    print('[GET_DB] Querying for siteId="$siteId" employeeId="$employeeId"');
    
    // First, let's see ALL records for this employee/site
    final allRows = await database.query(
      'timelog_cache',
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: "COALESCE(timelog_date, '') DESC, id DESC",
    );
    print('[GET_DB] Found ${allRows.length} total rows for this employee/site');
    for (int i = 0; i < allRows.length; i++) {
      final row = allRows[i];
      print('[GET_DB] Row $i: id=${row['id']}, raw_json=${row['raw_json']}');
    }
    
    // Now get the latest one
    final rows = await database.query(
      'timelog_cache',
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: "COALESCE(timelog_date, '') DESC, id DESC",
      limit: 1,
    );
    print('[GET_DB] Latest row query returned ${rows.length} rows');
    if (rows.isEmpty) return null;
    final raw = rows.first['raw_json'] as String?;
    print('[GET_DB] Raw JSON: $raw');
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    print('[GET_DB] Decoded: $decoded');
    return decoded is Map<String, dynamic> ? decoded : null;
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
        '[SAVE_DB] siteId="$siteId" employeeId="$employeeId" timelogDate="$timelogDate"');

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
  
  /// Debug method to dump all timelog_cache records
  static Future<void> debugDumpAllTimelogs() async {
    final database = await db;
    final rows = await database.query('timelog_cache');
    print('[DEBUG_DUMP] ===== ALL TIMELOG_CACHE RECORDS =====');
    print('[DEBUG_DUMP] Total rows: ${rows.length}');
    for (final row in rows) {
      print('[DEBUG_DUMP] id=${row['id']}, site_id=${row['site_id']}, employee_id=${row['employee_id']}');
      print('[DEBUG_DUMP]   raw_json: ${row['raw_json']}');
    }
    print('[DEBUG_DUMP] ===== END DUMP =====');
  }
  
  /// Validate that timelog_cache only contains enrolled employees for a site
  static Future<Map<String, dynamic>> validateTimelogCache(String siteId) async {
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
      debugPrint('[VALIDATE_CACHE] WARNING: Found ${unenrolledButCached.length} unenrolled employees with cached attendance!');
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
      debugPrint('[CLEANUP_CACHE] Deleted all $deleteCount records (no enrolled employees)');
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
      debugPrint('[CLEANUP_CACHE] Deleted $nullDeleted null records + $unenrolledDeleted unenrolled = $deleteCount total');
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
  static Future<List<Map<String, dynamic>>> getAttendanceLogsForSite(String siteId) async {
    final database = await db;

    // Get all timelog_cache entries for the site
    final rows = await database.query(
      'timelog_cache',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'id DESC',
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
            employeeId = (timelogData['employee_id'] ??
                         timelogData['companyID'] ??
                         timelogData['employeeID'] ??
                         timelogData['EMPLOYEEID'])?.toString();
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
      final aTime = DateTime.tryParse(a['timestamp']?.toString() ?? '') ?? DateTime(1970);
      final bTime = DateTime.tryParse(b['timestamp']?.toString() ?? '') ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    debugPrint('[LOGS] Returning ${logs.length} total logs for site $siteId');

    return logs;
  }
  
  /// Extract individual attendance entries from a timelog record
  static List<Map<String, dynamic>> _extractAttendanceEntries(
    Map<String, dynamic> timelogData,
    String? employeeId
  ) {
    final entries = <Map<String, dynamic>>[];
    final date = timelogData['timeLogDate'] ??
                 timelogData['timelog'] ??
                 timelogData['TIMELOG'] ??
                 timelogData['DATECAPTURED'] ??
                 '';

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
      {'field': ['timeInMorning', 'TIMEINMORNING'], 'type': 'Time In', 'period': 'Morning'},
      {'field': ['timeOutMorning', 'TIMEOUTMORNING'], 'type': 'Time Out', 'period': 'Morning'},
      {'field': ['timeInAfternoon', 'TIMEINAFTERNOON'], 'type': 'Time In', 'period': 'Afternoon'},
      {'field': ['timeOutAfternoon', 'TIMEOUTAFTERNOON'], 'type': 'Time Out', 'period': 'Afternoon'},
    ];

    for (final slot in timeSlots) {
      String? timeValue;

      // Try both camelCase and UPPERCASE field names
      for (final fieldName in (slot['field'] as List<String>)) {
        timeValue = timelogData[fieldName]?.toString();
        if (timeValue != null && timeValue.isNotEmpty && timeValue != 'null') {
          break;
        }
      }

      if (timeValue != null && timeValue.isNotEmpty && timeValue != 'null') {
        // timeValue already contains full datetime like "2026/02/20 08:38:42"
        // Parse it and store both date and time
        String timestamp = timeValue;
        String? timeOnly;

        try {
          // Convert "2026/02/20 08:38:42" to ISO format and extract parts
          if (timeValue.contains('/')) {
            // Format: 2026/02/20 08:38:42
            final parts = timeValue.split(' ');
            if (parts.length >= 2) {
              final datePart = parts[0].replaceAll('/', '-'); // 2026-02-20
              final timePart = parts[1]; // 08:38:42
              timestamp = '${datePart}T$timePart';
              timeOnly = timePart.substring(0, 5); // HH:MM
            }
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
  static Future<void> saveEmployeesForSite(String siteId, List<Map<String, dynamic>> employees) async {
    final database = await db;
    
    // Clear existing employees for this site to avoid duplicates
    await database.delete(
      'employees',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
    
    // Use batch insert for better performance
    final batch = database.batch();
    
    for (final employee in employees) {
      batch.insert('employees', {
        'employee_id': employee['employee_id'],
        'employee_name': employee['employee_name'],
        'site_id': siteId,
        'template': employee['template'] ?? employee['raw_data'],
        'fid': employee['fid'] ?? employee['finger_id'],
        'created_at': employee['created_at'] ?? DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
    
    final results = await batch.commit();
    debugPrint('[LOCAL_DB] Saved ${results.length} employees for site $siteId');
  }

  /// Save attendance logs from API to local database using batch insert
  static Future<void> saveAttendanceLogsForSite(String siteId, List<Map<String, dynamic>> logs) async {
    final database = await db;
    
    // Clear existing timelog_cache for this site to avoid duplicates
    await database.delete(
      'timelog_cache',
      where: 'site_id = ?',
      whereArgs: [siteId],
    );

    // Prepare batch insert with all employee timelogs
    final batch = database.batch();
    int mergedCount = 0;
    int skippedCount = 0;

    for (final log in logs) {
      final employeeId = (log['employee_id'] ??
              log['employeeId'] ??
              log['employeeID'] ??
              log['EMPLOYEEID'] ??
              log['companyID'])
          ?.toString()
          .trim();

      if (employeeId == null || employeeId.isEmpty) {
        skippedCount++;
        continue;
      }

      // Prepare the complete payload with all timelog data
      final payload = Map<String, dynamic>.from(log);
      
      // Normalize and set date fields
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

      // Ensure we have time fields (check both camelCase and UPPERCASE)
      final hasAnyAttendanceField = !_isBlank(payload['timeInMorning']) ||
          !_isBlank(payload['timeOutMorning']) ||
          !_isBlank(payload['timeInAfternoon']) ||
          !_isBlank(payload['timeOutAfternoon']) ||
          !_isBlank(payload['TIMEINMORNING']) ||
          !_isBlank(payload['TIMEOUTMORNING']) ||
          !_isBlank(payload['TIMEINAFTERNOON']) ||
          !_isBlank(payload['TIMEOUTAFTERNOON']);
      if (!hasAnyAttendanceField) {
        final type = payload['type']?.toString().toLowerCase() ?? '';
        final parsedTs = DateTime.tryParse(payload['timestamp']?.toString() ?? '');
        final hh = parsedTs?.hour.toString().padLeft(2, '0');
        final mm = parsedTs?.minute.toString().padLeft(2, '0');
        final ss = parsedTs?.second.toString().padLeft(2, '0');
        final inferredTime = (payload['time_only']?.toString().trim().isNotEmpty ?? false)
            ? payload['time_only'].toString().trim()
            : ((hh != null && mm != null && ss != null) ? '$hh:$mm:$ss' : null);
        if (inferredTime != null && inferredTime.isNotEmpty) {
          if (type.contains('out')) {
            payload['timeOutMorning'] = inferredTime;
          } else {
            payload['timeInMorning'] = inferredTime;
          }
        }
      }

      // Insert using batch with complete data in raw_json
      batch.insert('timelog_cache', {
        'site_id': siteId,
        'employee_id': employeeId,
        'timelog_date': dateOnly ?? DateTime.now().toIso8601String(),
        'raw_json': jsonEncode(payload), // Store all timelog data as JSON
      });

      mergedCount++;
    }

    // Execute batch insert
    await batch.commit(noResult: true);

    debugPrint(
      '[LOCAL_DB] Batch inserted $mergedCount attendance logs for site $siteId (skipped $skippedCount without employee_id)',
    );
  }

  /// Get attendance logs for a specific employee
  static Future<List<Map<String, dynamic>>> getAttendanceLogsForEmployee(String employeeId, String siteId) async {
    final database = await db;
    
    final timelogEntries = await database.query(
      'timelog_cache',
      where: 'employee_id = ? AND site_id = ?',
      whereArgs: [employeeId, siteId],
      orderBy: 'id DESC',
    );

    final logs = <Map<String, dynamic>>[];
    
    for (final entry in timelogEntries) {
      try {
        final rawJson = entry['raw_json'] as String?;
        if (rawJson == null || rawJson.isEmpty) {
          debugPrint('[LOCAL_DB] Skipping entry with no raw_json');
          continue;
        }
        
        final timelogData = jsonDecode(rawJson) as Map<String, dynamic>;
        
        // Check if data is in new format (has 'type', 'time_only', 'timestamp' fields)
        if (timelogData.containsKey('type') || timelogData.containsKey('time_only') || timelogData.containsKey('timestamp')) {
          // New format: each entry is already a complete log record
          final empId = (timelogData['employee_id'] ?? timelogData['employeeId'] ?? timelogData['employeeID'] ?? timelogData['companyID'] ?? '')?.toString() ?? '';
          if (empId.toLowerCase().trim() == employeeId.toLowerCase().trim()) {
            // Extract time from timestamp if time_only is missing
            String timeOnly = (timelogData['time_only'] ?? timelogData['timeOnly'] ?? timelogData['time'] ?? timelogData['Time'] ?? '')?.toString() ?? '';
            String timestamp = (timelogData['timestamp'] ?? timelogData['timelog'] ?? timelogData['TIMELOG'] ?? timelogData['date'] ?? timelogData['datetime'] ?? '')?.toString() ?? '';
            
            if (timeOnly.isEmpty && timestamp.isNotEmpty) {
              try {
                final dt = DateTime.parse(timestamp);
                timeOnly = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } catch (e) {
                if (timestamp.contains(' ')) {
                  final parts = timestamp.split(' ');
                  if (parts.length >= 2) {
                    timeOnly = parts[1].substring(0, parts[1].length >= 5 ? 5 : parts[1].length);
                  }
                }
              }
            }
            
            logs.add({
              'employee_id': empId,
              'employee_name': (timelogData['employee_name'] ?? timelogData['employeeName'] ?? timelogData['EMPLOYEE_NAME'] ?? timelogData['name'] ?? timelogData['Name'] ?? 'Unknown')?.toString() ?? 'Unknown',
              'type': (timelogData['type'] ?? timelogData['attendance_type'] ?? timelogData['CODE'] ?? timelogData['code'] ?? '')?.toString() ?? '',
              'time_only': timeOnly,
              'timestamp': timestamp,
              'period': (timelogData['period'] ?? timelogData['periodType'] ?? timelogData['shift'] ?? '')?.toString() ?? '',
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

        final requestSiteId = decoded['siteID']?.toString() ??
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
  static Future<void> cacheTimeLogs(String siteId, List<Map<String, dynamic>> logs) async {
    await saveAttendanceLogsForSite(siteId, logs);
  }

  static Future<List<Map<String, dynamic>>> getEmployeeLogsForDate(String employeeId, String siteId, DateTime date) async {
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
    final employeeId =
        (timelog['employeeId'] ?? timelog['employee_id'])?.toString().trim();

    if (siteId == null || siteId.isEmpty || employeeId == null || employeeId.isEmpty) {
      throw Exception('insertTimeLog requires siteId and employeeId');
    }

    final payload = Map<String, dynamic>.from(timelog);
    payload['employee_id'] = employeeId;

    final timestampText = payload['timestamp']?.toString();
    final parsedTimestamp =
        timestampText != null ? DateTime.tryParse(timestampText) : null;
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

    final hour = parsedTimestamp?.hour.toString().padLeft(2, '0');
    final minute = parsedTimestamp?.minute.toString().padLeft(2, '0');
    final second = parsedTimestamp?.second.toString().padLeft(2, '0');
    final timeOnly =
        (hour != null && minute != null && second != null) ? '$hour:$minute:$second' : null;

    final type = payload['type']?.toString().toLowerCase() ?? '';
    final hasAnyAttendanceField = !_isBlank(payload['timeInMorning']) ||
        !_isBlank(payload['timeOutMorning']) ||
        !_isBlank(payload['timeInAfternoon']) ||
        !_isBlank(payload['timeOutAfternoon']);

    if (!hasAnyAttendanceField && timeOnly != null) {
      if (type.contains('out')) {
        payload['timeOutMorning'] = timeOnly;
      } else {
        payload['timeInMorning'] = timeOnly;
      }
    }

    await saveTimelog(
      siteId: siteId,
      employeeId: employeeId,
      timelogData: payload,
    );
  }

  static Future<void> deleteEmployeePhoto(String employeeId, String siteId) async {
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
      batch.insert(
        'site_preferences',
        {
          'id': 1,
          'selected_site_id': siteId,
          'selected_site_name': siteName ?? '',
          'last_updated': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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

    debugPrint('[SITE_PREFS] Retrieved selected site: ${rows.first['selected_site_id']}');
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
      batch.insert(
        'site_preferences',
        {
          'id': 1,
          'selected_site_id': siteId,
          'selected_site_name': siteName ?? '',
          'last_updated': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Batch insert all employees for this site
      for (final emp in employees) {
        batch.insert(
          'employees',
          {
            'fid': emp['fid'],
            'employee_id': emp['employee_id'],
            'employee_name': emp['employee_name'],
            'finger_template': emp['finger_template'],
            'site_id': siteId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });

    debugPrint('[BATCH_SITE] Saved site preference and ${employees.length} employees');
  }

  /// Clear selected site preference
  static Future<void> clearSelectedSite() async {
    final database = await db;
    await database.delete('site_preferences');
    debugPrint('[SITE_PREFS] Cleared selected site');
  }
}
