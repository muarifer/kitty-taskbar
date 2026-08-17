import XCTest
@testable import KittyTaskbar

// MARK: - Soket adı ayrıştırma

final class SocketParsingTests: XCTestCase {
    func testValidSocketPath() {
        XCTAssertEqual(Kitty.pid(fromSocketPath: "/tmp/kitty-1234"), 1234)
    }

    func testBareName() {
        XCTAssertEqual(Kitty.pid(fromSocketPath: "kitty-42"), 42)
    }

    func testNonNumericPid() {
        XCTAssertNil(Kitty.pid(fromSocketPath: "/tmp/kitty-abc"))
    }

    func testEmptyPid() {
        XCTAssertNil(Kitty.pid(fromSocketPath: "/tmp/kitty-"))
    }

    func testWrongPrefix() {
        XCTAssertNil(Kitty.pid(fromSocketPath: "/tmp/mykitty-12"))
    }

    func testNegativePid() {
        XCTAssertNil(Kitty.pid(fromSocketPath: "/tmp/kitty--5"))
    }
}

// MARK: - kitty @ ls JSON çözümü

final class DecodeTests: XCTestCase {
    func testDecodeRepresentativeLsOutput() throws {
        let json = Data("""
        [{"id": 1, "is_focused": true, "platform_window_id": 55, "tabs": [
            {"id": 7, "title": "vim", "is_focused": true, "layout": "stack",
             "windows": [{"id": 3, "title": "vim main.swift", "is_focused": true, "pid": 999}]}
        ]}]
        """.utf8)
        let osWindows = try XCTUnwrap(Kitty.decodeOSWindows(json))
        XCTAssertEqual(osWindows.count, 1)
        XCTAssertEqual(osWindows[0].id, 1)
        XCTAssertEqual(osWindows[0].tabs[0].windows[0].title, "vim main.swift")
    }

    func testDecodeInvalidJSON() {
        XCTAssertNil(Kitty.decodeOSWindows(Data("not json".utf8)))
    }

    func testDecodeMissingRequiredField() {
        XCTAssertNil(Kitty.decodeOSWindows(Data("[{\"id\": 1}]".utf8)))
    }
}

// MARK: - Süreç çalıştırma ve zaman aşımı

final class RunProcessTests: XCTestCase {
    func testSuccessCapturesOutput() {
        let result = Kitty.runProcess(executable: "/bin/echo", arguments: ["hello"], timeout: 5)
        guard case .success(let data) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    }

    func testNonZeroExitFails() {
        let result = Kitty.runProcess(executable: "/usr/bin/false", arguments: [], timeout: 5)
        guard case .failure(.commandFailed(let code)) = result else {
            return XCTFail("expected commandFailed, got \(result)")
        }
        XCTAssertEqual(code, 1)
    }

