# Message Cloud — Project State & Resume Document

**Last Updated**: October 1, 2026
**App Name**: Message Cloud (`msg_to_server`)
**Framework**: Flutter (Dart 3.x) + Native Android (Kotlin / API 24+)
**Current Status**: Clean Build, 0 Static Analysis Issues, 100% Test Pass Rate

---

## 1. Project Overview & Architecture

Message Cloud is a background message capture and forwarding engine designed for Android devices. It continuously captures:
- **SMS Messages**: Native broadcast receiver intercepting `SMS_RECEIVED`.
- **WhatsApp & Clones**: Notification listener intercepting WhatsApp, WhatsApp Business, GBWhatsApp, and OEM dual/parallel instances.
- **IMAP Emails**: Real-time push via IMAP IDLE connections renewed on a 12-minute heartbeat.

Captured events are:
1. Deduplicated by deterministic hash identity in `EventCoordinator`.
2. Parsed for OTP codes using configurable regex rules in `OtpParserService`.
3. Matched against user-number bindings in `AuthService`.
4. Dispatched to the configured server endpoint via WebSocket (with ACK verification) or HTTP REST fallback in `TransportManager`.

---

## 2. Directory & Component Map

| Path | Purpose |
|---|---|
| `lib/main.dart` | App entry point, DB init, startup SIM detection, and background service bootstrap. |
| `lib/ui/home/home_screen.dart` | Primary dashboard: live event stream, SIM/WhatsApp/Email statuses, service toggle, quick simulation dialog. |
| `lib/ui/config/sim_config_screen.dart` | SIM card management with dynamic single/multi SIM source selector. |
| `lib/ui/config/config_screen.dart` | Server endpoint configuration (HTTP/WebSocket, Auth mechanism, timeout, retries). |
| `lib/ui/permissions/permissions_screen.dart` | Runtime permission checker + OEM AutoStart / battery saver exemption launcher. |
| `lib/services/event_coordinator.dart` | Central ingestion pipeline: deduplication, SIM resolution, OTP parsing, DB persistence, dispatch. |
| `lib/services/transport_manager.dart` | Network transport: WebSocket with ACK and HTTP POST/GET fallback with retry queues. |
| `lib/services/background_service_manager.dart` | Foreground service controller keeping monitoring worker alive in background. |
| `lib/services/sim_service.dart` | Native SIM card detection, caching, and state synchronization. |
| `lib/services/email_reader_service.dart` | Multi-account IMAP IDLE background listener. |
| `lib/data/local/database/app_database.dart` | SQLite database schema with versioning and seed rules. |
| `lib/data/local/dao/sim_dao.dart` | SIM persistence maintaining user configuration across hardware scans. |
| `lib/data/local/dao/settings_dao.dart` | App settings persistence (server URL, forwarding mode, service toggle). |
| `android/.../SmsBroadcastReceiver.kt` | Native receiver with 10s `PARTIAL_WAKE_LOCK` for deep-sleep capture and multi-OEM slot extraction. |
| `android/.../EventBridge.kt` | Synchronous SQLite/SharedPreferences persistence bridge between native Android and Dart. |
| `android/.../MainActivity.kt` | MethodChannel host, notification channels, OEM auto-start intents. |

---

## 3. Key Design Decisions & Critical Rules

### A. SIM Configuration (Single vs. Multi SIM)
- **Single-SIM Device (`totalSims <= 1`)**:
  - Dropdown displays **only 1 option**: `SIM 1 (Auto Detect)`.
  - Number source automatically defaults to `'auto_detect'`.
- **Dual-SIM Device (`totalSims > 1`)**:
  - Dropdown displays **multiple options**: `Default SIM` and `SIM ${slotIndex + 1} (Auto Detect)`.
- **Carrier Empty MSISDN Fallback**:
  - Over 90% of global SIM cards do not store their phone number on the chip (`detectedNumber` is empty).
  - In `SimInfoModel.effectiveNumber`, if `numberSource == 'auto_detect'` and `detectedNumber` is empty, it falls back to `userPhoneNumber` (manually entered by user). If neither is present, it returns `'Not configured'`.
