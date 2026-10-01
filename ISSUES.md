
# Message Cloud — Project Issues & Tracking Board

## 🟢 Resolved Issues (This Session)

### [RESOLVED] Issue #001: App Rebranding to "Message Cloud"

- **Component**: App Config / UI / Android Manifest
- **Description**: App title changed from "MSG to Server" to "Message Cloud" across Flutter UI (`MaterialApp`, `HomeScreen` AppBars), background service initial notification, `AndroidManifest.xml`, and Kotlin notification channel (`MainActivity.kt`).
- **Status**: Resolved

---

### [RESOLVED] Issue #002: SIM Dropdown Selection Reverting to "Default SIM"

- **Component**: `SimDao` (`lib/data/local/dao/sim_dao.dart`) & `SimConfigScreen` (`lib/ui/config/sim_config_screen.dart`)
- **Root Cause**: `SimDao.saveOrUpdateSim()` was overwriting the stored `numberSource` value with default `'default'` during native SIM auto-sync scans. `_initControllers()` in UI used `??=` which prevented state updates when refreshed.
- **Fix**: Updated `saveOrUpdateSim()` to preserve `existingModel.numberSource` and `existingModel.enabled`. Updated `_initControllers()` to update state controllers directly.
- **Status**: Resolved

---

### [RESOLVED] Issue #003: SMS Not Capturing in Background & Deep Sleep Mode

- **Component**: `SmsBroadcastReceiver.kt` (`android/app/src/main/kotlin/com/cybolite/msgserver/msg_to_server/`)
- **Root Cause**: Android released the broadcast wake lock as soon as `onReceive()` returned, allowing the CPU to go back to sleep before the SMS event was written to disk or processed by the Dart background worker.
- **Fix**: Added a 10-second `PARTIAL_WAKE_LOCK` in `SmsBroadcastReceiver.kt` upon `SMS_RECEIVED` broadcast delivery.
- **Status**: Resolved

---

### [RESOLVED] Issue #004: Email IMAP IDLE Real-time Disconnections

- **Component**: `EmailReaderService` (`lib/services/email_reader_service.dart`)
- **Root Cause**: Cellular NAT firewalls and Android power saver dropped long-lived idle TCP sockets after 15–20 minutes of inactivity.
- **Fix**: Reduced IDLE renewal interval from 25 minutes to 12 minutes and added `ImapMailboxStatusEvent` listener.
- **Status**: Resolved

---

### [RESOLVED] Issue #005: Dual-SIM Real Device Verification & Multi-Slot Extraction

- **Component**: `SmsBroadcastReceiver.kt` / `event_coordinator.dart` / `SimService`
- **Root Cause**: Carrier & OEM extras varied widely across manufacturers (Samsung using `phone`, MediaTek using `slot_id`/`simId`, AOSP using `subscription`/`slot`). In addition, extras could be cast as numbers or strings, and fallback logic could misattribute SIM 2 events to SIM 1.
- **Fix**: Added comprehensive `getIntFromExtras` supporting Samsung (`phone`), MediaTek (`slot_id`, `sim_id`), Qualcomm/AOSP (`slot`, `subscription`, `android.telephony.extra.SLOT_INDEX`), with bidirectional lookup via `SubscriptionManager.getActiveSubscriptionInfoForSimSlotIndex`. Updated `EventCoordinator` to only fall back to `allSims.first` for single-SIM configs.
- **Status**: Resolved

---

### [RESOLVED] Issue #006: Vendor-Specific Battery Saver Exemption Prompts

- **Component**: `PermissionsScreen` / `NativeService` / `MainActivity.kt`
- **Root Cause**: OEMs with aggressive background task killers (Xiaomi MIUI/HyperOS, Samsung Device Care, Huawei App Launch, Oppo/Realme, Vivo/iQOO, OnePlus) kill background services when the device locks or enters deep sleep despite standard battery optimization exemption.
- **Fix**: Added OEM detection (`getDeviceManufacturer`) and dedicated vendor intent handler (`openAutoStartSettings`) targeting MIUI AutoStart, Samsung Device Care, Huawei Startup, ColorOS Startup, and Vivo Power Manager, surfacing a high-priority AutoStart configuration prompt directly in `PermissionsScreen`.
- **Status**: Resolved

---

### [RESOLVED] Issue #007: Messages Dropped or Blocked from Server Forwarding

