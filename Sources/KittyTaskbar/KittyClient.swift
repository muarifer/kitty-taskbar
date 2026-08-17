import AppKit
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - kitty @ ls JSON modelleri

struct KittyWindow: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let is_focused: Bool
}

struct KittyTab: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let is_focused: Bool
    let windows: [KittyWindow]
}

struct KittyOSWindow: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let is_focused: Bool
    let tabs: [KittyTab]
}

struct KittyInstance: Identifiable, Hashable, Sendable {
    let socket: String
    let osWindows: [KittyOSWindow]
    var id: String { socket }
}

// MARK: - Sürükle-bırak yükü

extension UTType {
    static let kittyTab = UTType(exportedAs: "com.muarifer.kitty-taskbar.tab")
}

struct TabRef: Codable, Hashable, Transferable, Sendable {
    let socket: String
    let tabId: Int
    let osWindowId: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .kittyTab)
    }
}

// MARK: - Durum ve hatalar

enum KittyStatus: Equatable, Sendable {
    case loading
    case ok
    case kittenMissing
    case notRunning
    case connectionFailed
}

enum KittyRunError: Error, Sendable, CustomStringConvertible {
    case kittenMissing
    case launchFailed(String)
    case timeout
    case commandFailed(Int)

    var description: String {
        switch self {
        case .kittenMissing: return L10n.errorKittenMissing
        case .launchFailed(let reason): return L10n.errorLaunchFailed(reason)
        case .timeout: return L10n.errorTimeout
        case .commandFailed(let code): return L10n.errorCommandFailed(code)
        }
    }
}

// MARK: - kitty remote control

enum Kitty {
    static let bundleID = "net.kovidgoyal.kitty"

    /// Bilinen konumlar + PATH üzerinden kitten ikilisini bulur.
    static let kittenPath: String? = {
        var candidates = [
            "/usr/local/bin/kitten",
            "/opt/homebrew/bin/kitten",
            "/opt/local/bin/kitten",
            "/Applications/kitty.app/Contents/MacOS/kitten",
            NSHomeDirectory() + "/Applications/kitty.app/Contents/MacOS/kitten",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates = path.split(separator: ":").map { String($0) + "/kitten" } + candidates
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// "/tmp/kitty-1234" veya "kitty-1234" biçimindeki soket yolundan pid'i çıkarır.
    static func pid(fromSocketPath path: String) -> pid_t? {
        let name = (path as NSString).lastPathComponent
        guard name.hasPrefix("kitty-"),
              let pid = pid_t(name.dropFirst("kitty-".count)),
              pid > 0
        else { return nil }
        return pid
    }

    /// listen_on unix:/tmp/kitty-{kitty_pid} ayarına göre canlı soketleri bulur.
    static func sockets() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/tmp") else { return [] }
        return entries.compactMap { name -> String? in
            let path = "/tmp/" + name
            // Adında geçerli bir pid olmalı ve o süreç hâlâ yaşıyor olmalı
            guard let pid = pid(fromSocketPath: path), kill(pid, 0) == 0 else { return nil }
            var st = stat()
            guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFSOCK else { return nil }
            return path
        }.sorted()
    }

    /// Zaman aşımı korumalı, engelleyen çağrı — yalnızca arka plan görevlerinden kullanın.
    static func run(socket: String, _ args: [String], timeout: TimeInterval = 5) -> Result<Data, KittyRunError> {
        guard let kitten = kittenPath else { return .failure(.kittenMissing) }
        return runProcess(executable: kitten, arguments: ["@", "--to", "unix:\(socket)"] + args, timeout: timeout)
    }

    /// Testlerde de kullanılan çekirdek: verilen ikiliyi zaman aşımıyla çalıştırır.
    static func runProcess(executable: String, arguments: [String], timeout: TimeInterval) -> Result<Data, KittyRunError> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .failure(.launchFailed(error.localizedDescription)) }