    func testTimeoutKillsProcess() {
        let start = Date()
        let result = Kitty.runProcess(executable: "/bin/sleep", arguments: ["10"], timeout: 0.3)
        guard case .failure(.timeout) = result else {
            return XCTFail("expected timeout, got \(result)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "timeout should not wait for the process")
    }

    func testMissingExecutableFails() {
        let result = Kitty.runProcess(executable: "/nonexistent/binary", arguments: [], timeout: 1)
        guard case .failure(.launchFailed) = result else {
            return XCTFail("expected launchFailed, got \(result)")
        }
    }
}

// MARK: - Model durum geçişleri

@MainActor
final class TaskbarModelTests: XCTestCase {
    private func sampleInstance(socket: String = "/tmp/kitty-1") -> KittyInstance {
        KittyInstance(socket: socket, osWindows: [
            KittyOSWindow(id: 1, is_focused: true, tabs: [
                KittyTab(id: 10, title: "tab", is_focused: true, windows: [
                    KittyWindow(id: 100, title: "win", is_focused: true),
                ]),
            ]),
            KittyOSWindow(id: 2, is_focused: false, tabs: [
                KittyTab(id: 20, title: "tab2", is_focused: false, windows: []),
            ]),
        ])
    }

    private func makeModel(
        snapshot: Kitty.Snapshot,
        runner: @escaping TaskbarModel.Runner = { _, _ in .success(Data()) },
        activator: @escaping TaskbarModel.Activator = { _ in }
    ) -> TaskbarModel {
        TaskbarModel(snapshotProvider: { snapshot }, runner: runner, activator: activator)
    }

    func testRefreshPublishesSnapshot() async {
        let instance = sampleInstance()
        let model = makeModel(snapshot: Kitty.Snapshot(instances: [instance], status: .ok))
        XCTAssertEqual(model.status, .loading)
        await model.refreshNow()
        XCTAssertEqual(model.status, .ok)
        XCTAssertEqual(model.instances, [instance])
    }

    func testRefreshNotRunning() async {
        let model = makeModel(snapshot: Kitty.Snapshot(instances: [], status: .notRunning))
        await model.refreshNow()
        XCTAssertEqual(model.status, .notRunning)
        XCTAssertTrue(model.instances.isEmpty)
    }

    func testFocusTabSuccessActivatesAndClearsError() async {
        let instance = sampleInstance()
        let activated = expectation(description: "activated")
        let model = makeModel(
            snapshot: Kitty.Snapshot(instances: [instance], status: .ok),
            runner: { socket, args in
                XCTAssertEqual(socket, instance.socket)
                XCTAssertEqual(args, ["focus-tab", "--match", "id:10"])
                return .success(Data())
            },
            activator: { socket in
                XCTAssertEqual(socket, instance.socket)
                activated.fulfill()
            }
        )
        let ok = await model.focusTab(instance.osWindows[0].tabs[0], socket: instance.socket)
        XCTAssertTrue(ok)
        XCTAssertNil(model.lastError)
        await fulfillment(of: [activated], timeout: 2)
    }

    func testFocusTabFailureSetsErrorWithoutActivating() async {
        let model = makeModel(
            snapshot: Kitty.Snapshot(instances: [], status: .connectionFailed),
            runner: { _, _ in .failure(.timeout) },
            activator: { _ in XCTFail("must not activate on failure") }
        )
        let tab = KittyTab(id: 1, title: "t", is_focused: false, windows: [])
        let ok = await model.focusTab(tab, socket: "/tmp/kitty-1")
        XCTAssertFalse(ok)
        XCTAssertNotNil(model.lastError)
        XCTAssertEqual(model.status, .connectionFailed)
    }

    func testMoveRejectsCrossInstanceDrop() {
        let instance = sampleInstance()
        let model = makeModel(
            snapshot: Kitty.Snapshot(instances: [instance], status: .ok),
            runner: { _, _ in XCTFail("must not run for a rejected drop"); return .success(Data()) }
        )
        let foreign = TabRef(socket: "/tmp/kitty-OTHER", tabId: 10, osWindowId: 1)
        XCTAssertFalse(model.move([foreign], toOSWindow: instance.osWindows[1], in: instance))
    }

    func testMoveRejectsSameWindowDrop() {
        let instance = sampleInstance()
        let model = makeModel(snapshot: Kitty.Snapshot(instances: [instance], status: .ok))
        let ref = TabRef(socket: instance.socket, tabId: 10, osWindowId: 1)
        XCTAssertFalse(model.move([ref], toOSWindow: instance.osWindows[0], in: instance))
    }

    func testMoveSendsDetachCommand() async {
        let instance = sampleInstance()
        let ran = expectation(description: "runner called")
        let model = makeModel(
            snapshot: Kitty.Snapshot(instances: [instance], status: .ok),
            runner: { _, args in
                XCTAssertEqual(args, ["detach-tab", "--match", "id:10", "--target-tab", "id:20"])
                ran.fulfill()
                return .success(Data())
            }
        )
        let ref = TabRef(socket: instance.socket, tabId: 10, osWindowId: 1)
        XCTAssertTrue(model.move([ref], toOSWindow: instance.osWindows[1], in: instance))
        await fulfillment(of: [ran], timeout: 2)
    }

    func testDetachToNewSendsCommandWithoutTarget() async {
        let instance = sampleInstance()
        let ran = expectation(description: "runner called")
        let model = makeModel(
            snapshot: Kitty.Snapshot(instances: [instance], status: .ok),
            runner: { _, args in
                XCTAssertEqual(args, ["detach-tab", "--match", "id:10"])
                ran.fulfill()
                return .success(Data())
            }
        )
        let ref = TabRef(socket: instance.socket, tabId: 10, osWindowId: 1)
        XCTAssertTrue(model.detachToNew([ref]))
        await fulfillment(of: [ran], timeout: 2)
    }
}
