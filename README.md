<p align="center">
  <img src="assets/logo.svg" width="96" height="96" alt="BusyBridge logo">
</p>
<h1 align="center">BusyBridge</h1>
<p align="center"><strong>Share your availability. Keep the details yours.</strong></p>
<p align="center">Apple Calendar → anonymous busy blocks → Google Calendar → Calendly</p>

A small macOS utility that keeps your booking availability in sync with your personal and work calendars. Runs locally every 5 minutes. No server, subscription, or separate Google API credentials.

- Copies occupied times, never event titles, descriptions, or participants.
- Merges overlapping events and reconciles moves and cancellations.
- Uses calendar accounts already connected to your Mac.

## Install

Requires **macOS 14+**, **Xcode Command Line Tools** (`xcode-select --install`) and **Python 3.8+**. Tested on macOS 26.3.1; other versions are unverified.

```sh
git clone https://github.com/aeshef/busybridge.git
cd busybridge
bash build.sh
python3 manage.py install
python3 manage.py authorize
python3 manage.py list
```

Allow **Full Calendar Access** when macOS asks. In Google Calendar, create a separate calendar named **BusyBridge**, then wait for it to appear in Apple Calendar.

## Connect & run

Use the IDs printed by `list`: the target's `source_id` for `--account`, its `id` for `--target`, and each input calendar's `id` for `--source`. These are **local macOS IDs**, not Google Calendar's web IDs.

```sh
python3 manage.py configure \
  --account GOOGLE_SOURCE_ID \
  --target BUSYBRIDGE_CALENDAR_ID \
  --source PERSONAL_CALENDAR_ID \
  --source WORK_CALENDAR_ID
python3 manage.py preview   # Counts only; no writes
python3 manage.py sync      # First sync
python3 manage.py enable    # Every 5 minutes + at login
```

Replace the uppercase placeholders. Repeat `--source` as needed. Add `--include-all-day` to block all-day events too. Current placeholder titles are **“Занято”** (Russian for “Busy”).

In **Calendly → Calendar settings**, add BusyBridge to **Calendars to check for conflicts**. Keep your regular calendar selected under **Calendar to add events to**. You can hide BusyBridge in Apple Calendar to avoid seeing duplicates.

## Manage

```sh
python3 manage.py status    # Last sync and background job
python3 manage.py disable   # Stop syncing; keep existing blocks
```

**Your Mac must be awake and logged in.** Sync covers the next 60 days and depends on macOS account sync. This is an early, locally built app, not a notarized installer.

[How it works, privacy & troubleshooting →](docs/guide.md)

## License

[MIT](LICENSE) © 2026 aeshef
