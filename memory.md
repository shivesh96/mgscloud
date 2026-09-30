# Project Memory

## Current state

The Flutter/Android app forwards SMS, notification, and configured IMAP email
events. The current database schema version is **5**. The implementation was
verified on 2026-09-30 with `flutter test` and a debug Android APK build.

## Email ownership and invariants

- `lib/services/email_reader_service.dart` owns real-time email delivery.
  It maintains one `_EmailIdleListener` per enabled `EmailConfigModel`, enters
  IMAP IDLE, renews it every 25 minutes, and retries a failed account after
  five seconds. One account's failure must not stop another listener.
- `email_accounts` is the canonical multi-account configuration table.
  `email_config` remains only as legacy input for the version-5 migration.
- `processed_email_events` is the canonical email dedupe table. Its primary
  key is `(account_id, uid_validity, uid)`. Never deduplicate mail using body,
  subject, OTP, or Message-ID alone: IMAP UIDs are scoped to an account and
  can be recycled when UIDVALIDITY changes.
- The email configuration UI is
  `lib/ui/config/email_config_screen.dart`; it supports add, edit, delete,
  enable/disable, and connection testing. Saving or deleting calls
  `refreshListeners()` to prevent duplicate connections.

## SMS and SIM invariants

- `SmsBroadcastReceiver` derives `event_id` from the incoming SMS envelope:
  sender, timestamp, subscription, slot, service centre, and body. This makes
  broadcast redelivery and application restarts idempotent while permitting a
  later message that contains the same OTP.
- SIM number-source configuration is stored per subscription in
  `sim_config.number_source`. `simNumberSourceOptions(slotIndex)` must expose
  only `Default SIM` and that slot's own auto-detect option; SIM 1 and SIM 2
  must never share or overwrite selection state.
- Active Android subscriptions are authoritative. `SimService` refreshes them
  when SIM data is read and removes local rows whose subscription IDs are no
  longer active. Never seed a placeholder SIM row: a device with one active
  SIM must show one configuration card.

## Test contract

- `test/email_config_model_test.dart` protects independent account identity.
- `test/sim_number_source_options_test.dart` protects the slot-specific SIM
  choices.
- `test/widget_test.dart` is deliberately device-service-free; database and
  platform-channel behavior require Android integration testing.

## Next useful validation

Run an Android-device test with two configured IMAP accounts and a forced
network interruption. Confirm that each listener resumes independently and
that a previously processed `(account_id, uid_validity, uid)` never creates a
second server event.
