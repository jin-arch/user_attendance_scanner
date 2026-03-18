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
        raw_json TEXT NOT NULL
      )
    ''');
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
      version: 3,
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
    final batch = database.batch();
    batch.delete('timelog_cache', where: 'site_id = ?', whereArgs: [siteId]);

    for (final row in rows) {
      final employeeId =
          (row['employee_id'] ?? row['companyID'] ?? row['employeeID'])
              ?.toString();
      batch.insert('timelog_cache', {
        'site_id': siteId,
        'employee_id': employeeId,
        'raw_json': jsonEncode(row),
      });
    }

    await batch.commit(noResult: true);
  }

  static Future<Map<String, dynamic>?> getLatestTimelogForEmployee({
    required String siteId,
    required String employeeId,
  }) async {
    final database = await db;
    final rows = await database.query(
      'timelog_cache',
      where: 'site_id = ? AND employee_id = ?',
      whereArgs: [siteId, employeeId],
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['raw_json'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
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
      orderBy: 'id DESC',
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

  static Future<int> getEmployeeCountBySite(String siteId) async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS count FROM employees WHERE site_id = ?',
      [siteId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  static Future<void> pruneToSite(String siteId) async {
    final database = await db;

    await database.delete(
      'employees',
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

  /// Close the database (call on app exit if needed).
  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