- **Payload Sanitization**:
  - `EventModel.toServerPayload()` strips literal `'Not configured'` strings and sends `null` to avoid backend validation errors.
- **Scan Persistence Rule (`AGENTS.md`)**:
  - `SimDao.saveOrUpdateSim()` MUST preserve `existingModel.numberSource` and `existingModel.enabled` during native scans.

### B. Message Delivery Pipeline
- **Default Forwarding Mode**:
  - `send_filtered_only` defaults to `0` (false, "All Messages").
  - All messages on ANY SIM are captured, stored in SQLite, and transmitted to the server.
- **Unauthenticated Server Delivery**:
  - Users can configure a custom server endpoint and stream messages without logging into an account on the central auth server.
  - `TransportManager` and `BackgroundServiceManager` allow active monitoring and forwarding whenever `server_url` is configured.

### C. Android Deep Sleep & OEM Background Execution
- **Partial WakeLock**: `SmsBroadcastReceiver.kt` acquires a 10-second `PARTIAL_WAKE_LOCK` upon `SMS_RECEIVED` broadcast arrival to keep the CPU running until the event is written to disk.
- **Persistence Guarantee**: `EventBridge.persistEvent()` uses synchronous `.commit()` rather than `.apply()` to prevent data loss if the system terminates the process during Doze.
- **OEM AutoStart**: `PermissionsScreen` detects Xiaomi (MIUI/HyperOS), Samsung (Device Care), Huawei (Startup), Oppo/Realme (ColorOS), Vivo (iQOO), and OnePlus to direct users to OEM auto-start whitelists.

### D. Sender & Destination Mobile Separation
- **Strict Separation**: In `EventCoordinator`, the receiving mobile (`targetMobile`) is strictly resolved from the device's hardware SIMs or user profile (`simNumber`, `userPhoneNumber`, active SIM fallback, or `currentUser.mobile`). It NEVER falls back to `effectiveSender`.
- **Payload Guarantee**: `EventModel.toServerPayload()` sends the external contact (whether alphanumeric like `VK-RAILRR-S` or numeric like `+919876543210`) in `'sender'`, and the receiving device SIM in `'mobile'`, guaranteeing consistent user binding and server routing.

### E. Orientation Lock
- Strict portrait orientation is locked at both the Flutter layer (`SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown])` in `main.dart`) and Android OS activity layer (`android:screenOrientation="portrait"` in `AndroidManifest.xml`).

---

## 4. Verification & Testing

### Commands
```bash
# Run static analysis
flutter analyze

# Run all unit tests
flutter test
```

### Verified Test Suites (`test/sim_number_source_options_test.dart`)
1. Single SIM offers only one option (`SIM 1 (Auto Detect)`).
2. Multiple SIMs offer multiple options (`Default SIM` and `SIM X (Auto Detect)`).
3. Active Android subscriptions are retained and stale rows pruned during refresh.
4. `SimInfoModel.copyWith` preserves `numberSource` and `enabled` across scans.
5. `SimInfoModel.effectiveNumber` falls back to `userPhoneNumber` when `detectedNumber` is empty.
6. `EventModel.toServerPayload` sanitizes `'Not configured'` values from JSON payloads.
7. Single-SIM phone resolves SMS with arbitrary `subId` (e.g. `subId: 1`) to the installed SIM (`subId: 4`) with phone number and slot `0`.
8. SMS from a phone number preserves numeric sender and uses receiving SIM for mobile.
9. Smoke test constructed without device-only sqflite dependency (`test/widget_test.dart`).
10. Email config serialization test (`test/email_config_model_test.dart`).


---

## 5. Instructions for Next Agent Resuming Work

1. Always check `AGENTS.md` and `ISSUES.md` before making architectural modifications.
2. Maintain zero warnings on `flutter analyze`.
3. If modifying any UI widget or method under `lib/`, follow the proactive hot reload rule if connected to a live session.
4. If testing on Android emulator or physical hardware, use the "Flash / Send Test Event" icon on `HomeScreen` or trigger SMS via adb:
   ```bash
   adb emu sms send <number> <message>
   ```
