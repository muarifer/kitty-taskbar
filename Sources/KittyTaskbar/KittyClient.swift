import AppKit
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - kitty @ ls JSON modelleri

struct KittyWindow: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let is_focused: Bool
}

struct KittyTab: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let is_focused: Bool
    let windows: [KittyWindow]
}

struct KittyOSWindow: Decodable, Identifiable, Hashable {
    let id: Int
    let is_focused: Bool
    let tabs: [KittyTab]
}

struct KittyInstance: Identifiable, Hashable {
    let socket: String
    let osWindows: [KittyOSWindow]
    var id: String { socket }
}

// MARK: - Sürükle-bırak yükü

extension UTType {
    static let kittyTab = UTType(exportedAs: "com.muarifer.kitty-taskbar.tab")
}

struct TabRef: Codable, Hashable, Transferable {
    let socket: String
    let tabId: Int
    let osWindowId: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .kittyTab)
    }
}

// MARK: - kitty remote control

enum Kitty {
    static let bundleID = "net.kovidgoyal.kitty"

    static let kittenPath: String = {
        let candidates = [
            "/usr/local/bin/kitten",
            "/opt/homebrew/bin/kitten",
            "/Applications/kitty.app/Contents/MacOS/kitten",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "kitten"
    }()

    /// listen_on unix:/tmp/kitty-{kitty_pid} ayarına göre canlı soketleri bulur.
    static func sockets() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else { return [] }
        return entries.compactMap { name -> String? in
            guard name.hasPrefix("kitty-") else { return nil }
            let path = "/tmp/" + name
            var st = stat()
            guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFSOCK else { return nil }
            // Soket adındaki pid hâlâ yaşıyor mu? (eski/ölü soketleri ele)
            if let pid = pid_t(name.dropFirst("kitty-".count)), kill(pid, 0) != 0 { return nil }
            return path
        }.sorted()
    }

    @discardableResult
    static func run(socket: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: kittenPath)
        p.arguments = ["@", "--to", "unix:\(socket)"] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }

    static func list(socket: String) -> [KittyOSWindow] {
        guard let data = run(socket: socket, ["ls"]) else { return [] }
        return (try? JSONDecoder().decode([KittyOSWindow].self, from: data)) ?? []
    }

    static func activateApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Model

@MainActor
final class TaskbarModel: ObservableObject {
    @Published var instances: [KittyInstance] = []

    func refresh() {
        instances = Kitty.sockets()
            .map { KittyInstance(socket: $0, osWindows: Kitty.list(socket: $0)) }
            .filter { !$0.osWindows.isEmpty }
    }

    func focusTab(_ tab: KittyTab, socket: String) {
        Kitty.run(socket: socket, ["focus-tab", "--match", "id:\(tab.id)"])
        Kitty.activateApp()
    }

    func focusWindow(_ window: KittyWindow, socket: String) {
        Kitty.run(socket: socket, ["focus-window", "--match", "id:\(window.id)"])
        Kitty.activateApp()
    }

    /// Sekmeyi hedef OS penceresine taşır. Başarılıysa true döner.
    func move(_ refs: [TabRef], toOSWindow target: KittyOSWindow, in instance: KittyInstance) -> Bool {
        guard let ref = refs.first,
              ref.socket == instance.socket, // detach-tab yalnızca aynı kitty kopyası içinde çalışır
              ref.osWindowId != target.id,
              let anchor = target.tabs.first
        else { return false }
        Kitty.run(socket: ref.socket, ["detach-tab", "--match", "id:\(ref.tabId)", "--target-tab", "id:\(anchor.id)"])
        refresh()
        return true
    }

    /// Sekmeyi yeni bir OS penceresine ayırır.
    func detachToNew(_ refs: [TabRef]) -> Bool {
        guard let ref = refs.first else { return false }
        Kitty.run(socket: ref.socket, ["detach-tab", "--match", "id:\(ref.tabId)"])
        refresh()
        return true
    }
}
