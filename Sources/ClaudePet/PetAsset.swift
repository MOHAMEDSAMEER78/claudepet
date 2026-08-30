import AppKit
import ClaudePetCore

struct PetManifest: Codable {
    var id: String?
    var displayName: String?
    var description: String?
    var spritesheetPath: String?

    var name: String?
    var spritesheet: String?
    var frameWidth: Int?
    var frameHeight: Int?
    var fps: Double?
    var rows: [String: Int]?

    var resolvedName: String? { displayName ?? name }
    var resolvedSpritesheet: String? { spritesheetPath ?? spritesheet }

    static let defaultRowOrder = [
        "idle", "running-right", "running-left", "waving",
        "jumping", "failed", "waiting", "running", "review",
        "stretching", "looking-around",
    ]
}

struct PetAsset {
    let name: String
    let fps: Double
    let frames: [String: [NSImage]]

    func hasRow(_ name: String) -> Bool {
        !(frames[name]?.isEmpty ?? true)
    }

    static func rowName(for state: PetState) -> String {
        switch state {
        case .idle: return "idle"
        case .checking: return "idle"
        case .running: return "running"
        case .waitingPermission: return "waiting"
        case .review: return "review"
        case .failed: return "failed"
        }
    }

    func frames(for state: PetState) -> [NSImage]? {
        let row = Self.rowName(for: state)
        if let f = frames[row], !f.isEmpty { return f }
        return frames["idle"]
    }

    func frames(row: String) -> [NSImage]? {
        frames[row]
    }
}

enum PetAssetLoader {
    static func searchDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".claude/pets", isDirectory: true),
            home.appendingPathComponent(".codex/pets", isDirectory: true),
        ]
    }

    static func availablePets() -> [URL] {
        var found: [URL] = []
        for dir in searchDirectories() {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }
            for entry in entries {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }
                if FileManager.default.fileExists(atPath: entry.appendingPathComponent("pet.json").path) {
                    found.append(entry)
                }
            }
        }
        return found
    }

    private static func cellHasContent(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int) -> Bool {
        let samples = 5
        for sx in 0..<samples {
            for sy in 0..<samples {
                let px = x + (w * sx) / samples + w / (samples * 2)
                let py = y + (h * sy) / samples + h / (samples * 2)
                if px >= rep.pixelsWide || py >= rep.pixelsHigh { continue }
                if let color = rep.colorAt(x: px, y: py), color.alphaComponent > 0.05 {
                    return true
                }
            }
        }
        return false
    }

    static func load(from dir: URL) -> PetAsset? {
        let manifestURL = dir.appendingPathComponent("pet.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data)
        else { return nil }

        let sheetURL: URL
        if let explicit = manifest.resolvedSpritesheet {
            sheetURL = dir.appendingPathComponent(explicit)
        } else {
            let webp = dir.appendingPathComponent("spritesheet.webp")
            let png = dir.appendingPathComponent("spritesheet.png")
            sheetURL = FileManager.default.fileExists(atPath: webp.path) ? webp : png
        }
        guard let sheetImage = NSImage(contentsOf: sheetURL),
              let cgSheet = sheetImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let frameW = manifest.frameWidth ?? 192
        let frameH = manifest.frameHeight ?? 208
        let cols = cgSheet.width / frameW
        let rowOrder = PetManifest.defaultRowOrder
        let rep = NSBitmapImageRep(cgImage: cgSheet)
        let explicitRows = manifest.rows

        var framesByRow: [String: [NSImage]] = [:]
        for (rowIndex, rowName) in rowOrder.enumerated() {
            let count: Int
            if let explicit = explicitRows?[rowName] {
                count = explicit
            } else {
                var detected = 0
                for col in 0..<cols {
                    let hasContent = cellHasContent(
                        rep, x: col * frameW, y: rowIndex * frameH, w: frameW, h: frameH
                    )
                    if !hasContent { break }
                    detected += 1
                }
                count = detected
            }
            guard count > 0 else { continue }

            var images: [NSImage] = []
            for col in 0..<count {
                let rect = CGRect(x: col * frameW, y: rowIndex * frameH, width: frameW, height: frameH)
                guard let cropped = cgSheet.cropping(to: rect) else { continue }
                images.append(NSImage(cgImage: cropped, size: NSSize(width: frameW, height: frameH)))
            }
            if !images.isEmpty { framesByRow[rowName] = images }
        }

        guard !framesByRow.isEmpty else { return nil }
        return PetAsset(
            name: manifest.resolvedName ?? dir.lastPathComponent,
            fps: manifest.fps ?? 8,
            frames: framesByRow
        )
    }
}
