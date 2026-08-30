import Foundation

public enum PetState: String, Codable, CaseIterable {
    case idle
    case checking
    case running
    case waitingPermission = "waiting-permission"
    case review
    case failed

    public var priority: Int {
        switch self {
        case .waitingPermission: return 5
        case .failed: return 4
        case .review: return 3
        case .running: return 2
        case .checking: return 1
        case .idle: return 0
        }
    }

    public var emoji: String {
        switch self {
        case .idle: return "😴"
        case .checking: return "🤔"
        case .running: return "🏃"
        case .waitingPermission: return "🙋"
        case .review: return "✅"
        case .failed: return "💥"
        }
    }

    public var label: String {
        switch self {
        case .idle: return "Idle"
        case .checking: return "Still going? (no update in a while)"
        case .running: return "Working"
        case .waitingPermission: return "Needs permission"
        case .review: return "Ready for review"
        case .failed: return "Failed"
        }
    }

    public var menuBarSymbol: String {
        switch self {
        case .idle: return "pawprint.fill"
        case .checking: return "questionmark.circle.fill"
        case .running: return "figure.run"
        case .waitingPermission: return "hand.raised.fill"
        case .review: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

public struct SessionStatus: Codable {
    public var sessionId: String
    public var state: PetState
    public var cwd: String?
    public var tool: String?
    public var summary: String?
    public var action: String?
    public var ts: TimeInterval
    public var terminalPid: Int32?
    public var terminalApp: String?
    public var tty: String?
    public var tasksDone: Int?
    public var tasksTotal: Int?
    public var title: String?
    public var claudePid: Int32?
    public var startedTs: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state, cwd, tool, summary, action, ts, tty, title
        case terminalPid = "terminal_pid"
        case terminalApp = "terminal_app"
        case tasksDone = "tasks_done"
        case tasksTotal = "tasks_total"
        case claudePid = "claude_pid"
        case startedTs = "started_ts"
    }
}
