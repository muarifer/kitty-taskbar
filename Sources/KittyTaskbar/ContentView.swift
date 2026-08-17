import SwiftUI

struct ContentView: View {
    @ObservedObject var model: TaskbarModel
    var close: () -> Void

    private var totalRows: Int {
        var count = 0
        for instance in model.instances {
            for osWindow in instance.osWindows {
                for tab in osWindow.tabs {
                    count += 1
                    if tab.windows.count > 1 { count += tab.windows.count }
                }
            }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch model.status {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            case .kittenMissing:
                statusText("kitten komutu bulunamadı — kitty kurulu mu?")
            case .notRunning:
                statusText("Kitty çalışmıyor")
            case .connectionFailed:
                statusText(
                    "Kitty'ye bağlanılamadı. kitty.conf içinde şunlar ayarlı mı?\n" +
                    "allow_remote_control yes\nlisten_on unix:/tmp/kitty-{kitty_pid}"
                )
            case .ok:
                if totalRows > 16 {
                    ScrollView {
                        sections
                    }
                    .frame(height: 480)
                } else {
                    sections
                }
                NewWindowDropZone(model: model)
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Button("Kitty'yi Aç") {
                    Kitty.activateApp()
                    close()
                }
                Spacer()
                Button("Çıkış") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 320)
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.instances) { instance in
                ForEach(Array(instance.osWindows.enumerated()), id: \.element.id) { index, osWindow in
                    WindowSection(
                        model: model,
                        instance: instance,
                        osWindow: osWindow,
                        title: sectionTitle(instanceIndex: instanceIndex(of: instance), windowIndex: index),
                        close: close
                    )
                }
            }
        }
    }

    private func statusText(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    private func instanceIndex(of instance: KittyInstance) -> Int {
        model.instances.firstIndex(of: instance) ?? 0
    }

    private func sectionTitle(instanceIndex: Int, windowIndex: Int) -> String {
        model.instances.count > 1
            ? "Kitty \(instanceIndex + 1) · Pencere \(windowIndex + 1)"
            : "Pencere \(windowIndex + 1)"
    }
}

// MARK: - OS penceresi bölümü (bırakma hedefi)

private struct WindowSection: View {
    @ObservedObject var model: TaskbarModel
    let instance: KittyInstance
    let osWindow: KittyOSWindow
    let title: String
    var close: () -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(osWindow.tabs) { tab in
                TabRow(model: model, instance: instance, osWindow: osWindow, tab: tab, close: close)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .dropDestination(for: TabRef.self) { refs, _ in
            model.move(refs, toOSWindow: osWindow, in: instance)
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Sekme satırı (sürüklenebilir)

private struct TabRow: View {
    @ObservedObject var model: TaskbarModel
    let instance: KittyInstance
    let osWindow: KittyOSWindow
    let tab: KittyTab
    var close: () -> Void

    @State private var hovering = false

    private var isActive: Bool { tab.is_focused && osWindow.is_focused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(displayTitle(tab.title))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                Task {
                    if await model.focusTab(tab, socket: instance.socket) { close() }
                }
            }
            .draggable(TabRef(socket: instance.socket, tabId: tab.id, osWindowId: osWindow.id)) {
                Label(displayTitle(tab.title), systemImage: "macwindow")
                    .padding(6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            }

            // Sekmede birden fazla bölme (split) varsa altına küçük satırlar olarak listele
            if tab.windows.count > 1 {
                ForEach(tab.windows) { window in
                    SplitRow(model: model, instance: instance, window: window, close: close)
                }
            }
        }
    }
}

private struct SplitRow: View {
    @ObservedObject var model: TaskbarModel
    let instance: KittyInstance
    let window: KittyWindow
    var close: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
            Text(displayTitle(window.title))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
        }
        .padding(.leading, 24)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            Task {
                if await model.focusWindow(window, socket: instance.socket) { close() }
            }
        }
    }
}

// MARK: - Yeni pencereye ayırma alanı

private struct NewWindowDropZone: View {
    @ObservedObject var model: TaskbarModel
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.caption)
            Text("Yeni pencereye ayırmak için buraya bırak")
                .font(.caption)
        }
        .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
        .dropDestination(for: TabRef.self) { refs, _ in
            model.detachToNew(refs)
        } isTargeted: { isTargeted = $0 }
    }
}

private func displayTitle(_ s: String, max: Int = 50) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return "(başlıksız)" }
    return t.count > max ? String(t.prefix(max)) + "…" : t
}
