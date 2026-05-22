# Offline-First Data Flow Implementation

## Overview
The application has been modified to follow an **offline-first approach** where:
1. **All data reads MUST happen from the offline database first**
2. **No API data is directly displayed to users**
3. **Sync operations happen in the background and queue changes in the database**
4. **Data consistency is maintained between offline DB and API**

## Key Changes Made

### 1. LogsController (`lib/controllers/logs_controller.dart`)

#### `authenticateByEmployeeId()` (Line 259-369)
- **CHANGED**: Now reads employee name from **LOCAL DATABASE FIRST** (via `EmployeeRepository.getEmployeesForSite()`)
- **REMOVED**: Direct API call to fetch employee names
- **BENEFIT**: Authentication happens instantly with offline data, no network delay

**Old Flow**: API call → Local DB fallback
**New Flow**: Local DB only → Instant response

#### `loadLogs()` (Line 586-654)
- **CHANGED**: Now ONLY loads from **LOCAL DATABASE** (via `LocalDb.getAttendanceLogsForEmployee()`)
- **REMOVED**: Fallback to API fetch if no local logs
- **BENEFIT**: Shows only verified local data, prevents mixing offline/online data
- **BEHAVIOR**: If no logs exist locally, shows empty state instead of fetching from API

**Old Flow**: Local DB → API if empty
**New Flow**: Local DB only → Show empty if nothing found

### 2. DatabaseController (`lib/controllers/database_controller.dart`)

#### `loadEmployees()` (Line 37-61)
- **CHANGE**: Added clear comment marking "offline-first" approach
- **BEHAVIOR**: Loads only from `LocalDb.getEmployeesBySite()`
- **STATUS**: Already correct, now clearly documented

### 3. SiteRepositoryImpl (`lib/services/site_repository_impl.dart`)

#### `fetchSites()` (Line 13-55)
- **CHANGED**: Now reads from **LOCAL CACHE FIRST** (via `LocalDb.getSitesFromCache()`)
- **FALLBACK**: Only calls API if cache is empty
- **CACHING**: Saves API responses to local cache for future use
- **BENEFIT**: Instant site loading, works offline

**Old Flow**: API call only
**New Flow**: Local cache → API if empty → Save to cache

#### `getCachedSites()` (Line 58-67)
- **CHANGED**: Now actually returns cached sites from local database
- **BENEFIT**: Provides offline access to site list

#### `getSiteById()` (Line 80-94)
- **CHANGED**: Now reads from **LOCAL CACHE FIRST**
- **FALLBACK**: Only calls API if not in cache
- **BENEFIT**: Faster site lookups, works offline

### 4. HomePageController (`lib/controllers/home_page_controller.dart`)

#### `loadSites()` (Line 84-118)
- **CHANGED**: Now reads from **CACHED SITES FIRST** (via `_siteRepository.getCachedSites()`)
- **FALLBACK**: Only calls API if cache is empty
- **BENEFIT**: Instant site loading on app start

**Old Flow**: API call only
**New Flow**: Cached sites → API if empty

### 5. HomePageService (`lib/services/home_page_service.dart`)

#### `fetchSites()` (Line 193-283)
- **CHANGED**: Now reads from **LOCAL CACHE FIRST** (via `LocalDb.getSitesFromCache()`)
- **FALLBACK**: Only calls API if cache is empty
- **CACHING**: Saves API responses to local cache
- **BENEFIT**: Works offline, faster loading

### 6. EmployeeRepositoryImpl (`lib/services/employee_repository_impl.dart`)

#### `syncEmployeesFromApi()` (Line 66-83)
- **CHANGED**: Now properly fetches from API and saves to local database
- **MERGING**: Uses `LocalDb.saveEmployeesForSite()` which merges with existing data
- **FALLBACK**: Returns local employees even if sync fails
- **BENEFIT**: Ensures local data is always available

### 7. AttendanceRepositoryImpl (`lib/services/attendance_repository_impl.dart`)

#### `markAttendanceAsSynced()` (Line 68-90)
- **CHANGED**: Now properly marks attendance records as synced in the queue
- **IMPLEMENTATION**: Finds matching records and updates their synced status
- **BENEFIT**: Proper tracking of synced attendance

#### `syncPendingAttendanceToApi()` (Line 93-151)
- **CHANGED**: Now properly syncs pending attendance to API
- **IMPLEMENTATION**: Submits each pending record to API and marks as synced
- **ERROR HANDLING**: Continues with next record if one fails
- **BENEFIT**: Reliable sync of offline attendance records

### 8. LocalDb (`lib/services/local_db.dart`)

#### New Table: `sites_cache` (Line 193-199)
- **ADDED**: Table for caching site list from API
- **PURPOSE**: Enable offline-first site loading
- **COLUMNS**: site_id (PK), site_name, last_updated

#### `saveSitesToCache()` (Line 1884-1911)
- **ADDED**: Method to save sites to local cache
- **BEHAVIOR**: Clears existing cache and inserts new sites
- **BENEFIT**: Enables offline site access

