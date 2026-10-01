
# Message Cloud — AI Agent Project Guidelines

## Project Overview

- **App Name**: **Message Cloud** (Package / Directory: `msg_to_server`)
- **Framework**: Flutter (Dart) + Native Android (Kotlin)
- **Description**: Background monitoring application that captures incoming SMS messages, WhatsApp notifications, and IMAP emails in real-time and securely forwards them to configured server endpoints via HTTP/WebSocket.

---

## App Name & Branding Guidelines

- Always refer to and display the application as **"Message Cloud"** in UI titles, AppBars, dialogs, system notifications, and Android notification channels.
- Main entry point: `lib/main.dart` -> `MaterialApp(title: 'Message Cloud')`
- Android Label: `android:label="Message Cloud"` in `AndroidManifest.xml`

---

## Key Architecture & Core Services

### 1. Flutter Layer (`lib/`)

- `lib/main.dart`: App initialization & SQLite DB setup.
- `lib/ui/home/home_screen.dart`: Main dashboard displaying live event stream, SIM status, and service controls.
- `lib/services/event_coordinator.dart`: Central pipeline for event deduplication, OTP extraction, user binding matching, and transport dispatch.
- `lib/services/background_service_manager.dart`: Manages `flutter_background_service` foreground worker (`msg_to_server_channel`).
- `lib/services/email_reader_service.dart`: Manages long-lived IMAP IDLE connections per enabled email account. Keeps renewal timer at **12 minutes** to prevent NAT/firewall drops.
- `lib/services/sim_service.dart`: Manages active SIM card detection and user configuration settings.

### 2. Data Persistence (`lib/data/local/`)

- `dao/sim_dao.dart`: Stores SIM card slot configurations.
  > ⚠️ **CRITICAL SIM FIX**: `saveOrUpdateSim()` MUST preserve `existingModel.numberSource` and `existingModel.enabled` during native SIM auto-detection scans so user dropdown selections (`SIM 1 (Auto Detect)`) do not revert to `'default'`.
  >
- `dao/settings_dao.dart`: Stores application settings (URL, protocol, timeout, retries, `service_enabled`, `send_filtered_only`).
  > ⚠️ **DEFAULT FORWARDING RULE**: `send_filtered_only` MUST default to `0` (false, "All Messages") so unauthenticated and non-OTP traffic is never discarded.

### 3. Native Android Layer (`android/app/src/main/kotlin/com/cybolite/msgserver/msg_to_server/`)

- `SmsBroadcastReceiver.kt`: Intercepts `android.provider.Telephony.SMS_RECEIVED`.
  > ⚠️ **BACKGROUND / SLEEP MODE REQUIREMENT**: Must acquire a `PARTIAL_WAKE_LOCK` (10s duration) upon SMS arrival so the CPU stays awake long enough to process and write the event to disk when the phone is in deep Doze/sleep mode.
  >
- `MsgNotificationListenerService.kt`: Intercepts WhatsApp & system notifications.
- `EventBridge.kt`: Synchronously commits native events to `SharedPreferences` for consumption by Dart background workers.
- `MainActivity.kt`: Native MethodChannel handlers, notification channel setup (`Message Cloud Background Service`), and OEM auto-start intents.

---

## SIM Selection & Dropdown Rules

1. **Single SIM Installed (`totalSims <= 1`)**:
   - The UI MUST only present **1 option**: `SIM 1 (Auto Detect)`.
   - `_initControllers` and `detectAndSyncSims` must default single-SIM setups to `'auto_detect'`.
2. **Multiple SIMs Installed (`totalSims > 1`)**:
   - The UI MUST present multiple options: `Default SIM` and `SIM ${slotIndex + 1} (Auto Detect)`.
3. **Number Fallback in `SimInfoModel.effectiveNumber`**:
   - Under `auto_detect`, check `detectedNumber` first; if carrier SIM did not burn MSISDN to chip (empty string), fall back to `userPhoneNumber`. If both empty, return `'Not configured'`.
4. **Server Payload Hygiene**:
   - `EventModel.toServerPayload()` must strip literal `'Not configured'` strings and send `null` instead to prevent backend validation rejections.

---

## Background & Deep Sleep Execution Rules

1. **WAKELOCK**: Ensure background tasks and receivers hold partial wakelocks while saving and transmitting offline events.
2. **Battery Optimization**: Mandatory permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` must remain enabled.
3. **IMAP IDLE Heartbeat**: Keep IMAP IDLE renewal timers under 15 minutes (default 12 minutes).
4. **Guest & Unauthenticated Server Forwarding**:
   - `TransportManager.sendEvent` and `BackgroundServiceManager` must NOT kill or block message delivery if the user is unauthenticated, provided a `server_url` is configured.

---

## Agent Handoff & Resume Checklist

When picking up this codebase:
1. Run `flutter analyze` — MUST have 0 errors and 0 warnings.
2. Run `flutter test` — all tests in `test/` MUST pass.
3. Check `ISSUES.md` for historical bug context and resolved items.
4. Check `PROJECT_STATE.md` for end-to-end event lifecycle and architecture map.
5. When editing Dart files under `lib/`, execute `hot_reload` or `hot_restart` immediately after saving UI widgets or methods if an active app session is connected.
