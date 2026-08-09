//
//  NotificationService.swift
//  WearLoop
//
//  Local reminders only. Nothing is scheduled until the user has read what the
//  reminders are for and said yes.
//

import UserNotifications

protocol NotificationServiceProtocol: AnyObject {
    /// Asks the system for permission. Returns whether it was granted.
    func requestAuthorization() async -> Bool
    /// Whether the system permission is currently granted.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Replaces all pending reminders with ones derived from the current state.
    func reschedule(state: AppState) async
    func cancelAll()
}

final class NotificationService: NotificationServiceProtocol {

    private let center = UNUserNotificationCenter.current()

    private enum Identifier {
        static let tripPrefix = "trip-starts-"
        static let laundryPrefix = "laundry-ready-"
        static let eventPrefix = "event-tomorrow-"
        static let repairPrefix = "repair-pending-"
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }

    func reschedule(state: AppState) async {
        cancelAll()

        let settings = state.notificationSettings
        guard settings.hasGrantedConsent else { return }
        guard await authorizationStatus() == .authorized else { return }

        let now = Date()

        if settings.tripStartsInTwoDays {
            for trip in state.trips where trip.phase == .upcoming && !trip.isDraft {
                let fireDate = Calendar.wl.addingDays(-2, to: trip.startDate.wlStartOfDay)
                guard let scheduled = at9am(fireDate), scheduled > now else { continue }
                let unplanned = trip.daysWithoutPlan.count
                let body = unplanned > 0
                    ? "\(trip.name) starts in two days and \(Plural.days(trip.daysWithoutPlan.map(\.dayNumber))) still need an outfit."
                    : "\(trip.name) starts in two days. Check the packing list and the weight."
                add(
                    id: Identifier.tripPrefix + trip.id.uuidString,
                    title: "Trip Starts in Two Days",
                    body: body,
                    at: scheduled
                )
            }
        }

        if settings.laundryReadyToReturn {
            for load in state.laundryLoads where load.stage == .drying || load.stage == .washingNow {
                guard let ready = load.expectedReady, let scheduled = at9am(ready), scheduled > now else { continue }
                add(
                    id: Identifier.laundryPrefix + load.id.uuidString,
                    title: "Laundry Ready to Return",
                    body: "\(load.name) should be dry. \(Plural.count(load.pieceIDs.count, "piece")) can go back into the wardrobe.",
                    at: scheduled
                )
            }
        }

        if settings.eventTomorrowWithoutOutfit {
            for event in state.events where !event.isWorn && event.outfitID == nil {
                let fireDate = Calendar.wl.addingDays(-1, to: event.date.wlStartOfDay)
                guard let scheduled = at(hour: 19, on: fireDate), scheduled > now else { continue }
                add(
                    id: Identifier.eventPrefix + event.id.uuidString,
                    title: "Event Tomorrow Without an Outfit",
                    body: "\(event.name) is tomorrow and has no outfit assigned.",
                    at: scheduled
                )
            }
        }

        if settings.repairPending {
            for repair in state.openRepairs where repair.daysOpen(now: now) >= 14 {
                // Nudge a week from now rather than about the past.
                guard let scheduled = at9am(Calendar.wl.addingDays(7, to: now)) else { continue }
                add(
                    id: Identifier.repairPrefix + repair.id.uuidString,
                    title: "Repair Pending",
                    body: "\(repair.snapshot.name) has been waiting for repair since \(DateFormatterCache.dayMonth.string(from: repair.reportedOn)).",
                    at: scheduled
                )
            }
        }
    }

    // MARK: - Helpers

    private func at9am(_ date: Date) -> Date? { at(hour: 9, on: date) }

    private func at(hour: Int, on date: Date) -> Date? {
        var components = Calendar.wl.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = 0
        return Calendar.wl.date(from: components)
    }

    private func add(id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.wl.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
