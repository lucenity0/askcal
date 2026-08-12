//
//  Models.swift
//  Askcal
//
//  Domain models matching askcal-api's contracts (camelCase JSON).
//  The regret score (0–100) still ranks everything — it's just never shown.
//  In the monochrome UI it surfaces only as a priority dot band.
//

import Foundation

enum TrackKey: String, Codable, CaseIterable, Identifiable {
    case career, design, uni, feed, finance
    var id: String { rawValue }

    var title: String {
        switch self {
        case .career: return "Career"
        case .design: return "Design"
        case .uni: return "Uni"
        case .feed: return "Feed"
        case .finance: return "Finance"
        }
    }

    var icon: String {
        switch self {
        case .career: return "briefcase"
        case .design: return "paintbrush.pointed"
        case .uni: return "graduationcap"
        case .feed: return "newspaper"
        case .finance: return "creditcard"
        }
    }

    /// Kicker for the track's section header on the Tracks page
    var sectionKicker: String {
        switch self {
        case .career: return "Pipeline"
        case .design: return "Briefs"
        case .uni: return "Deadlines"
        case .feed: return "Reading"
        case .finance: return "Money"
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
    var track: TrackKey
    var title: String
    var meta: String?          // server-humanized deadline; client recomputes live
    var regretScore: Int
    var estimatedHours: Double?
    var status: TaskStatus = .pending
    var pipeline: String?      // career only: applied | oa | interview | offer | reject
    var scheduledFor: Date?    // the day this task lives on
    var scheduledAt: Date?     // pinned start time, if the user chose one
    var dueAt: Date?           // deadline — drives the live countdown

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
        id: UUID, track: TrackKey, title: String, meta: String? = nil,
        regretScore: Int, estimatedHours: Double? = nil,
        status: TaskStatus = .pending, pipeline: String? = nil,
        scheduledFor: Date? = nil, scheduledAt: Date? = nil, dueAt: Date? = nil
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
        track = try c.decodeIfPresent(TrackKey.self, forKey: .track) ?? .uni
        title = try c.decode(String.self, forKey: .title)
        meta = try c.decodeIfPresent(String.self, forKey: .meta)
        regretScore = try c.decodeIfPresent(Int.self, forKey: .regretScore) ?? 0
        estimatedHours = try c.decodeIfPresent(Double.self, forKey: .estimatedHours)
        status = try c.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .pending
        pipeline = try c.decodeIfPresent(String.self, forKey: .pipeline)
        scheduledFor = try c.decodeIfPresent(Date.self, forKey: .scheduledFor)
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        dueAt = try c.decodeIfPresent(Date.self, forKey: .dueAt)
    }
}

struct EmailItem: Identifiable, Codable, Equatable {
    let id: String             // Gmail message id
    var track: TrackKey?
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
