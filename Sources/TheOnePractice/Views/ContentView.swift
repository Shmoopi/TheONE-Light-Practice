import SwiftUI
import UniformTypeIdentifiers

/// Where the Connect button sits. The Mac puts it beside the sidebar toggle; on
/// iPhone that slot belongs to the back button, so it goes on the right instead.
#if os(macOS)
private let connectionPlacement: ToolbarItemPlacement = .navigation
#else
private let connectionPlacement: ToolbarItemPlacement = .topBarTrailing
#endif

struct ContentView: View {
    @State private var model = PracticeModel()
    @State private var showingImporter = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            LibraryView(model: model, showingImporter: $showingImporter)
                .navigationSplitViewColumnWidth(min: 180, ideal: 250)
        } detail: {
            PracticeView(model: model)
                // The toolbar belongs to the detail column: on iPhone and iPad
                // that's the bar these buttons actually appear in, and on the Mac
                // it still goes to the window's own toolbar.
                .toolbar {
                    ToolbarItem(placement: connectionPlacement) {
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
                #if os(iOS)
                // The screen has its own title already; a second one just eats
                // the height the keyboard needs.
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        // Small enough to sit beside something else on screen. Everything inside
        // wraps or scrolls rather than piling up.
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 440)
        #endif
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
        // Opening a MIDI file from Finder, Files, or Mail adds it to the library.
        .onOpenURL { model.importSongs(urls: [$0]) }
        .onAppear {
            // Connect on its own — there's only one keyboard to connect to.
            model.piano.refreshDestinations()
            model.connect()
        }
        // Turn the lights off on the way out.
        .onDisappear { model.stop() }
        #if os(iOS)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // Leaving the app should never leave the keyboard lit.
            case .background: model.stop()
            // Songs can be dropped into the app's folder in Files while it's away.
            case .active: model.rescanLibrary()
            default: break
            }
        }
        #endif
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
                        #if os(iOS)
                        // Long-pressing for a menu isn't the first thing anyone
                        // tries on a touchscreen.
                        .swipeActions {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                model.remove(song)
                            }
                        }
                        #endif
                }
                if model.songs.isEmpty {
                    emptyState
                }
            }
        }
        .listStyle(.sidebar)
        #if os(iOS)
        // Names the back button on iPhone, where the sidebar is a separate screen.
        .navigationTitle("Songs")
        #endif
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
            Text(Self.emptyHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Import MIDI…") { showingImporter = true }
            #if os(macOS)
                .buttonStyle(.link)
            #else
                .buttonStyle(.borderless)
            #endif
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    #if os(macOS)
    private static let emptyHint = "Drag MIDI files here, or use Import."
    #else
    private static let emptyHint =
        "Use Import, or put MIDI files in this app's folder in the Files app."
    #endif

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
