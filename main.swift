import Foundation
import EventKit
import AppKit
import Darwin

umask(0o077)
let arguments = CommandLine.arguments
let mode = arguments.dropFirst().first ?? "list"
if mode == "self-test" { plannerTests(); print("planner tests passed"); exit(0) }
let fm = FileManager.default
let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BusyBridge")
try fm.createDirectory(at: root, withIntermediateDirectories: true)
let output = root.appendingPathComponent("\(mode)-result.json")
func writeJSON(_ value: Any, _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
}
func finish(_ result: [String: Any], code: Int32 = 0) -> Never {
    try? writeJSON(result.merging(["checked_at": ISO8601DateFormatter().string(from: Date())]) { a, _ in a }, output)
    exit(code)
}
func fail(_ reason: String) -> Never { finish(["status": "error", "reason": reason], code: 1) }
let lockFD = open(root.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
let store = EKEventStore()
if mode == "authorize" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)
    var completed = false
    store.requestFullAccessToEvents { _, _ in DispatchQueue.main.async { completed = true } }
    let deadline = Date().addingTimeInterval(55)
    while !completed && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
}
guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { fail("calendar_full_access_required") }
store.refreshSourcesIfNecessary()
let calendars = store.calendars(for: .event)
if mode == "list" || mode == "authorize" {
    finish(["status": "ready", "calendars": calendars.map { c in
        ["id": c.calendarIdentifier, "name": c.title, "source_id": c.source.sourceIdentifier,
         "source": c.source.title, "source_type": c.source.sourceType.rawValue,
         "writable": c.allowsContentModifications, "subscription": c.isSubscribed] as [String: Any]
    }])
}
// Creation requires an explicitly selected account; never infer Google from a default calendar.
if mode == "create-target" {
    guard arguments.count == 3,
          let source = store.sources.first(where: { $0.sourceIdentifier == arguments[2] }),
          source.sourceType == .calDAV else { fail("explicit_caldav_source_required") }
    let matches = calendars.filter { $0.source.sourceIdentifier == source.sourceIdentifier && $0.title == "Занятость" }
    guard matches.isEmpty else { fail("target_name_already_exists_select_existing_id") }
    let c = EKCalendar(for: .event, eventStore: store)
    c.title = "Занятость"; c.source = source
    do { try store.saveCalendar(c, commit: true) } catch { fail("target_creation_failed_check_before_retry") }
    finish(["status": "created", "target_id": c.calendarIdentifier])
}
struct Config: Codable {
    let sourceIDs: [String]
    let targetID: String
    let targetSourceID: String
    let days: Int
    let includeAllDay: Bool
    let owner: String
}
let configURL = root.appendingPathComponent("config.json")
guard let data = try? Data(contentsOf: configURL), let cfg = try? JSONDecoder().decode(Config.self, from: data),
      (1...180).contains(cfg.days), UUID(uuidString: cfg.owner) != nil,
      !cfg.sourceIDs.isEmpty, Set(cfg.sourceIDs).count == cfg.sourceIDs.count,
      !cfg.sourceIDs.contains(cfg.targetID) else { fail("valid_config_required") }
