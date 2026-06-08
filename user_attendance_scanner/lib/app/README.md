# App structure (GetX)

Matches the modular layout: **data**, **modules**, **routes**, **core**.

```
lib/
  main.dart
  zkfp/                          # Device SDK (platform)
  app/
    bindings/
      app_binding.dart           # Global DI
      emergency_binding.dart
    core/
      values/                      # api_config, date_time_formats
      utils/                       # hris_log, responsive, …
      widgets/                     # Shared UI + animations/
    data/
      api/                         # hris_api.dart — config + endpoints + HTTP client
      models/                      # employee, attendance, site, scan_result
      providers/                   # re-exports api/hris_api.dart
      services/                    # LocalDb, DeviceService, sync, repositories
    modules/
      splash/
        bindings/
        controllers/
        views/
      home/
        bindings/
        controllers/
        views/                     # home_page, dashboard, navigation_drawer
      enrollment/
        bindings/
        controllers/
        views/
      time_logs/
        bindings/
        controllers/
        views/
      database/
        bindings/
        controllers/
        views/
    routes/
      app_pages.dart
      app_routes.dart
      route_observer.dart
```

## Feature map

| Feature | Module path |
|---------|-------------|
| Portal / site scanner | `app/modules/home/` |
| Per-employee dashboard | `app/modules/home/views/dashboard_page.dart` |
| Fingerprint enrollment | `app/modules/enrollment/` |
| Time logs (scan auth only here) | `app/modules/time_logs/` |
| Offline DB / employee list | `app/modules/database/` |
| Splash / loading | `app/modules/splash/` |

## Data flow

Scan → `LocalDb` + queue → `PendingUploadService` → `PendingSyncService` → `HrisApiProvider` (see `app/data/api/hris_api.dart`).
