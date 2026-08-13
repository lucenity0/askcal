//
//  Models.swift
//  Askcal
//
//  Domain models matching askcal-api's contracts (camelCase JSON).
//  The regret score (0–100) still ranks everything — it's just never shown.
//  In the monochrome UI it surfaces only as a priority dot band.
//

import Foundation

/// A track, as the account has it.
///
/// This used to be a five-case enum. It described a guess at someone's life
/// rather than anyone's actual life — a PR review is work, but it was filed
/// as `design`, because those were the only categories on offer. A track is a
/// row the user names now, so nothing here can be a compile-time set.
///
/// `id` is the slug: stable across renames, and what every task and mail is
/// filed under. `label` is what the user typed and can change at any time.
struct Track: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var label: String
    var detail: String?      // their words for what belongs here; steers the classifier
    var active: Bool
    var autoTasks: Bool
    var isBuiltin: Bool
    var weight: Double
    var taskCount: Int
    var urgentCount: Int

    init(
        id: String, label: String, detail: String? = nil,
        active: Bool = true, autoTasks: Bool = true, isBuiltin: Bool = false,
        weight: Double = 1.0, taskCount: Int = 0, urgentCount: Int = 0
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.active = active
        self.autoTasks = autoTasks
        self.isBuiltin = isBuiltin
        self.weight = weight
        self.taskCount = taskCount
        self.urgentCount = urgentCount
    }

    enum CodingKeys: String, CodingKey {
        case id, label, active, autoTasks, isBuiltin, weight, taskCount, urgentCount
        case detail = "description"
    }

    /// Every field but the slug tolerates absence. A track the server describes
    /// slightly differently than we expect must not take the whole list down
    /// with it — that is how a screen ends up empty for no visible reason.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? Track.title(for: id)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
        autoTasks = try c.decodeIfPresent(Bool.self, forKey: .autoTasks) ?? true
        isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1.0
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount) ?? 0
        urgentCount = try c.decodeIfPresent(Int.self, forKey: .urgentCount) ?? 0
    }

    var icon: String { Track.icon(for: id) }

    /// A readable name for a slug we have no track for — mail classified under
    /// a track that has since been deleted, or a response that arrived before
    /// the track list did.
    static func title(for slug: String) -> String {
        slug.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The five that ship with an account keep their symbols. Anything the user
    /// makes gets a neutral one — guessing a symbol from a name they chose is a
    /// worse failure than not trying.
    static func icon(for slug: String) -> String {
        switch slug {
        case "career": return "briefcase"
        case "design": return "paintbrush.pointed"
        case "uni": return "graduationcap"
        case "feed": return "newspaper"
        case "finance": return "creditcard"
        default: return "bookmark"
        }
    }
}

enum TaskStatus: String, Codable {
    case pending, done, carried
}

/// Monochrome urgency: solid dot / hollow dot / nothing. Never a number.
enum PriorityBand {
    case high, medium, low

    init(regretScore: Int?) {
        switch regretScore ?? 0 {
        case 65...: self = .high
        case 25..<65: self = .medium
        default: self = .low
        }
    }
}

struct AskcalTask: Identifiable, Codable, Equatable {
    let id: UUID
    var track: String
    var title: String
    var meta: String?          // server-humanized deadline; client recomputes live
    var regretScore: Int
    var estimatedHours: Double?
    var status: TaskStatus = .pending
    var pipeline: String?      // career only: applied | oa | interview | offer | reject
    var scheduledFor: Date?    // the day this task lives on
    var scheduledAt: Date?     // pinned start time, if the user chose one
    var dueAt: Date?           // deadline — drives the live countdown
    /// When it was actually ticked. The day list showed the planned slot and
    /// lost it on completion, so finishing something erased the only evidence
    /// of when it happened.
    var completedAt: Date?

    var priority: PriorityBand { PriorityBand(regretScore: regretScore) }

