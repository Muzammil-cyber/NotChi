import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drop target strip above the module content: shows stashed items as draggable chips.
struct StashDropView: View {
    let store: StashStore
    @State private var targeted = false

    var body: some View {
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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.items) { StashChip(item: $0, store: store) }
                    }
                    .padding(.horizontal, 6)
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

    private func handle(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    Task { @MainActor in
                        if let url, url.isFileURL { store.addFile(url) }
                        else if provider.canLoadObject(ofClass: NSImage.self) { loadImage(provider) }
                        else if let url { store.addText(url.absoluteString) }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                loadImage(provider)
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { string, _ in
                    Task { @MainActor in if let string { store.addText(string) } }
                }
            }
        }
    }

    private func loadImage(_ provider: NSItemProvider) {
        _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
            Task { @MainActor in if let image = image as? NSImage { store.addImage(image) } }
        }
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
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white.opacity(0.7)).padding(3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture { store.copy(item) }
        .onDrag {
            NotchState.shared.holdOpen("stash-drag", true)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: .milliseconds(150)) }
                NotchState.shared.holdOpen("stash-drag", false)
            }
            return store.itemProvider(for: item)
        }
        .help(item.title)
        .contextMenu {
            Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Copy") { store.copy(item) }
            if item.kind == .file {
                if item.storedFile == nil { Button("Copy into Stash") { store.copyIntoStash(item) } }
                Button("Reveal in Finder") { store.revealInFinder(item) }
            }
            Divider()
            Button("Remove", role: .destructive) { store.remove(item) }
        }
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
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
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