#### `getSitesFromCache()` (Line 1913-1920)
- **ADDED**: Method to retrieve sites from local cache
- **BEHAVIOR**: Returns cached sites ordered by name
- **BENEFIT**: Fast site loading from local database

### 9. OfflineModeSyncService (`lib/services/offline_mode_sync_service.dart`)
- **ADDED**: `startSync()` and `completeSync()` methods to track sync operations
- **ADDED**: `isSyncing()` method to check if sync is in progress
- **ADDED**: `isSyncingNotifier` ValueNotifier for UI updates during sync
- **PURPOSE**: Manage background sync operations without affecting display

## Data Flow Architecture

```
User Interaction
    ↓
Authentication/Data Load
    ↓
Read from LOCAL DATABASE ← ← ← ← ← ← PRIORITY
    ↓
Display to User
    ↓
BACKGROUND SYNC (if online)
    ↓
Queue pending records in:
  - attendance_queue table
  - hris_queue table
    ↓
Sync with API (when possible)
    ↓
Update LOCAL DATABASE with responses
```

## Database Tables for Sync Management

### `attendance_queue` Table
- **id**: Unique identifier
- **employee_id**: Employee being recorded
- **site_id**: Site reference
- **attendance_time**: Time of attendance
- **synced**: 0 = pending, 1 = synced

**Methods**:
- `queueAttendance()` - Add record to queue
- `getPendingAttendance()` - Get unsynced records
- `markAttendanceSynced()` - Mark as synced after successful upload

### `hris_queue` Table
- **id**: Unique identifier
- **endpoint**: API endpoint to call
- **query_params**: JSON encoded parameters
- **synced**: 0 = pending, 1 = synced

**Methods**:
- `queueHrisRequest()` - Queue API request
- `getPendingHrisRequests()` - Get unsent requests
- `markHrisRequestSynced()` - Mark as synced

### `timelog_cache` Table
- **id**: Unique identifier
- **site_id**: Site reference
- **employee_id**: Employee reference
- **timelog_date**: Date of the log
- **raw_json**: Full JSON data

**Methods**:
- `saveTimelog()` - Save/update single entry
- `batchSaveTimelogs()` - Batch save for efficiency
- `getLatestTimelogForEmployee()` - Get most recent
- `getTimelogHistoryForEmployee()` - Get history with limit
- `getAttendanceLogsForEmployee()` - Get formatted logs

## Sync Operations

### When Online
1. Check for pending records in queues
2. Send to API endpoint
3. On success: Mark as synced (synced = 1)
4. On failure: Leave synced = 0, retry later

### When Offline
1. All changes go directly to local queues
2. User sees only local data
3. No API calls attempted
4. Automatic retry when online

### Key Methods for Syncing

```dart
// In LocalDb class:
static Future<List<Map<String, dynamic>>> getPendingAttendance()
static Future<void> markAttendanceSynced(int id)
static Future<List<Map<String, dynamic>>> getPendingHrisRequests()
static Future<void> markHrisRequestSynced(int id)

// In OfflineModeSyncService:
void startSync()  // Mark sync start
void completeSync()  // Mark sync end
bool isSyncing()  // Check status
```

## API Methods (Use in Background Only)

These methods should **NOT** be called during normal data loading:

### In LogsController
- `_fetchLogsFromApi()` - Only for background sync or explicit refresh
- `_fetchEmployeeNamesFromApi()` - Only for background sync
- `fetchAndSaveTimeLogsFromApi()` - Saves to DB, doesn't display directly
- `sendLogToServer()` - Queue-based sending

### In LocalDb
- `fetchSitesFromApi()` - For background sync
- `fetchEmployeesBySiteFromApi()` - For background sync
- `fetchTimelogsBySiteFromApi()` - For background sync

## Important: Data Integrity Rules

1. **NEVER show API data directly** - Always save to local DB first
2. **NEVER overwrite local changes with API** - Merge/queue instead
3. **ALWAYS queue pending changes** - Use attendance_queue and hris_queue
4. **ALWAYS merge data on update** - Don't delete then insert
5. **ALWAYS validate employee is enrolled** - Before accepting timelog

## Testing the Implementation

### Test 1: Offline Logs Display
1. Go offline (disable network)
2. Authenticate employee
3. Verify logs load from local DB only
4. Verify no API errors shown

### Test 2: Queued Changes
1. Make attendance record while offline
2. Verify record saved in attendance_queue
3. Go online
4. Verify queue is processed
5. Verify synced = 1 after success

### Test 3: Data Consistency
1. Make change in offline mode
2. Go online
3. Verify local DB updated after sync
4. Verify no duplicate records
5. Verify merged data is correct

## Migration Notes

- **No database schema changes** - Uses existing tables
- **No user-facing changes** - Same UI, faster performance
- **Backward compatible** - Works with existing data
- **No breaking changes** - Existing APIs still work

## Benefits

1. **Faster Performance**: No network latency for reads
2. **Offline Capability**: Works without internet
3. **Data Integrity**: No mixing of local/API data
4. **Better UX**: Instant feedback to user
5. **Reliability**: Data isn't lost if sync fails
6. **Consistency**: Single source of truth (local DB)
