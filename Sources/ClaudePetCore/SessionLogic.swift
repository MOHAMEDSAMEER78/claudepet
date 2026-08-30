import Foundation

public struct EffectiveSession: Identifiable {
    public var id: String { sessionId }
    public var sessionId: String
    public var state: PetState
    public var bubbleText: String
    public var cwd: String?
    public var terminalPid: Int32?
    public var terminalApp: String?
    public var tty: String?
    public var ts: TimeInterval
    public var tasksDone: Int?
    public var tasksTotal: Int?
    public var title: String?
    public var claudePid: Int32?
    public var startedTs: TimeInterval?

    public init(
        sessionId: String, state: PetState, bubbleText: String, cwd: String?,
        terminalPid: Int32?, terminalApp: String?, tty: String?, ts: TimeInterval,
        tasksDone: Int?, tasksTotal: Int?, title: String?, claudePid: Int32?,
        startedTs: TimeInterval? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.bubbleText = bubbleText
        self.cwd = cwd
        self.terminalPid = terminalPid
        self.terminalApp = terminalApp
        self.tty = tty
        self.ts = ts
        self.tasksDone = tasksDone
        self.tasksTotal = tasksTotal
        self.title = title
        self.claudePid = claudePid
        self.startedTs = startedTs
    }
}

public enum SessionLogic {
    public static let currentSchemaVersion = 1

    public enum DecodeIssue: Equatable, Error {
        case malformed
        case unsupportedSchema(found: Int)
    }

    public static func decodeStatus(data: Data) -> Result<SessionStatus, DecodeIssue> {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let schema = obj["schema"] as? Int, schema > currentSchemaVersion {
            return .failure(.unsupportedSchema(found: schema))
        }
        guard let status = try? JSONDecoder().decode(SessionStatus.self, from: data) else {
            return .failure(.malformed)
        }
        return .success(status)
    }

    public static func effectiveState(
        status: SessionStatus, now: TimeInterval, reviewDecaySeconds: TimeInterval,
        runningStalledSeconds: TimeInterval = .infinity
    ) -> PetState {
        if status.state == .review && now - status.ts > reviewDecaySeconds { return .idle }
        if status.state == .running && now - status.ts > runningStalledSeconds { return .checking }
        return status.state
    }

    public static func isStale(status: SessionStatus, now: TimeInterval, staleSeconds: TimeInterval) -> Bool {
        now - status.ts > staleSeconds
    }

    public static func bubbleText(for status: SessionStatus, state: PetState) -> String {
        if let action = status.action, !action.isEmpty { return action }
        let cwdName = status.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        var parts = [String]()
        if !cwdName.isEmpty { parts.append(cwdName) }
        if let tool = status.tool, !tool.isEmpty { parts.append(tool) }
        if let summary = status.summary, !summary.isEmpty { parts.append(summary) }
        return parts.isEmpty ? state.label : parts.joined(separator: " · ")
    }

    public static func winner(among sessions: [EffectiveSession]) -> EffectiveSession? {
        sessions.max { $0.state.priority < $1.state.priority }
    }
}
