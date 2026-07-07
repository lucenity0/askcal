//
//  NotificationManager.swift
//  Pulse
//
//  Two quiet local nudges, both user-toggleable in More:
//  - morning digest (08:30): your day is ready
//  - evening nudge (21:00): close the day — suppressed for today once closed
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

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningId, eveningId])
        guard morningOn || eveningOn else { return }
        guard await ensureAuthorized() else { return }

        if morningOn {
            let content = UNMutableNotificationContent()
            content.title = "your day is ready."
            content.body = "the plan's built. open when you are."
            var comps = DateComponents()
            comps.hour = 8; comps.minute = 30
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            try? await center.add(
                UNNotificationRequest(identifier: morningId, content: content, trigger: trigger)
            )
        }

        if eveningOn {
            let content = UNMutableNotificationContent()
            content.title = "close the day?"
            content.body = "30 seconds. tomorrow builds itself."
            let trigger: UNCalendarNotificationTrigger
            if dayClosed, let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) {
                // today is handled — stay quiet tonight, resume tomorrow
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = 21; comps.minute = 0
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            } else {
                var comps = DateComponents()
                comps.hour = 21; comps.minute = 0
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            }
            try? await center.add(
                UNNotificationRequest(identifier: eveningId, content: content, trigger: trigger)
            )
        }
    }
}
