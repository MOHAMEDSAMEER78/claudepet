import AppKit
import ClaudePetCore

enum SoundPlayer {
    static func play(for state: PetState) {
        guard AppSettings.shared.soundEnabled else { return }
        switch state {
        case .waitingPermission: NSSound(named: "Ping")?.play()
        case .review: NSSound(named: "Glass")?.play()
        case .failed: NSSound(named: "Basso")?.play()
        case .idle, .running, .checking: break
        }
    }
}
