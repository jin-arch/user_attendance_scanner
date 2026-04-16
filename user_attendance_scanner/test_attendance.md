# Attendance Scan Test

## Expected Behavior
1. **First scan**: TIME IN SUCCESS 
   - Saves record with timeInMorning = current time
   - Shows success modal
   - Navigates to dashboard

2. **Second scan** (within 5 minutes): ALREADY TIMED IN
   - Finds record from first scan
   - Calculates time difference < 5 minutes
   - Shows "already timed in" modal
   - Stays on dashboard

3. **Third scan** (after 5 minutes): TIME OUT SUCCESS
   - Finds record from first scan  
   - Calculates time difference >= 5 minutes
   - Updates record with timeOutMorning = current time
   - Shows "time out success" modal

## Issues Fixed

### 1. Employee Identification Failure (Fixed)
**Problem**: After first scan, returning to home page couldn't identify employees
**Root Cause**: Employee database not reloaded when returning from dashboard
**Fixes**:
- Added `didChangeDependencies` to reload employees when page regains focus
- Added fallback to reload employees if database is empty during scan
- Added scan loop restart mechanism after failed identification
- Enhanced logging to trace employee loading and identification process

### 2. Time Logs History Not Showing (Fixed)  
**Problem**: Attendance records not appearing in dashboard history
**Root Cause**: Database save/query timing issues and insufficient logging
**Fixes**:
- Increased delay from 300ms to 1000ms before loading history
- Added comprehensive database logging with `debugDumpAllTimelogs()`
- Enhanced saveTimelog to force INSERT for debugging
- Added verification queries after saves

### 3. Save Before Network Request (Fixed)
**Problem**: Records only saved if network request succeeded
**Root Cause**: saveTimelog called inside `if (primarySent)` block
**Fixes**:
- Moved saveTimelog BEFORE network requests in home_page.dart  
- Added 500ms delay after saves to ensure completion
- Added fallback logic for recent scans within 30 minutes

## Debug Output to Look For
When testing, look for these log patterns:

### Employee Loading:
```
[LOAD_EMPLOYEES] Loading employees for site: SITEID
[LOAD_EMPLOYEES] Found X employee rows in DB
[LOAD_EMPLOYEES] Successfully registered X employees
```

### Employee Identification:
```
[HOME_SCAN] Current employee DB size: X
[HOME_SCAN] Android identify result: found=true, fid=123
[HOME_SCAN] Employee lookup result: John Doe
```

### Database Operations:
```
[SAVE_DB] FORCE INSERTING new record (debugging)
[SAVE_DB] INSERT complete, id=X
[GET_DB] Found X total rows for this employee/site
[DEBUG_DUMP] Total rows: X
```

### History Loading:
```
[DASHBOARD_LOAD] siteId="X" employeeId="Y" 
[DASHBOARD_LOAD] Loaded X rows for employeeId="Y"
```

## Test Steps
1. Run app and select a site
2. Scan fingerprint → should show TIME IN SUCCESS with detailed logs
3. Check dashboard shows the attendance record in history
4. Return to home page (should reload employees automatically)
5. Scan again immediately → should show ALREADY TIMED IN  
6. Wait 5+ minutes, scan again → should show TIME OUT SUCCESS

If issues persist, the debug logs will show exactly where the failure occurs.