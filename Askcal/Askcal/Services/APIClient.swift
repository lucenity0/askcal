//
//  APIClient.swift
//  Askcal
//
//  askcal-api client. Access token lives in memory (15-min JWT), refresh
//  token in the Keychain. On 401: silent refresh, retry once — per the
//  API contract. Base URL is editable in More (simulator: localhost).
//

import Foundation

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .badURL: return "bad API URL."
        case .http(let code, let message): return "\(message) (\(code))"
        case .disconnected: return "not connected."
        }
    }
}

/// Date formatting for the wire, deliberately outside `APIClient`.
///
/// `JSONDecoder`'s custom strategy runs wherever decoding happens, not on the
/// main actor, so main-actor-isolated formatters can't be reached from it —
/// and a `DateFormatter` shared across threads is a genuine data race, not just
/// a compiler complaint. These are configured once here and only ever read
/// from, which is safe; `nonisolated(unsafe)` states that promise explicitly
/// rather than leaving the decode path warning-shaped.
enum APIDates {
    /// Date-only ("2026-07-08"), interpreted at local midnight — used for
    /// `scheduledFor`, which the API sends without a time component.
    nonisolated(unsafe) static let dayOnly: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        // en_US_POSIX or the format string is at the mercy of the device's
        // regional calendar: under a Buddhist or Japanese locale "yyyy" is an
        // era year, so this both parses and emits the wrong date entirely.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    /// ISO-8601 for datetimes we send back (pinned time, deadline).
    nonisolated(unsafe) static let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = isoFractional.date(from: raw) ?? iso.date(from: raw)
                ?? dayOnly.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: d.codingPath, debugDescription: "bad date: \(raw)"
            ))
        }
        return decoder
    }()
}

@MainActor
final class APIClient {
    static let shared = APIClient()
    private var accessToken: String?

    /// Production API on GCP; override via UserDefaults "apiBaseURL"
    /// (no UI for it — deliberate, per owner request).
    static let defaultBaseURL = "https://api.askcal.lucenity.dev"

    var baseURL: String {
        UserDefaults.standard.string(forKey: "apiBaseURL") ?? Self.defaultBaseURL
    }

    var isConnected: Bool { Keychain.read("askcalRefreshToken") != nil }

    // MARK: - Auth

    func authStartURL(scheme: String) -> URL? {
        URL(string: "\(baseURL)/auth/google/start?scheme=\(scheme)")
    }

    /// askcal://oauth#accessToken=…&refreshToken=…&email=…&name=…
    func handleAuthCallback(_ url: URL) -> (email: String, name: String)? {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        else { return nil }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            params[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
        }
        guard let access = params["accessToken"], let refresh = params["refreshToken"]
        else { return nil }
        accessToken = access
        Keychain.save("askcalRefreshToken", refresh)
        return (params["email"] ?? "", params["name"] ?? "")
    }

    func disconnect() {
        accessToken = nil
        Keychain.delete("askcalRefreshToken")
    }

    private func refreshAccessToken() async throws {
        guard let refresh = Keychain.read("askcalRefreshToken") else {
            throw APIError.disconnected
        }
        struct RefreshOut: Decodable { let accessToken: String }
        let out: RefreshOut = try await send(
            "POST", "/auth/refresh",
            body: ["refreshToken": refresh],
            authenticated: false
        )
        accessToken = out.accessToken
    }

    // MARK: - Core request

    private static let decoder = APIDates.decoder
    private static var dayOnly: DateFormatter { APIDates.dayOnly }

    /// ISO-8601 for datetimes we send back (pinned time, deadline).
    static var isoOut: ISO8601DateFormatter { APIDates.isoOut }

