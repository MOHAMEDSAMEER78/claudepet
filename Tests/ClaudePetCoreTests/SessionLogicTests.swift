import Foundation
import Testing
@testable import ClaudePetCore

struct SessionLogicTests {
    private func status(
        id: String = "s1", state: PetState = .running, ts: TimeInterval = 1000,
        cwd: String? = "/Users/dev/my-project", tool: String? = nil,
        summary: String? = nil, action: String? = nil
    ) -> SessionStatus {
        SessionStatus(
            sessionId: id, state: state, cwd: cwd, tool: tool, summary: summary,
            action: action, ts: ts, terminalPid: nil, terminalApp: nil, tty: nil,
            tasksDone: nil, tasksTotal: nil, title: nil, claudePid: nil, startedTs: nil
        )
    }

    @Test func decodeStatusSucceedsForWellFormedData() {
        let json = """
        {"session_id":"s1","state":"running","ts":1000,"schema":1}
        """.data(using: .utf8)!
        switch SessionLogic.decodeStatus(data: json) {
        case .success(let status): #expect(status.sessionId == "s1")
        case .failure: Issue.record("expected success")
        }
    }

    @Test func decodeStatusSucceedsWhenSchemaFieldIsAbsent() {
        let json = """
        {"session_id":"s1","state":"running","ts":1000}
        """.data(using: .utf8)!
        switch SessionLogic.decodeStatus(data: json) {
        case .success: break
        case .failure: Issue.record("expected success - missing schema means schema 0, always supported")
        }
    }

    @Test func decodeStatusFailsForMalformedJSON() {
        let json = "not json".data(using: .utf8)!
        switch SessionLogic.decodeStatus(data: json) {
        case .success: Issue.record("expected failure")
        case .failure(let issue): #expect(issue == .malformed)
        }
    }

    @Test func decodeStatusFailsForNewerUnsupportedSchema() {
        let json = """
        {"session_id":"s1","state":"running","ts":1000,"schema":999}
        """.data(using: .utf8)!
        switch SessionLogic.decodeStatus(data: json) {
        case .success: Issue.record("expected failure")
        case .failure(let issue): #expect(issue == .unsupportedSchema(found: 999))
        }
    }

    @Test func reviewDecaysToIdleAfterWindow() {
        let s = status(state: .review, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 1021, reviewDecaySeconds: 20)
        #expect(result == .idle)
    }

    @Test func reviewStaysReviewWithinWindow() {
        let s = status(state: .review, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 1010, reviewDecaySeconds: 20)
        #expect(result == .review)
    }

    @Test func nonReviewStatesNeverDecay() {
        let s = status(state: .failed, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 999_999, reviewDecaySeconds: 20)
        #expect(result == .failed)
    }

    @Test func runningBecomesCheckingAfterStalledWindow() {
        let s = status(state: .running, ts: 1000)
        let result = SessionLogic.effectiveState(
            status: s, now: 1021, reviewDecaySeconds: 20, runningStalledSeconds: 20
        )
        #expect(result == .checking)
    }

    @Test func runningStaysRunningWithinStalledWindow() {
        let s = status(state: .running, ts: 1000)
        let result = SessionLogic.effectiveState(
            status: s, now: 1010, reviewDecaySeconds: 20, runningStalledSeconds: 20
        )
        #expect(result == .running)
    }

    @Test func runningNeverBecomesCheckingWhenNoStalledThresholdGiven() {
        let s = status(state: .running, ts: 1000)
        let result = SessionLogic.effectiveState(status: s, now: 999_999, reviewDecaySeconds: 20)
        #expect(result == .running)
    }

    @Test func staleAfterThreshold() {
        let s = status(ts: 1000)
        #expect(SessionLogic.isStale(status: s, now: 1000 + 1801, staleSeconds: 1800))
        #expect(!SessionLogic.isStale(status: s, now: 1000 + 1799, staleSeconds: 1800))
    }

    @Test func bubbleTextPrefersAction() {
        let s = status(cwd: "/x/my-project", tool: "Bash", summary: "npm test", action: "Running `npm test`")
        #expect(SessionLogic.bubbleText(for: s, state: .running) == "Running `npm test`")
    }

    @Test func bubbleTextFallsBackToCwdToolSummary() {
        let s = status(cwd: "/x/my-project", tool: "Bash", summary: "npm test", action: nil)
        #expect(SessionLogic.bubbleText(for: s, state: .running) == "my-project · Bash · npm test")
    }

    @Test func bubbleTextFallsBackToStateLabelWhenNothingElseAvailable() {
        let s = status(cwd: nil, tool: nil, summary: nil, action: nil)
        #expect(SessionLogic.bubbleText(for: s, state: .idle) == "Idle")
    }

    private func session(id: String, state: PetState, ts: TimeInterval) -> EffectiveSession {
        EffectiveSession(
            sessionId: id, state: state, bubbleText: "", cwd: nil, terminalPid: nil,
            terminalApp: nil, tty: nil, ts: ts, tasksDone: nil, tasksTotal: nil,
            title: nil, claudePid: nil
        )
    }

    @Test func winnerPicksHighestPriorityState() {
        let sessions = [
            session(id: "a", state: .idle, ts: 1),
            session(id: "b", state: .waitingPermission, ts: 2),
            session(id: "c", state: .failed, ts: 3),
        ]
        #expect(SessionLogic.winner(among: sessions)?.sessionId == "b")
    }

    @Test func winnerIsNilForEmptySessions() {
        #expect(SessionLogic.winner(among: []) == nil)
    }
}
