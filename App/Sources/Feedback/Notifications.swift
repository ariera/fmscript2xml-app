// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import UserNotifications

/// Failure notifications with an "Open Inspector" action.
@MainActor
final class Notifications: NSObject {
    static let shared = Notifications()

    private nonisolated static let failureCategory = "conversionFailed"
    private nonisolated static let openInspectorAction = "openInspector"

    private var center: UNUserNotificationCenter { .current() }

    func configure() {
        center.delegate = self
        let open = UNNotificationAction(identifier: Self.openInspectorAction, title: "Open Inspector", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.failureCategory, actions: [open], intentIdentifiers: []),
        ])
    }

    /// Asks for permission; called from the welcome window and before the
    /// first failure notification.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func postFailure(summary: String, errorCount: Int) {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "FMSPSuppressNotifications") {
            debugLog("notification suppressed: \(summary)")
            return
        }
        #endif
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard await requestAuthorization() else { return }
            }
            let content = UNMutableNotificationContent()
            content.title = errorCount > 1 ? "Not converted (\(errorCount) errors)" : "Not converted"
            content.subtitle = "The clipboard was left unchanged."
            content.body = summary
            content.categoryIdentifier = Self.failureCategory
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

extension Notifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action == Self.openInspectorAction || action == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { WindowManager.shared.showInspector() }
    }
}