    /// Live deadline label, recomputed each render so it never goes stale.
    /// Under an hour → minutes, under a day → hours, else days. Falls back to
    /// the server's `meta` when there's no raw deadline.
    var deadlineLabel: String? {
        guard let dueAt else { return meta }
        let secs = dueAt.timeIntervalSinceNow
        let overdue = secs < 0
        let s = abs(secs)
        let unit: String
        if s < 3600 {
            unit = "\(max(1, Int((s / 60).rounded()))) min"
        } else if s < 86400 {
            unit = "\(max(1, Int(s / 3600))) h"
        } else {
            let d = Int(s / 86400)
            unit = "\(d) day\(d == 1 ? "" : "s")"
        }
        return overdue ? "overdue by \(unit)" : "due in \(unit)"
    }

    init(
        id: UUID, track: String, title: String, meta: String? = nil,
        regretScore: Int, estimatedHours: Double? = nil,
        status: TaskStatus = .pending, pipeline: String? = nil,
        scheduledFor: Date? = nil, scheduledAt: Date? = nil, dueAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.track = track
        self.title = title
        self.meta = meta
        self.regretScore = regretScore
        self.estimatedHours = estimatedHours
        self.status = status
        self.pipeline = pipeline
        self.scheduledFor = scheduledFor
        self.scheduledAt = scheduledAt
        self.dueAt = dueAt
        self.completedAt = completedAt
    }

    // Defensive decoding: a missing `status` (older/leaner API responses)
    // must not silently kill the whole decode — that's exactly how created
    // tasks vanished between server and screen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // `track` is nullable in the API contract (TaskOut.track: str | None),
        // so a hard decode here would throw on a legitimate response and take
        // the whole task with it.
        track = try c.decodeIfPresent(String.self, forKey: .track) ?? ""
        title = try c.decode(String.self, forKey: .title)
        meta = try c.decodeIfPresent(String.self, forKey: .meta)
        regretScore = try c.decodeIfPresent(Int.self, forKey: .regretScore) ?? 0
        estimatedHours = try c.decodeIfPresent(Double.self, forKey: .estimatedHours)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .pending
        pipeline = try c.decodeIfPresent(String.self, forKey: .pipeline)
        scheduledFor = try c.decodeIfPresent(Date.self, forKey: .scheduledFor)
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct EmailItem: Identifiable, Codable, Equatable {
    let id: String             // Gmail message id
    var track: String?
    var subject: String?
    var sender: String?
    var receivedAt: Date
    var regretScore: Int?
    var estimatedMinutes: Int?
    var snippet: String?
    /// What this mail wants from you, decided server-side from the stored
    /// signals. Derived there rather than here so the app and the auto-tasker
    /// cannot disagree about what a piece of mail is.
    var needs: MailNeed = .read

    enum CodingKeys: String, CodingKey {
        case id, track, subject
        case sender = "from"
        case receivedAt, regretScore, estimatedMinutes, snippet, needs
    }

    var priority: PriorityBand { PriorityBand(regretScore: regretScore) }
}

/// The four things a piece of mail can want. Ordered as the inbox reads them.
enum MailNeed: String, Codable, CaseIterable, Identifiable {
    case reply, deadline, read, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply: return "reply needed"
        case .deadline: return "has a deadline"
        case .read: return "read when free"
        case .none: return "nothing to do"
        }
    }

    var note: String {
        switch self {
        case .reply: return "someone is waiting on you"
        case .deadline: return "there is a date on it"
        case .read: return "worth a look, no rush"
        case .none: return "receipts, digests, notices"
        }
    }

    /// An unrecognised value must not fail the decode and take the whole inbox
    /// with it — a new band added server-side should degrade to "read".
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MailNeed(rawValue: raw) ?? .read
    }
}

struct PlanSlot: Identifiable, Codable, Equatable {
    var time: String           // "09:00"
    var taskId: UUID
    var duration: Int          // minutes
    var id: UUID { taskId }
}


/// External calendar block. IDs come from Google, so they're strings;
/// start/end stay "HH:mm" — the API's ISO datetimes are converted on decode.
struct CalendarEvent: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var start: String          // "10:00"
    var end: String            // "11:30"
    var source: String = "google"
}

/// "HH:mm" → minutes since midnight; nil if malformed.
func minutesSinceMidnight(_ hhmm: String) -> Int? {
    let parts = hhmm.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
    return h * 60 + m
}

