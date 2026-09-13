import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = PracticeModel()
    @State private var showingImporter = false

    var body: some View {
        NavigationSplitView {
            LibraryView(model: model, showingImporter: $showingImporter)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            PracticeView(model: model)
        }
        .frame(minWidth: 900, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ConnectionButton(model: model)
            }
            ToolbarItem {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import MIDI", systemImage: "square.and.arrow.down")
                }
                .help("Import one or more MIDI files")
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.midi],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): model.importSongs(urls: urls)
            case .failure(let error): model.reportImportFailure(error)
            }
        }
        .onAppear {
            // Connect on its own — there's only one keyboard to connect to.
            model.piano.refreshDestinations()
            model.connect()
        }
        // Turn the lights off on the way out.
        .onDisappear { model.stop() }
    }
}

struct ConnectionButton: View {
    let model: PracticeModel

    var body: some View {
        Button {
            if model.piano.status.isConnected {
                model.stop()
                model.piano.disconnect()
            } else {
                model.connect()
            }
        } label: {
            Label(
                model.piano.status.isConnected ? "Connected" : "Connect",
                systemImage: model.piano.status.isConnected
                    ? "pianokeys.inverse" : "pianokeys"
            )
            .foregroundStyle(model.piano.status.isConnected ? .green : .primary)
        }
        .help(model.piano.status.description)
    }
}

struct LibraryView: View {
    let model: PracticeModel
    @Binding var showingImporter: Bool
    @State private var isTargeted = false

    var body: some View {
        List(selection: Binding(
            get: { model.selectedSong },
            set: { if let song = $0 { model.select(song) } }
        )) {
            Section("Songs") {
                ForEach(model.songs) { song in
                    SongRow(song: song)
                        .tag(song)
                        .contextMenu {
                            Button("Remove", systemImage: "trash") { model.remove(song) }
                        }
                }
                if model.songs.isEmpty {
                    emptyState
                }
            }
        }
        .listStyle(.sidebar)
        // Dropping files here is the quickest way to add music.
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            loadDroppedFiles(providers)
            return true
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.tint, lineWidth: 2)
                    .padding(4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No songs yet")
                .font(.headline)
            Text("Drag MIDI files here, or use Import.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Import MIDI…") { showingImporter = true }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension.lowercased() == "mid"
                        || url.pathExtension.lowercased() == "midi" else { return }
                Task { @MainActor in model.importSongs(urls: [url]) }
            }
        }
    }
}

struct SongRow: View {
    let song: SongEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title).lineLimit(1)
            HStack(spacing: 4) {
                Text(song.subtitle)
                if !song.handSignal.isReliable {
                    // Be upfront when the hands were a guess.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Hands inferred from \(song.handSignal.rawValue) — may be wrong where the hands cross")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