- **Component**: `TransportManager` / `BackgroundServiceManager` / `EventCoordinator` / `SettingsDao`
- **Root Cause**: 
  1. `TransportManager.sendEvent` checked `if (!await AuthService.instance.isAuthenticated())` before checking `serverUrl`, preventing guest users from transmitting events to their configured HTTP/WebSocket endpoints.
  2. `BackgroundServiceManager` terminated foreground workers when running unauthenticated even if `server_url` was configured.
  3. `EventCoordinator` discarded incoming events if `!sim.enabled`.
  4. Default `send_filtered_only` mode (`_forwardingMode = 'filtered'`) was dropping non-OTP SMS during debugging.
- **Fix**: Removed authentication hard-gate in `TransportManager` and `BackgroundServiceManager` when `server_url` is configured; removed `!sim.enabled` SMS discard in `EventCoordinator`; defaulted forwarding mode to "All Messages" (`send_filtered_only = 0`); and sanitized `'Not configured'` strings from payload contacts.
- **Status**: Resolved

---

### [RESOLVED] Issue #008: SIM Configuration Options for Single vs Multiple SIMs

- **Component**: `SimConfigScreen` (`lib/ui/config/sim_config_screen.dart`) & `SimService` (`lib/services/sim_service.dart`)
- **Root Cause**: `simNumberSourceOptions` always returned two choices (`Default SIM` and `SIM ${slotIndex + 1} (Auto Detect)`) even when only 1 SIM card was installed.
- **Fix**: Updated `simNumberSourceOptions(slotIndex, {int totalSims = 1})` to return only 1 option (`[('auto_detect', 'SIM ${slotIndex + 1} (Auto Detect)')]`) when `totalSims <= 1`, and multiple options when `totalSims > 1`. Single-SIM devices automatically default to `'auto_detect'`.
- **Status**: Resolved

---

### [RESOLVED] Issue #009: Single-SIM SMS Broadcasts with subId: 1 Failing to Resolve and Send

- **Component**: `SmsBroadcastReceiver.kt`, `EventCoordinator.dart`, `sim_number_source_options_test.dart`
- **Root Cause**:
  1. On single-SIM devices (e.g. OnePlus 11R CPH2447 with Jio True5G where active SIM has `subscription_id = 4` and `slot_index = 0`), incoming SMS broadcasts from the carrier/OEM telephony stack frequently deliver with `subId = 1` or `slot = 1`.
  2. Previously, `SmsBroadcastReceiver.kt` performed an exact lookup with `getActiveSubscriptionInfo(1)` which returned null, leaving `subId = 1` and `slot = 1`.
  3. `EventCoordinator.processIncomingNativeEvent` failed to match `_simDao.getSimBySubId(1)` and `_simDao.getSimBySlot(1)`. Its fallback checked `if (allSims.length == 1 && resolvedSlot <= 0)`, which evaluated to false because `resolvedSlot` was 1. Consequently, `simName` became `SIM 2` and `simNumber` became `null`.
  4. Without `simNumber`, the event payload lacked sender/SIM identity (`sim_number: null`, `mobile: null`), leading to missed deliveries and user-binding failures.
  5. In addition, R8 / ProGuard minification lacked `@Keep` annotations on `SmsBroadcastReceiver` and other native components.
- **Fix**:
  1. **Native Normalization in `SmsBroadcastReceiver.kt`**:
     - Added `@Keep` annotation to prevent R8 stripping.
     - Queried `SubscriptionManager.activeSubscriptionInfoList`. If `activeList.size == 1` (single-SIM phone), immediately normalizes `subId = activeList[0].subscriptionId` and `slotIndex = activeList[0].simSlotIndex`.
     - For multi-SIM phones (`activeList.size > 1`), accurately resolves exact subId, exact slot, 1-based subId (`subId - 1`), 1-based slot (`slotIndex - 1`), default SMS subId, and active SIM fallback.
     - Added real-time logcat tracing: `Log.i("MessageCloud", "SmsBroadcastReceiver: SMS received from $effectiveSender, subId: $subId, slot: $effectiveSlot, len: ${messageBody.length}")`.
  2. **Dart Pipeline Normalization in `EventCoordinator.dart`**:
     - Single-SIM phones (`allSims.length == 1`): Guarantees that EVERY incoming SMS event is mapped to `allSims.first` regardless of whether the raw broadcast reported `subId: 1`, `subId: 4`, or `simSlot: 1`.
     - Multi-SIM phones (`allSims.length > 1`): Maps exact subId -> 0-based slot -> 1-based subId -> 1-based slot -> first enabled SIM.
     - Always attaches `simNumber` (via `matchedSim.effectiveNumber`), `simName`, and `simSlot`.
  3. **Verification**:
     - Verified with unit tests in `test/sim_number_source_options_test.dart` (10/10 passed).
     - Built and deployed debug APK directly to the connected OnePlus device (`8118d753`).
     - Injected test SMS with `subscription_id = 1` and `sim_slot = 1` into the device's native pipeline; confirmed in SQLite DB that it was captured as event #52, attributed to `SIM1`, slot `0`, SIM number `+918292000123`, target mobile `+918292000123`, OTP parsed, and delivery status set to `sent`.