let sources = cfg.sourceIDs.compactMap { id in calendars.first { $0.calendarIdentifier == id } }
guard sources.count == cfg.sourceIDs.count else { fail("source_calendar_missing_no_changes") }
guard let target = calendars.first(where: { $0.calendarIdentifier == cfg.targetID }),
      target.source.sourceIdentifier == cfg.targetSourceID, target.source.sourceType == .calDAV,
      target.allowsContentModifications, target.supportedEventAvailabilities.contains(.busy) else {
    fail("target_missing_readonly_or_busy_unsupported")
}
guard mode == "preview" || mode == "sync" else { fail("unknown_mode") }
let now = Date()
let start = Calendar.current.startOfDay(for: now)
let end = Calendar.current.date(byAdding: .day, value: cfg.days, to: start)!
let marker = URL(string: "busybridge://managed/\(cfg.owner)")!
let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: sources))
// Never access source title, notes, participant names/addresses, location or URL.
let blocks = mergeBlocks(events.compactMap { event -> Block? in
    guard event.status != .canceled, event.availability != .free,
          cfg.includeAllDay || !event.isAllDay,
          event.endDate > now,
          event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true else { return nil }
    return Block(start: Int64(max(event.startDate, start).timeIntervalSince1970),
                 end: Int64(min(event.endDate, end).timeIntervalSince1970))
})
let existing = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [target]))
let owned = existing.filter { $0.url == marker && $0.endDate > now }
guard !owned.contains(where: { $0.hasRecurrenceRules || $0.hasAttendees }) else { fail("managed_block_manually_changed_no_writes") }
func key(_ e: EKEvent) -> String { Block(start: Int64(e.startDate.timeIntervalSince1970), end: Int64(e.endDate.timeIntervalSince1970)).key }
let diff = reconcile(blocks, owned.map { Block(start: Int64($0.startDate.timeIntervalSince1970), end: Int64($0.endDate.timeIntervalSince1970)) })
let stale = diff.stale.map { owned[$0] }
var repairs: [EKEvent] = []
for index in diff.retained {
    let event = owned[index]
    if event.title != "Занято" || event.availability != .busy || event.notes != nil || event.location != nil || event.hasAlarms || event.isAllDay { repairs.append(event) }
}
let creates = diff.create
var summary: [String: Any] = ["status": "preview", "source_calendars": sources.count,
    "occupied_blocks": blocks.count, "create": creates.count, "repair": repairs.count,
    "stale": stale.count, "all_day_included": cfg.includeAllDay, "days": cfg.days]
if mode == "preview" { finish(summary) }
// Missing calendars abort above. Missing events must persist across two runs >=4 minutes apart.
// Only opaque managed target IDs and timestamps are retained locally.
let pendingURL = root.appendingPathComponent("pending-removals.json")
let pending = (try? JSONSerialization.jsonObject(with: Data(contentsOf: pendingURL))) as? [String: Double] ?? [:]
var nextPending: [String: Double] = [:]
var deletes: [EKEvent] = []
for event in stale {
    let id = event.calendarItemIdentifier
    let firstSeen = pending[id] ?? now.timeIntervalSince1970
    nextPending[id] = firstSeen
    if now.timeIntervalSince1970 - firstSeen >= 240 { deletes.append(event) }
}
func sanitize(_ event: EKEvent) {
    event.title = "Занято"; event.availability = .busy; event.isAllDay = false
    event.notes = nil; event.location = nil; event.alarms = nil; event.url = marker
}
do {
    // Commit additions first: interrupted runs remain conservatively busy, never open gaps.
    for block in creates {
        let event = EKEvent(eventStore: store); event.calendar = target
        event.startDate = Date(timeIntervalSince1970: Double(block.start))
        event.endDate = Date(timeIntervalSince1970: Double(block.end))
        sanitize(event); try store.save(event, span: .thisEvent, commit: true)
    }
    for event in repairs { sanitize(event); try store.save(event, span: .thisEvent, commit: true) }
    for event in deletes { try store.remove(event, span: .thisEvent, commit: true); nextPending.removeValue(forKey: event.calendarItemIdentifier) }
    try writeJSON(nextPending, pendingURL)
} catch { fail("write_incomplete_reconcile_next_run") }
let readback = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [target])).filter { $0.url == marker }
let validKeys = Set(readback.filter {
    $0.title == "Занято" && $0.availability == .busy && $0.notes == nil && $0.location == nil && !$0.hasAlarms && !$0.hasAttendees
}.map { key($0) })
guard Set(blocks.map(\.key)).isSubset(of: validKeys) else { fail("local_readback_failed") }
summary["status"] = "synced_locally"
summary["deleted"] = deletes.count
summary["pending_removals"] = nextPending.count
summary["note"] = "Google cloud delivery and Calendly conflict selection require separate verification"
finish(summary)
