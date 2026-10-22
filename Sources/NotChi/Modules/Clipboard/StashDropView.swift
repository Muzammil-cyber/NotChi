import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drop target strip above the module content: shows stashed items as draggable chips.
struct StashDropView: View {
    let store: StashStore
    @State private var targeted = false
    private let settings = Settings.shared

    init(store: StashStore) { self.store = store }

    var body: some View {
        HStack(spacing: 6) {
            stashStrip
            // Phone send targets appear only for the platform(s) chosen in Settings.
            if let transfer = TransferCoordinator.shared {
                if settings.phonePlatform.usesAirDrop {
                    SendDropTarget(title: "iPhone", systemImage: "iphone") { transfer.sendToiPhone($0) }
                }
                if settings.phonePlatform.usesQuickShare {
                    SendDropTarget(title: "Android", systemImage: "candybarphone") { transfer.sendToAndroid($0) }
                }
            }
        }
    }

    private var stashStrip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(targeted ? 0.10 : 0.03))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(targeted ? 0.6 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [4]))
            if store.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Drop files, images or text to stash")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(targeted ? 0.9 : 0.45))
            } else {
                HStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(store.items) { StashChip(item: $0, store: store) }
                        }
                        .padding(.horizontal, 6)
                    }
                    if store.items.contains(where: { !$0.pinned }) {
                        Button("Clear") { store.clearUnpinned() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 10)
                            .help("Remove all unpinned items")
                    }
                }
            }
        }
        .frame(height: 56)
        .animation(.easeOut(duration: 0.12), value: targeted)
        .onDrop(of: [.fileURL, .image, .text, .url], isTargeted: $targeted) { providers in
            handle(providers)
            return true
        }
        .onChange(of: targeted) { _, value in NotchState.shared.holdOpen("stash-drop", value) }
    }

    /// A single drag usually carries several representations of the same thing (a file URL
    /// plus an image or text, sometimes repeated), so each drop is resolved to one kind:
    /// files win, then images, then text/links.
    private func handle(_ providers: [NSItemProvider]) {
        Task { @MainActor in
            let urls = await load(URL.self, from: providers)
            let files = urls.filter(\.isFileURL)
            if !files.isEmpty {
                files.forEach(store.addFile)
                return
            }
            let images = await load(NSImage.self, from: providers)
            if !images.isEmpty {
                images.forEach(store.addImage)
                return
            }
            if let link = urls.first {
                store.addText(link.absoluteString)
                return
            }
            for string in await load(String.self, from: providers) { store.addText(string) }
        }
    }

    private func load<T: _ObjectiveCBridgeable>(_ type: T.Type, from providers: [NSItemProvider]) async -> [T]
    where T._ObjectiveCType: NSItemProviderReading {
        var results: [T] = []
        for provider in providers where provider.canLoadObject(ofClass: T.self) {
            let value: T? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: T.self) { value, _ in continuation.resume(returning: value) }
            }
            if let value { results.append(value) }
        }
        return results
    }

    private func load(_ type: NSImage.Type, from providers: [NSItemProvider]) async -> [NSImage] {
        var results: [NSImage] = []
        for provider in providers where provider.canLoadObject(ofClass: NSImage.self) {
            let image: NSImage? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSImage.self) { value, _ in
                    continuation.resume(returning: value as? NSImage)
                }
            }
            if let image { results.append(image) }
        }
        return results
    }
}

private struct StashChip: View {
    let item: StashItem
    let store: StashStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            icon.frame(width: 34, height: 34)
            if item.kind == .text || item.kind == .link || item.kind == .file {
                Text(item.title)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 42)
        .background(.white.opacity(hovering ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 8))
        // Drag, click and right-click are handled in AppKit so we learn whether a drop landed.
        .overlay {
            StashDragSource(
                writer: { store.pasteboardWriter(for: item) },
                preview: { dragPreview },
                onClick: { store.copy(item) },
                menu: { contextMenu },
                onDragEnd: { droppedElsewhere in
                    if droppedElsewhere && !item.pinned { store.removeAfterDragOut(item) }
                })
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { store.remove(item) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Remove from stash")
                .offset(x: 5, y: -5)
            } else if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.7)).padding(3)
            }
        }
        .padding(.top, 5)
        .onHover { hovering = $0 }
        .help(item.pinned ? item.title : item.title + "\nDrag it out to use it; it leaves the stash unless pinned.")
    }

    private var dragPreview: NSImage? {
        guard let url = item.fileURL else { return nil }
        if item.kind == .image, let image = Thumbnails.image(at: url) { return image }
        return Self.typeIcon(for: url)
    }

    /// Icon from the file's type alone. `icon(forFile:)` would read the file itself, which can
    /// block the main thread on a folder-access prompt or an unreachable volume.
    static func typeIcon(for url: URL) -> NSImage {
        let type = url.pathExtension.isEmpty ? UTType.folder : (UTType(filenameExtension: url.pathExtension) ?? .data)
        return NSWorkspace.shared.icon(for: type)
    }

    private var contextMenu: NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(item.pinned ? "Unpin" : "Pin (keep after dragging out)") { store.togglePin(item) })
        menu.addItem(ClosureMenuItem("Copy") { store.copy(item) })
        if item.kind == .file {
            if item.storedFile == nil {
                menu.addItem(ClosureMenuItem("Copy into Stash") { store.copyIntoStash(item) })
            }
            menu.addItem(ClosureMenuItem("Reveal in Finder") { store.revealInFinder(item) })
        }
        if let url = item.fileURL, let transfer = TransferCoordinator.shared {
            if transfer.canSendToiPhone { menu.addItem(ClosureMenuItem("Send to iPhone (AirDrop)") { transfer.sendToiPhone([url]) }) }
            if transfer.canSendToAndroid { menu.addItem(ClosureMenuItem("Send to Android (Quick Share)") { transfer.sendToAndroid([url]) }) }
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Remove") { store.remove(item) })
        return menu
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .image:
            if let url = item.fileURL, let image = Thumbnails.image(at: url) {
                Image(nsImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: "photo").foregroundStyle(.white.opacity(0.6))
            }
        case .file:
            if let url = item.fileURL {
                Image(nsImage: Self.typeIcon(for: url)).resizable().scaledToFit()
            } else {
                Image(systemName: "doc").foregroundStyle(.white.opacity(0.6))
            }
        case .text:
            Image(systemName: "text.alignleft").foregroundStyle(.white.opacity(0.6))
        case .link:
            Image(systemName: "link").foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// "Send to iPhone / Android" drop target beside the stash. Accepts files only.
private struct SendDropTarget: View {
    let title: String
    let systemImage: String
    let send: ([URL]) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 15))
            Text(title).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.white.opacity(targeted ? 0.95 : 0.55))
        .frame(width: 64, height: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(targeted ? 0.12 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(.white.opacity(targeted ? 0.6 : 0.2), style: StrokeStyle(lineWidth: 1, dash: [4])))
        .help("Drop files here to send them to your \(title)")
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                    let url: URL? = await withCheckedContinuation { continuation in
                        _ = provider.loadObject(ofClass: URL.self) { value, _ in continuation.resume(returning: value) }
                    }
                    if let url, url.isFileURL { urls.append(url) }
                }
                send(urls)
            }
            return true
        }
        .onChange(of: targeted) { _, value in NotchState.shared.holdOpen("send-drop-\(title)", value) }
    }
}
