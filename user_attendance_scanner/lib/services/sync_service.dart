import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'local_db.dart';

class SyncService {
  static const String _baseUrl = 'https://fastdevs-api.com/HRIS_BIOMETRICS/biometricsapi/api/index.php';
  static const String _apiUsername = 'devuser';
  static const String _apiPassword = '12456789!';

  /// Sync all data with options dialog
  static Future<void> syncAllWithDialog(
    BuildContext context, {
    String? siteId,
    Function(String)? onStatusUpdate,
  }) async {
    final result = await showDialog<SyncOption>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A2240),
          title: const Text(
            'Sync Options',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSyncOption(
                icon: Icons.people,
                title: 'Employee List',
                subtitle: 'Sync employee database from server',
                onTap: () => Navigator.of(context).pop(SyncOption.employeeList),
              ),
              const SizedBox(height: 12),
              _buildSyncOption(
                icon: Icons.history,
                title: 'Employee Logs',
                subtitle: 'Sync time logs from server',
                onTap: () => Navigator.of(context).pop(SyncOption.employeeLogs),
              ),
              const SizedBox(height: 12),
              _buildSyncOption(
                icon: Icons.sync,
                title: 'Sync All',
                subtitle: 'Sync both employees and logs',
                onTap: () => Navigator.of(context).pop(SyncOption.all),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF3FA9F5)),
              ),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    try {
      onStatusUpdate?.call('Starting sync...');
      
      switch (result) {
        case SyncOption.employeeList:
          await _syncEmployeeList(siteId: siteId, onStatusUpdate: onStatusUpdate);
          break;
        case SyncOption.employeeLogs:
          await _syncEmployeeLogs(siteId: siteId, onStatusUpdate: onStatusUpdate);
          break;
        case SyncOption.all:
          await _syncEmployeeList(siteId: siteId, onStatusUpdate: onStatusUpdate);
          await _syncEmployeeLogs(siteId: siteId, onStatusUpdate: onStatusUpdate);
          break;
      }

      onStatusUpdate?.call('Sync completed successfully!');
      _showSuccessMessage(context, 'Data synchronized successfully!');
    } catch (e) {
      onStatusUpdate?.call('Sync failed: $e');
      _showErrorMessage(context, 'Sync failed: $e');
    }
  }

  static Widget _buildSyncOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A5C),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF3FA9F5),
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
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

  static Future<void> _syncEmployeeList({
    String? siteId,
    Function(String)? onStatusUpdate,
  }) async {
    final resolvedSiteId = siteId ?? await LocalDb.getSelectedSiteId();
    if (resolvedSiteId == null || resolvedSiteId.isEmpty) {
      throw Exception('No site selected');
    }

    onStatusUpdate?.call('Fetching employee list from server...');

    final rows = await LocalDb.fetchEmployeesBySiteFromApi(resolvedSiteId);
    onStatusUpdate?.call('Saving ${rows.length} employees to local database...');

    for (final row in rows) {
      final empId = LocalDb.employeeIdFromApiRow(row);
      if (empId == null) continue;
      final fields = LocalDb.profileFieldsFromApiRow(row);
      await LocalDb.upsertEmployeeProfile(
        employeeId: empId,
        siteId: resolvedSiteId,
        employeeName: fields['employee_name'],
        position: fields['position'],
        sbu: fields['sbu'],
      );
    }
  }

  static Future<void> _syncEmployeeLogs({
    String? siteId,
    Function(String)? onStatusUpdate,
  }) async {
    final resolvedSiteId = siteId ?? await LocalDb.getSelectedSiteId();
    if (resolvedSiteId == null || resolvedSiteId.isEmpty) {
      throw Exception('No site selected');
    }

    onStatusUpdate?.call(
      'Fetching full timelog history from server (per employee)...',
    );
    
    try {
      final count = await LocalDb.syncTimelogsFromApi(resolvedSiteId);
      
      if (count == 0) {
        debugPrint('[SYNC_SERVICE] Warning: No timelog records received from API for site $resolvedSiteId');
        onStatusUpdate?.call('No new timelog records found on server.');
      } else {
        debugPrint('[SYNC_SERVICE] Successfully synced $count timelog records for site $resolvedSiteId');
        onStatusUpdate?.call('Saved $count timelog records to local database.');
      }
      
      // Verify data was actually saved
      final savedCount = await LocalDb.getAttendanceCountForSite(resolvedSiteId);
      debugPrint('[SYNC_SERVICE] Verified: $savedCount total timelog records now in local database for site $resolvedSiteId');
    } catch (e) {
      debugPrint('[SYNC_SERVICE] Error syncing timelogs: $e');
      throw Exception('Failed to sync timelogs: $e');
    }
  }

  static void _showSuccessMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  static void _showErrorMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

enum SyncOption {
  employeeList,
  employeeLogs,
  all,
}