    private func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any?]? = nil,
        authenticated: Bool = true,
        retryOn401: Bool = true
    ) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else {
            throw APIError.badURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        // no-op against the real backend; required so ngrok's free-tier
        // browser-warning interstitial doesn't intercept plain API calls
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: body.compactMapValues { $0 }
            )
        }
        if authenticated {
            if accessToken == nil { try await refreshAccessToken() }
            request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401, authenticated, retryOn401 {
            try await refreshAccessToken()
            return try await send(
                method, path, query: query, body: body,
                authenticated: authenticated, retryOn401: false
            )
        }
        guard (200..<300).contains(status) else {
            let message = (try? Self.decoder.decode(APIErrorBody.self, from: data))?.message
            throw APIError.http(status, message ?? "request failed")
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try Self.decoder.decode(T.self, from: data)
    }

    struct EmptyResponse: Decodable {}
    private struct APIErrorBody: Decodable { let message: String? }

    // MARK: - Endpoints

    struct TasksOut: Decodable { let tasks: [AskcalTask] }
    struct TodayOut: Decodable {
        let dayPlan: [PlanSlot]
        let unscheduled: [UnscheduledTask]
        let carryForward: Int
        struct UnscheduledTask: Decodable { let id: UUID; let title: String }
    }
    struct InboxOut: Decodable { let emails: [EmailItem] }
    struct EventsOut: Decodable {
        let events: [APIEvent]
        struct APIEvent: Decodable {
            let id: String
            let title: String
            let start: Date?
            let end: Date?
            let allDay: Bool
        }
    }
    struct ClosingOut: Decodable { let carryForwardCount: Int; let message: String }

    /// Today's list. `includeDone` keeps completed work in it: the day shows a
    /// ticked task struck through rather than removing it, so leaving them out
    /// here would make every refresh quietly erase the day's progress.
    func tasks(includeDone: Bool = true) async throws -> [AskcalTask] {
        (try await send("GET", "/api/tasks", query: [
            .init(name: "includeDone", value: includeDone ? "true" : "false"),
        ]) as TasksOut).tasks
    }

    func today() async throws -> TodayOut {
        try await send("GET", "/api/today")
    }

    func inbox() async throws -> [EmailItem] {
        (try await send("GET", "/api/inbox") as InboxOut).emails
    }

    func calendarEvents(start: String, end: String) async throws -> [EventsOut.APIEvent] {
        let out: EventsOut = try await send(
            "GET", "/api/calendar",
            query: [.init(name: "start", value: start), .init(name: "end", value: end)]
        )
        return out.events
    }

    func createTask(
        title: String, track: TrackKey,
        scheduledAt: Date? = nil, dueAt: Date? = nil, scheduledFor: Date? = nil
    ) async throws -> AskcalTask {
        var body: [String: Any?] = ["title": title, "track": track.rawValue]
        if let scheduledAt { body["scheduledAt"] = Self.isoOut.string(from: scheduledAt) }
        if let dueAt { body["dueAt"] = Self.isoOut.string(from: dueAt) }
        if let scheduledFor { body["scheduledFor"] = Self.dayOnly.string(from: scheduledFor) }
        return try await send("POST", "/api/tasks", body: body)
    }

    /// Remove a task outright. The undo for a wrong auto-tasked item or a
    /// mistyped quick-add — without it the only way to clear one was to mark it
    /// done, so every mistake accumulated permanently.
    func deleteTask(_ id: UUID) async throws {
        let _: EmptyResponse = try await send(
            "DELETE", "/api/tasks/\(id.uuidString.lowercased())"
        )
    }

    func setTaskStatus(_ id: UUID, _ status: TaskStatus) async throws -> AskcalTask {
        try await send("PATCH", "/api/tasks/\(id.uuidString.lowercased())",
                       body: ["status": status.rawValue])
    }

    /// Shift a task to another day/time and/or change its deadline. This is a
    /// full replace of the schedule: a nil pin or deadline is sent as an
    /// explicit null (NSNull) so the server clears it rather than ignoring it.
    func updateTaskSchedule(
        _ id: UUID, scheduledAt: Date?, dueAt: Date?, scheduledFor: Date?
    ) async throws -> AskcalTask {
        var body: [String: Any?] = [
            "scheduledAt": scheduledAt.map { Self.isoOut.string(from: $0) } ?? NSNull(),
            "dueAt": dueAt.map { Self.isoOut.string(from: $0) } ?? NSNull(),
        ]
        if let scheduledFor { body["scheduledFor"] = Self.dayOnly.string(from: scheduledFor) }
        return try await send("PATCH", "/api/tasks/\(id.uuidString.lowercased())", body: body)
    }

    /// Every task in an inclusive date range — one request for a whole month,
    /// so the month grid can mark the days that have something on them.
    func tasks(from start: Date, to end: Date) async throws -> [AskcalTask] {
        (try await send("GET", "/api/tasks", query: [
            .init(name: "start", value: Self.dayOnly.string(from: start)),
            .init(name: "end", value: Self.dayOnly.string(from: end)),
        ]) as TasksOut).tasks
    }

    func tasks(on date: Date) async throws -> [AskcalTask] {
        (try await send("GET", "/api/tasks",
                        query: [.init(name: "on", value: Self.dayOnly.string(from: date))]) as TasksOut).tasks
    }

    struct MeOut: Decodable { let email: String; let name: String? }

    func updateName(_ name: String) async throws -> String {
        let out: MeOut = try await send("PATCH", "/api/me", body: ["name": name])
        return out.name ?? name
    }

    /// Keep the account's timezone in step with the device so day plans land
    /// in real local time instead of UTC.
    func syncTimezone() async {
        _ = try? await send("PATCH", "/api/me",
                            body: ["timezone": TimeZone.current.identifier]) as MeOut
    }

    // MARK: - Settings and digests

    func settings() async throws -> AppSettings {
        try await send("GET", "/api/settings")
    }

    /// Patches only what it is given. Every field is optional server-side, so
    /// omitting one leaves it alone rather than resetting it.
    func updateSettings(_ changes: [String: Any?]) async throws -> AppSettings {
        try await send("PATCH", "/api/settings", body: changes)
    }

    func digest(_ which: DigestKind) async throws -> Digest {
        try await send("GET", "/api/digest/\(which.rawValue)")
    }

    func me() async throws -> MeOut {
        try await send("GET", "/api/me")
    }

    func handleEmail(_ gmailId: String) async throws -> AskcalTask {
        try await send("POST", "/api/inbox/\(gmailId)/handle", body: [:])
    }

    func snoozeEmail(_ gmailId: String) async throws {
        struct SnoozeOut: Decodable { let snoozedUntil: Date }
        let _: SnoozeOut = try await send("POST", "/api/inbox/\(gmailId)/snooze", body: [:])
    }

    func triggerSync() async throws {
        struct SyncOut: Decodable { let status: String }
        let _: SyncOut = try await send("POST", "/api/inbox/sync", body: nil)
    }


    func closingTime(date: String, pulled: [UUID], remaining: [UUID]) async throws -> ClosingOut {
        try await send("POST", "/api/closing-time", body: [
            "date": date,
            "pulled": pulled.map { $0.uuidString.lowercased() },
            "remaining": remaining.map { $0.uuidString.lowercased() },
        ])
    }
}
