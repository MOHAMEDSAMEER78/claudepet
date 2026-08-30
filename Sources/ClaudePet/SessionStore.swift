import Foundation
import Combine
import Darwin
import os
import ClaudePetCore

final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [EffectiveSession] = []
    @Published private(set) var aggregate: PetState = .idle
    @Published private(set) var bubbleText: String = ""
    @Published private(set) var sessionCount: Int = 0
    @Published private(set) var tasksDone: Int?
    @Published private(set) var tasksTotal: Int?
    @Published private(set) var title: String?
    @Published private(set) var winningSessionId: String?
    @Published private(set) var lastDecodeWarning: String?

    private let directory: URL
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var decayTimer: Timer?

    private static let reviewDecaySeconds: TimeInterval = 20
    private static let staleSeconds: TimeInterval = 30 * 60
    private static let runningStalledSeconds: TimeInterval = 20

    let stateTransitions = PassthroughSubject<(old: EffectiveSession?, new: EffectiveSession), Never>()
    let sessionEnded = PassthroughSubject<EffectiveSession, Never>()

    private var lastStateBySession: [String: PetState] = [:]
    private let notifier = IPCNotifier(socketName: "notify-sessions.sock")

    init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/pet/sessions", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        startWatching()
        refresh()
    }

    private func startWatching() {
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in self?.refresh() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.dirWatcher = source

        notifier.start { [weak self] in self?.refresh() }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        decayTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let now = Date().timeIntervalSince1970
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        var statuses: [SessionStatus] = []
        var decodeWarning: String?
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file) else { continue }
            let status: SessionStatus
            switch SessionLogic.decodeStatus(data: data) {
            case .success(let decoded):
                status = decoded
            case .failure(let issue):
                switch issue {
                case .malformed:
                    os_log(.error, "ClaudePet: skipped unreadable session file %{public}@", file.lastPathComponent)
                case .unsupportedSchema(let found):
                    let message = "Session file \(file.lastPathComponent) uses a newer format (schema \(found)) than this build of ClaudePet understands - update the app."
                    os_log(.error, "ClaudePet: %{public}@", message)
                    decodeWarning = message
                }
                continue
            }

            if let pid = status.claudePid, kill(pid_t(pid), 0) != 0, errno == ESRCH {
                emitSessionEnded(for: status, now: now)
                try? FileManager.default.removeItem(at: file)
                continue
            }

            if SessionLogic.isStale(status: status, now: now, staleSeconds: Self.staleSeconds) {
                emitSessionEnded(for: status, now: now)
                try? FileManager.default.removeItem(at: file)
                continue
            }
            statuses.append(status)
        }

        let effective: [EffectiveSession] = statuses.map { s in
            let state = SessionLogic.effectiveState(
                status: s, now: now, reviewDecaySeconds: Self.reviewDecaySeconds,
                runningStalledSeconds: Self.runningStalledSeconds
            )
            return EffectiveSession(
                sessionId: s.sessionId,
                state: state,
                bubbleText: SessionLogic.bubbleText(for: s, state: state),
                cwd: s.cwd,
                terminalPid: s.terminalPid,
                terminalApp: s.terminalApp,
                tty: s.tty,
                ts: s.ts,
                tasksDone: s.tasksDone,
                tasksTotal: s.tasksTotal,
                title: s.title,
                claudePid: s.claudePid,
                startedTs: s.startedTs
            )
        }.sorted { $0.ts < $1.ts }

        emitTransitions(for: effective)

        sessions = effective
        sessionCount = effective.count
        lastDecodeWarning = decodeWarning

        guard let winner = SessionLogic.winner(among: effective) else {
            aggregate = .idle
            bubbleText = ""
            tasksDone = nil
            tasksTotal = nil
            title = nil
            winningSessionId = nil
            return
        }
        aggregate = winner.state
        bubbleText = winner.bubbleText
        tasksDone = winner.tasksDone
        tasksTotal = winner.tasksTotal
        title = winner.title
        winningSessionId = winner.sessionId
    }

    var winningSession: EffectiveSession? {
        guard let winningSessionId else { return nil }
        return sessions.first { $0.sessionId == winningSessionId }
    }

    private func emitTransitions(for effective: [EffectiveSession]) {
        var seen: Set<String> = []
        for session in effective {
            seen.insert(session.sessionId)
            let previous = lastStateBySession[session.sessionId]
            if previous != session.state {
                let oldSession = previous.map { old in
                    var s = session
                    s.state = old
                    return s
                }
                stateTransitions.send((old: oldSession, new: session))
                lastStateBySession[session.sessionId] = session.state
            }
        }
        for goneId in lastStateBySession.keys where !seen.contains(goneId) {
            lastStateBySession.removeValue(forKey: goneId)
        }
    }

    private func emitSessionEnded(for status: SessionStatus, now: TimeInterval) {
        let state = SessionLogic.effectiveState(status: status, now: now, reviewDecaySeconds: Self.reviewDecaySeconds)
        sessionEnded.send(EffectiveSession(
            sessionId: status.sessionId, state: state,
            bubbleText: SessionLogic.bubbleText(for: status, state: state),
            cwd: status.cwd, terminalPid: status.terminalPid, terminalApp: status.terminalApp,
            tty: status.tty, ts: status.ts, tasksDone: status.tasksDone, tasksTotal: status.tasksTotal,
            title: status.title, claudePid: status.claudePid, startedTs: status.startedTs
        ))
        lastStateBySession.removeValue(forKey: status.sessionId)
    }

    func killSession(_ session: EffectiveSession) {
        if let pid = session.claudePid {
            kill(pid_t(pid), SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if kill(pid_t(pid), 0) == 0 {
                    kill(pid_t(pid), SIGKILL)
                }
            }
        }
        sessionEnded.send(session)
        lastStateBySession.removeValue(forKey: session.sessionId)
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent("\(session.sessionId).json")
        )
        refresh()
    }

    func killSession(sessionId: String) {
        guard let session = sessions.first(where: { $0.sessionId == sessionId }) else { return }
        killSession(session)
    }
}
