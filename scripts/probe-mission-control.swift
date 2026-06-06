import CoreGraphics
import Darwin
import Foundation

private typealias SendFn = @convention(c) (CFString, Int32) -> Int32

private let coreDockSend: SendFn? = {
    let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    if let p = dlsym(rtldDefault, "CoreDockSendNotification") {
        return unsafeBitCast(p, to: SendFn.self)
    }
    let candidates = [
        "/System/Library/PrivateFrameworks/CoreDock.framework/CoreDock",
        "/System/Library/PrivateFrameworks/CoreDock.framework/Versions/A/CoreDock",
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices",
        "/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox",
    ]
    for path in candidates {
        guard let h = dlopen(path, RTLD_NOW) else { continue }
        if let p = dlsym(h, "CoreDockSendNotification") {
            return unsafeBitCast(p, to: SendFn.self)
        }
    }
    return nil
}()

struct WindowRow {
    let id: Int
    let layer: Int
    let owner: String
    let title: String
    let rect: CGRect
}

func snapshot() -> [WindowRow] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    return raw.map { dict in
        let bounds = dict[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        return WindowRow(
            id: dict[kCGWindowNumber as String] as? Int ?? -1,
            layer: dict[kCGWindowLayer as String] as? Int ?? -1,
            owner: dict[kCGWindowOwnerName as String] as? String ?? "?",
            title: dict[kCGWindowName as String] as? String ?? "",
            rect: CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
        )
    }
}

func pad(_ s: String, _ len: Int) -> String {
    if s.count >= len { return String(s.prefix(len)) }
    return s + String(repeating: " ", count: len - s.count)
}

func rectStr(_ r: CGRect) -> String {
    String(format: "(%6.0f,%6.0f, %6.0f×%6.0f)", r.minX, r.minY, r.width, r.height)
}

func dump(label: String, rows: [WindowRow]) {
    print("=== \(label) — \(rows.count) windows ===")
    let sorted = rows.sorted {
        if $0.layer != $1.layer { return $0.layer < $1.layer }
        if $0.owner != $1.owner { return $0.owner < $1.owner }
        return $0.id < $1.id
    }
    for r in sorted {
        let title = r.title.isEmpty ? "" : " \"\(r.title.prefix(40))\""
        let idCol = pad(String(r.id), 8)
        let layerCol = pad(String(r.layer), 5)
        let ownerCol = pad(r.owner, 22)
        print("  id=\(idCol) layer=\(layerCol) owner=\(ownerCol) rect=\(rectStr(r.rect))\(title)")
    }
}

guard let send = coreDockSend else {
    fputs("CoreDockSendNotification unavailable — cannot probe.\n", stderr)
    exit(1)
}

let before = snapshot()
dump(label: "BEFORE", rows: before)

print("\n>> opening Mission Control")
_ = send("com.apple.expose.awake" as CFString, 0)
Thread.sleep(forTimeInterval: 0.6)

let during = snapshot()
dump(label: "DURING MC", rows: during)

print("\n>> closing Mission Control")
_ = send("com.apple.expose.awake" as CFString, 0)
Thread.sleep(forTimeInterval: 0.3)

let after = snapshot()
dump(label: "AFTER", rows: after)

let beforeByID = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0) })
print("\n=== DIFF (windows present in BOTH BEFORE and DURING) ===")
var changed = 0
for w in during {
    guard let b = beforeByID[w.id] else { continue }
    if b.rect == w.rect { continue }
    changed += 1
    let ownerCol = pad(w.owner, 22)
    print("  id=\(pad(String(w.id), 8)) owner=\(ownerCol)  before=\(rectStr(b.rect))  during=\(rectStr(w.rect))")
}
print(">> \(changed) window(s) changed frame while MC was active")
