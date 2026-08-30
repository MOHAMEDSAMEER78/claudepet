import Foundation
import UserNotifications
import AppKit
import ClaudePetCore

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var authorized = false

    func requestAuthorization() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorized = granted }
        }
    }

    func notifyPermissionNeeded(request: PermissionRequest) {
        guard AppSettings.shared.notificationsEnabled, AppSettings.shared.notifyOnPermission, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "🙋 Claude Code needs your permission"
        if let project = Self.projectName(fromCwd: request.cwd) { content.subtitle = project }
        content.body = request.summary ?? request.tool.map { "Wants to use \($0)" } ?? "Waiting on a decision"
        content.sound = .default
        content.categoryIdentifier = "PERMISSION_REQUEST"
        post(content, id: "permission-\(request.requestId)")
    }

    func notifyStateChange(name: String, state: PetState, appIsActive: Bool) {
        guard AppSettings.shared.notificationsEnabled, authorized, !appIsActive else { return }
        guard isEnabled(for: state) else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(state.emoji) \(name)"
        content.body = body(for: state)
        content.sound = .default
        post(content, id: "state-\(name)-\(state.rawValue)-\(Int(Date().timeIntervalSince1970))")
    }

    func notifySessionCompleted(name: String, finalState: PetState, cwd: String?, tasksCompleted: Int, tasksTotal: Int, durationSeconds: TimeInterval?) {
        guard AppSettings.shared.notificationsEnabled, AppSettings.shared.notifyOnSessionEnd, authorized else { return }
        let content = UNMutableNotificationContent()
        let verb = finalState == .failed ? "ended after a failure" : "finished"
        content.title = "\(finalState.emoji) \(name) \(verb)"
        if let project = Self.projectName(fromCwd: cwd) { content.subtitle = project }
        var parts: [String] = []
        if tasksTotal > 0 { parts.append("\(tasksCompleted)/\(tasksTotal) tasks") }
        if let durationSeconds, durationSeconds > 0 {
            let minutes = Int(durationSeconds / 60)
            parts.append(minutes > 0 ? "\(minutes)m" : "<1m")
        }
        content.body = parts.isEmpty ? "Session ended" : parts.joined(separator: " · ")
        content.sound = .default
        post(content, id: "session-end-\(Int(Date().timeIntervalSince1970))")
    }

    func notifyBudgetExceeded(spendUSD: Double, thresholdUSD: Double) {
        guard AppSettings.shared.notificationsEnabled, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "💰 Today's spend crossed your budget"
        content.body = String(format: "Est. $%.2f so far, budget is $%.2f.", spendUSD, thresholdUSD)
        content.sound = .default
        post(content, id: "budget-\(Int(Date().timeIntervalSince1970))")
    }

    func notifyWeeklyDigest(sessions: Int, tasksCompleted: Int, secondsWorked: TimeInterval, costUSD: Double) {
        guard AppSettings.shared.notificationsEnabled, authorized else { return }
        let hours = secondsWorked / 3600
        let content = UNMutableNotificationContent()
        content.title = "📅 This week with Claude Code"
        content.body = String(
            format: "%d sessions, %d tasks, %.1fh worked, est. $%.2f.",
            sessions, tasksCompleted, hours, costUSD
        )
        content.sound = .default
        post(content, id: "weekly-digest-\(Int(Date().timeIntervalSince1970))")
    }

    private static func projectName(fromCwd cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private func isEnabled(for state: PetState) -> Bool {
        switch state {
        case .failed: return AppSettings.shared.notifyOnFailed
        case .review: return AppSettings.shared.notifyOnReview
        case .running: return AppSettings.shared.notifyOnRunning
        case .checking: return AppSettings.shared.notifyOnRunning
        case .waitingPermission, .idle: return false
        }
    }

    private func body(for state: PetState) -> String {
        switch state {
        case .failed: return "Something went wrong"
        case .review: return "Done - ready for your review"
        case .running: return "Started working"
        case .checking: return "Been quiet a while - might be stuck"
        case .waitingPermission, .idle: return state.label
        }
    }

    private func post(_ content: UNMutableNotificationContent, id: String) {
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