// MARK: - Settings

/// What the settings screen reads. Split the way the backend splits it: the
/// The day's page — whatever needed writing down that was not a task.
///
/// Keyed on the day, not on an id of its own, so writing on a day never needs
/// the note to be created first.
struct DayNote: Codable, Equatable, Identifiable {
    var day: Date
    var body: String
    var updatedAt: Date?

    var id: Date { day }
    var isEmpty: Bool { body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The first line worth showing, for the collapsed row on the phone.
    /// Markdown heading marks are stripped — "# standup" reads as a title in
    /// the editor and as a hash in a one-line preview.
    var summary: String {
        body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .drop { $0 == "#" || $0 == "-" || $0 == "*" || $0 == ">" }
                    .trimmingCharacters(in: .whitespaces)
            } ?? ""
    }
}

/// One connected mailbox.
///
/// There used to be exactly one, held on the user, so college mail and personal
/// mail could not both reach Askcal. `defaultTrack` is what mail here usually
/// is — a leaning handed to the classifier, never a rule, since a bill arriving
/// at a college address is still about money.
struct MailAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var email: String
    /// What the user calls it — "college", "work". The address makes a poor
    /// title: it is long, it wraps, and they already know it.
    var label: String?
    var isPrimary: Bool
    var active: Bool
    /// Whether there is still a usable token. An account outlives its access
    /// when Google revokes it, and saying so is the only way that stops looking
    /// like an inbox that simply never delivers.
    var connected: Bool
    /// Tracks this mailbox usually carries — as many as apply.
    var tracks: [String] = []
    var lastSyncedAt: Date?

    /// What to call it on screen. Falls back to the part of the address before
    /// the @, which is shorter than the whole thing and usually recognisable.
    var title: String {
        if let label, !label.isEmpty { return label }
        return String(email.prefix(while: { $0 != "@" }))
    }
}

/// classifier half is reported and cannot be set from here, because the
/// credential behind it lives in the environment on the server and a settings
/// screen able to write it would mean a subscription token travelling from a
/// phone into a database.
struct AppSettings: Codable, Equatable {
    var classifier: ClassifierStatus
    var sync: SyncStatus
    var autoTask: AutoTaskPrefs
    var reminders: ReminderPrefs
    var timezone: String

    struct ClassifierStatus: Codable, Equatable {
        var provider: String
        var model: String
        var configured: Bool
        /// Only present when something is wrong, and then it says what.
        var detail: String?
    }

    struct SyncStatus: Codable, Equatable {
        var intervalMinutes: Int
        var windowDays: Int
        var lastSyncedAt: Date?
        /// When a pass last ran, and why it failed if it did. Separate from
        /// `lastSyncedAt`, which is when mail last actually arrived — one
        /// timestamp could not tell "not running" from "running and failing".
        var lastAttemptAt: Date?
        var lastError: String?
        var enabled: Bool
    }

    struct AutoTaskPrefs: Codable, Equatable {
        var minConfidence: Double
        var minRegret: Int
        /// How hard work you keep pushing to tomorrow argues for a place in
        /// the day. 0 leaves the classifier's ranking untouched.
        var carryForwardSensitivity: Double
    }

    struct ReminderPrefs: Codable, Equatable {
        var morningDigest: Bool
        var morningHour: Int
        var eveningNudge: Bool
        var eveningHour: Int
    }
}

/// One end-of-day or start-of-day summary. Both digests share a shape because
/// they answer the same question at different ends of the day.
struct Digest: Codable, Equatable {
    var date: Date
    var headline: String
    var lines: [String] = []

    var taskCount: Int = 0
    var dueToday: Int = 0
    var carriedOver: Int = 0
    var firstSlot: String?
    var plannedMinutes: Int = 0
    var needsReply: Int = 0
    var mailWithDeadlines: Int = 0

    var done: Int = 0
    var carried: Int = 0
    var stillOpen: Int = 0
    var streak: Int = 0
}

enum DigestKind: String, CaseIterable, Identifiable {
    case morning, evening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return "Your day"
        case .evening: return "How it went"
        }
    }
}