- **Status**: Resolved

---

### [RESOLVED] Issue #010: SMS from Numeric Senders (Phone Numbers) Not Forwarding & Orientation Lock Bypassed

- **Component**: `event_coordinator.dart`, `event_model.dart`, `main.dart`, `AndroidManifest.xml`, `MsgNotificationListenerService.kt`
- **Root Cause**:
  1. **Numeric Sender Payload & User Matching Failure**: In `lib/services/event_coordinator.dart`, the fallback logic for resolving `targetContact` contained:
     ```dart
     : (RegExp(r'^\+?[0-9\s\-()]{7,}$').hasMatch(effectiveSender) ? effectiveSender : null);
     ```
     When an SMS came from an alphanumeric header (e.g., `VK-RAILRR-S`), the regex was false, so `targetContact` properly remained null/device SIM. But when an SMS arrived from an actual phone number (e.g. `+919876543210`), `targetContact` was set to the *originating sender's* phone number.
     In `EventModel.toServerPayload()`, `cleanTarget` was given precedence over `cleanSimNum`:
     ```dart
     final effectiveMobile = cleanTarget ?? cleanUserPhone ?? cleanSimNum;
     ```
     This sent `mobile: +919876543210` (the sender's phone number) to the server instead of the device's receiving SIM number (`+918292000123`). In addition, `_authService.findBoundUserIdFor(+919876543210)` failed to match the logged-in user, yielding `userId: null`. The server rejected or misrouted the payload because `mobile` was not recognized as the user's registered SIM.
  2. **Device Orientation Lock Bypassed**: On devices with auto-rotate or when orientation was locked in portrait, tilting the phone still triggered landscape layout switching because neither Flutter's `SystemChrome.setPreferredOrientations` nor Android's `android:screenOrientation="portrait"` was set.
  3. **RCS / Google Messages Notification Extraction**: On Android 13–15, notifications from numeric contacts often bundle rich messaging objects under `NotificationCompat.MessagingStyle`, which were not unpacked when basic extras were empty.
- **Fix**:
  1. **Decoupled Receiving Phone Number from Originating Sender**:
     - In `event_coordinator.dart`, replaced the faulty regex fallback with receiving SIM resolution: always attempts active SIM number (`simNumber`), configured phone (`userPhoneNumber`), fallback active SIM (`allSims.first.effectiveNumber`), and authenticated user phone (`currentUser.mobile`). Never falls back to `effectiveSender`.
     - In `event_model.dart`, prioritized `cleanSimNum` first in `effectiveMobile = cleanSimNum ?? cleanTarget ?? cleanUserPhone` so the physical receiving SIM number is always placed in the server payload's `mobile` field, while the originating numeric sender is preserved untouched in `sender`.
  2. **Strict Portrait Orientation Lock**:
     - Added `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown])` to `lib/main.dart`.
     - Added `android:screenOrientation="portrait"` and `tools:ignore="LockedOrientationActivity"` to `.MainActivity` in `android/app/src/main/AndroidManifest.xml`.
  3. **AndroidX MessagingStyle Notification Support**:
     - Added `NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(notification)` in `MsgNotificationListenerService.kt` to unpack numeric sender messages from Google Messages / RCS.
  4. **Unit Test Coverage**:
     - Added unit test in `test/sim_number_source_options_test.dart` verifying that SMS from a numeric phone number retains the phone number in `sender`, sets the receiving device SIM in `mobile`, and marks `deliveryStatus: 'pending'`.
- **Status**: Resolved


