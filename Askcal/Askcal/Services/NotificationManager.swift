//
//  NotificationManager.swift
//  Askcal
//
//  Two quiet local nudges, at hours the user picks.
//
//  Both carry the day's actual summary rather than fixed copy. "your day is
//  ready" is a reminder that the app exists, not a reason to open it, and a
//  notification that says nothing trains you to swipe it away. The text comes
//  from the same endpoint as the card behind it, so the two cannot disagree.
//
//  Local notifications are scheduled ahead of time, so the content is whatever
//  was true when the app last ran. That is a real limitation and an acceptable
//  one: a digest built at last launch is far closer to the truth than a fixed
//  string, and it refreshes on every open.
//

import Foundation
import UserNotifications

enum NotificationManager {
    private static let morningId = "morningDigest"
    private static let eveningId = "eveningNudge"

    static func ensureAuthorized() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
    }

    static func refreshSchedules(dayClosed: Bool) async {
        let ud = UserDefaults.standard
        let morningOn = ud.object(forKey: "morningDigest") as? Bool ?? true
        let eveningOn = ud.object(forKey: "eveningNudge") as? Bool ?? true
        let morningHour = ud.object(forKey: "morningHour") as? Int ?? 8
        let eveningHour = ud.object(forKey: "eveningHour") as? Int ?? 21

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningId, eveningId])
        guard morningOn || eveningOn else { return }
        guard await ensureAuthorized() else { return }

        if morningOn {
            let summary = try? await APIClient.shared.digest(.morning)
            let content = UNMutableNotificationContent()
            content.title = summary?.headline ?? "your day is ready."
            content.body = summary?.lines.prefix(2).joined(separator: " · ")
                ?? "the plan's built. open when you are."
            content.userInfo = ["digest": DigestKind.morning.rawValue]
            var comps = DateComponents()
            comps.hour = morningHour; comps.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: morningId, content: content, trigger: trigger)
            )
        }

        if eveningOn {
            let summary = try? await APIClient.shared.digest(.evening)
            let content = UNMutableNotificationContent()
            content.title = summary?.headline ?? "close the day?"
            content.body = summary?.lines.prefix(2).joined(separator: " · ")
                ?? "30 seconds. tomorrow builds itself."
            content.userInfo = ["digest": DigestKind.evening.rawValue]
            let trigger: UNCalendarNotificationTrigger
            if dayClosed, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) {
                // today is handled — stay quiet tonight, resume tomorrow
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = eveningHour; comps.minute = 0
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            } else {
                var comps = DateComponents()
                comps.hour = eveningHour; comps.minute = 0
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            }
            try? await center.add(
                UNNotificationRequest(identifier: eveningId, content: content, trigger: trigger)
            )
        }
    }
}
