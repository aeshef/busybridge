# How BusyBridge works

`main.swift` reads calendar intervals through EventKit and writes managed blocks. `Planner.swift` merges intervals and computes changes, with tests. `build.sh` builds and locally signs the app. `manage.py` handles configuration and the user LaunchAgent.

## Privacy

Source titles, descriptions, locations and links are never copied. Only the current user's invitation response is checked; participant names and addresses are not exported. Google receives occupied times, a generic title, Busy status and a random ownership URL (`busybridge://managed/<UUID>`). This marker contains no source event data.

Overlapping and adjacent intervals are merged. Cancelled events, Free events and invitations declined by the current user are skipped. Unknown availability counts as busy. All-day events are optional. EventKit expands recurring events.

## Reconciliation

New blocks are written before obsolete blocks are removed. Removal requires two observations at least four minutes apart, so cancellations may take an extra cycle. Only blocks carrying this installation's ownership marker are changed. Missing source calendars stop writes. Managed blocks manually given attendees or recurrence rules also stop writes. Existing unrelated events are not modified. Past blocks remain in history.

## Local files

- App: `~/Applications/BusyBridge.app`
- Settings and last results: `~/Library/Application Support/BusyBridge/`
- Background job: `~/Library/LaunchAgents/local.busybridge.calendar.plist`

Configuration stores calendar IDs, the window and an ownership UUID. Results contain counts and status; `list` and `authorize` also include calendar names, never event titles. Pending removals store only managed target IDs and timestamps. These files are outside the repository.

## Troubleshooting

**New Google calendar missing?** Create it in Google Calendar on the web, enable its synchronization to macOS and refresh Apple Calendar. Do not add a read-only iCal subscription as the target.

**Calendly still offers occupied slots?** Check that blocks have arrived in Google, have Busy status, and that the target is selected for conflict checks in Calendly. Local readback alone does not prove cloud delivery. Leave new bookings directed to your regular Google calendar.

**Permission denied after rebuilding?** A replacement locally signed app may need Full Calendar Access again in System Settings → Privacy & Security → Calendars.

**No updates while asleep?** Expected: the LaunchAgent runs while logged in and awake. Source freshness depends on macOS account synchronization; this app cannot independently verify remote freshness.

**Need different sources or a new destination?** Disable the agent first. Configuration is deliberately not overwritten by `configure`. Review the existing config and plan cleanup before changing destinations; preserve the ownership UUID for the same target. Stopping the agent does not remove existing blocks.

**Testing:** `bash build.sh` runs interval and reconciliation tests without requesting calendar access. A manual `sync` verifies required blocks by local readback. Cloud delivery and booking availability need separate checks. Only macOS 26.3.1 has been tested so far.