        // Çıktıyı ayrı iş parçacığında oku (pipe tamponu dolarsa kilitlenmesin)
        nonisolated(unsafe) var data = Data()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            p.waitUntilExit()
            exited.signal()
        }
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            let pid = p.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if p.isRunning { kill(pid, SIGKILL) }
            }
            return .failure(.timeout)
        }
        readDone.wait()

        guard p.terminationStatus == 0 else { return .failure(.commandFailed(Int(p.terminationStatus))) }
        return .success(data)
    }

    struct Snapshot: Sendable {
        let instances: [KittyInstance]
        let status: KittyStatus
    }

    /// kitty @ ls çıktısını çözer; geçersiz JSON'da nil döner.
    static func decodeOSWindows(_ data: Data) -> [KittyOSWindow]? {
        try? JSONDecoder().decode([KittyOSWindow].self, from: data)
    }

    static func snapshot() -> Snapshot {
        guard kittenPath != nil else { return Snapshot(instances: [], status: .kittenMissing) }
        let socks = sockets()
        guard !socks.isEmpty else { return Snapshot(instances: [], status: .notRunning) }

        var instances: [KittyInstance] = []
        var anyFailure = false
        for socket in socks {
            switch run(socket: socket, ["ls"]) {
            case .success(let data):
                if let osWindows = decodeOSWindows(data) {
                    if !osWindows.isEmpty {
                        instances.append(KittyInstance(socket: socket, osWindows: osWindows))
                    }
                } else {
                    anyFailure = true
                }
            case .failure:
                anyFailure = true
            }
        }
        if instances.isEmpty {
            return Snapshot(instances: [], status: anyFailure ? .connectionFailed : .notRunning)
        }
        return Snapshot(instances: instances, status: .ok)
    }

    /// Soket adındaki pid üzerinden doğru kitty sürecini öne getirir;
    /// bulunamazsa bundle ID ile etkinleştirir.
    @MainActor
    static func activateApp(socket: String? = nil) {
        if let socket,
           let pid = pid(fromSocketPath: socket),
           let running = NSRunningApplication(processIdentifier: pid) {
            if #available(macOS 14.0, *) {
                running.activate()
            } else {
                running.activate(options: [.activateIgnoringOtherApps])
            }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Model

@MainActor
final class TaskbarModel: ObservableObject {
    typealias SnapshotProvider = @Sendable () -> Kitty.Snapshot
    typealias Runner = @Sendable (_ socket: String, _ args: [String]) -> Result<Data, KittyRunError>
    typealias Activator = @MainActor (_ socket: String) -> Void

    @Published var instances: [KittyInstance] = []
    @Published var status: KittyStatus = .loading
    @Published var lastError: String?

    private let snapshotProvider: SnapshotProvider
    private let runner: Runner
    private let activator: Activator
    // Eski başlayan bir refresh görevinin daha yeni sonucu ezmesini önler
    private var refreshGeneration = 0

    init(
        snapshotProvider: @escaping SnapshotProvider = { Kitty.snapshot() },
        runner: @escaping Runner = { Kitty.run(socket: $0, $1) },
        activator: @escaping Activator = { Kitty.activateApp(socket: $0) }
    ) {
        self.snapshotProvider = snapshotProvider
        self.runner = runner
        self.activator = activator
    }

    func refresh() {
        Task { await refreshNow() }
    }

    func refreshNow() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let provider = snapshotProvider
        let snapshot = await Task.detached(priority: .userInitiated) { provider() }.value
        guard generation == refreshGeneration else { return }
        instances = snapshot.instances
        status = snapshot.status
    }

    func focusTab(_ tab: KittyTab, socket: String) async -> Bool {
        await runAction(socket: socket, ["focus-tab", "--match", "id:\(tab.id)"], activateAfter: true)
    }

    func focusWindow(_ window: KittyWindow, socket: String) async -> Bool {
        await runAction(socket: socket, ["focus-window", "--match", "id:\(window.id)"], activateAfter: true)
    }

    /// Sekmeyi hedef OS penceresine taşır. Bırakma kabulü için senkron true döner;
    /// asıl iş arka planda yapılır, hata olursa lastError ile gösterilir.
    func move(_ refs: [TabRef], toOSWindow target: KittyOSWindow, in instance: KittyInstance) -> Bool {
        guard let ref = refs.first,
              ref.socket == instance.socket, // detach-tab yalnızca aynı kitty kopyası içinde çalışır
              ref.osWindowId != target.id,
              let anchor = target.tabs.first
        else { return false }
        Task {
            await runAction(
                socket: ref.socket,
                ["detach-tab", "--match", "id:\(ref.tabId)", "--target-tab", "id:\(anchor.id)"],
                activateAfter: false
            )
        }
        return true
    }

    /// Sekmeyi yeni bir OS penceresine ayırır.
    func detachToNew(_ refs: [TabRef]) -> Bool {
        guard let ref = refs.first else { return false }
        Task {
            await runAction(socket: ref.socket, ["detach-tab", "--match", "id:\(ref.tabId)"], activateAfter: false)
        }
        return true
    }

    private func runAction(socket: String, _ args: [String], activateAfter: Bool) async -> Bool {
        let runner = runner
        let result = await Task.detached(priority: .userInitiated) { runner(socket, args) }.value
        switch result {
        case .success:
            lastError = nil
            if activateAfter { activator(socket) }
            await refreshNow()
            return true
        case .failure(let error):
            lastError = error.description
            await refreshNow()
            return false
        }
    }
}
