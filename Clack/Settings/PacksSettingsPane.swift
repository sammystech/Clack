import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PacksSettingsPane: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedFolderID: String?
    @State private var hoveredRowID: String?
    @State private var isImporting = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var successToken = 0
    @State private var isDropTargeted = false

    private var model: AppModel { .shared }
    private var library: PackLibrary { model.library }

    var body: some View {
        Form {
            foldersSection
            packsSection
            if !library.failures.isEmpty {
                failuresSection
            }
        }
        .formStyle(.grouped)
        .frame(width: DS.Size.settingsWidth, height: 560)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DS.Radius.thumb, style: .continuous)
                    .strokeBorder(DS.Palette.accent, lineWidth: 2)
                    .padding(DS.Space.xs)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            importPacks(files)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onAppear { model.reloadPacks() }
    }

    // MARK: - Folders

    private var foldersSection: some View {
        Section("Folders") {
            ForEach(library.folders) { folder in
                folderRow(folder)
            }
            HStack(spacing: DS.Space.xs) {
                Button(action: addFolders) {
                    Image(systemName: "plus").frame(width: 14, height: 14)
                }
                .help("Add Folder…")
                .accessibilityLabel("Add Folder")
                Button(action: removeSelectedFolder) {
                    Image(systemName: "minus").frame(width: 14, height: 14)
                }
                .help("Remove Folder")
                .accessibilityLabel("Remove Folder")
                .disabled(selectedFolder?.isRemovable != true)
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var selectedFolder: PackFolder? {
        library.folders.first { $0.id == selectedFolderID }
    }

    private func folderRow(_ folder: PackFolder) -> some View {
        let isSelected = folder.id == selectedFolderID
        let path = (folder.url.path as NSString).abbreviatingWithTildeInPath
        return HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(folder.displayName)
                    .font(DS.Typo.body)
                Text(folder.exists ? path : "\(path) (missing)")
                    .font(DS.Typo.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DS.Space.s)
            revealButton(folder.url, rowID: folder.id)
                .disabled(!folder.exists)
        }
        .frame(minHeight: DS.Size.rowHeight - 12)
        .contentShape(Rectangle())
        .onTapGesture { selectedFolderID = isSelected ? nil : folder.id }
        .onHover { hoveredRowID = $0 ? folder.id : (hoveredRowID == folder.id ? nil : hoveredRowID) }
        .listRowBackground(isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : nil)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { selectedFolderID = folder.id }
    }

    // MARK: - Packs

    private var packsSection: some View {
        Section("Packs") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text(countText)
                    .font(DS.Typo.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: DS.Space.s) {
                    Button("Add Pack…", action: choosePacks)
                    Button("Reload Packs") { model.reloadPacks() }
                    Button("Random Pack") { model.randomPack() }
                        .disabled(!model.canRandomize)
                    Button("Open Folder") { model.openCustomPacksFolder() }
                }
                .disabled(isImporting)

                if isImporting {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                if let importError {
                    Label {
                        Text(importError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(DS.Typo.caption)
                    .foregroundStyle(DS.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                } else if let importSuccess {
                    Text(importSuccess)
                        .font(DS.Typo.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, DS.Space.xs)
            .animation(reduceMotion ? nil : DS.Motion.progress, value: isImporting)
        }
    }

    private var countText: String {
        let count = library.all.count
        var text = count == 1 ? "1 pack" : "\(count) packs"
        if !library.failures.isEmpty {
            text += ", \(library.failures.count) couldn't load"
        }
        return text
    }

    // MARK: - Failures

    private var failuresSection: some View {
        Section("Couldn't Load") {
            ForEach(library.failures) { failure in
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.warning)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(failure.folderName)
                            .font(DS.Typo.body)
                        Text(failure.reason)
                            .font(DS.Typo.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: DS.Space.s)
                    revealButton(failure.url, rowID: "failure:" + failure.id)
                }
                .frame(minHeight: DS.Size.rowHeight - 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    let id = "failure:" + failure.id
                    hoveredRowID = hovering ? id : (hoveredRowID == id ? nil : hoveredRowID)
                }
            }
        }
    }

    // MARK: - Shared pieces

    private func revealButton(_ url: URL, rowID: String) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 15))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Show in Finder")
        .accessibilityLabel("Show in Finder")
        .opacity(hoveredRowID == rowID ? 1.0 : 0.7)
        .animation(DS.Motion.hover, value: hoveredRowID == rowID)
    }

    // MARK: - Actions

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.preferences.customPackFolders += panel.urls.map(\.path)
    }

    private func removeSelectedFolder() {
        guard let folder = selectedFolder, folder.isRemovable else { return }
        let target = folder.url.standardizedFileURL.path
        model.preferences.customPackFolders.removeAll {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path == target
        }
        selectedFolderID = nil
    }

    private func choosePacks() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder, .zip]
        panel.prompt = "Add"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importPacks(panel.urls)
    }

    private func importPacks(_ urls: [URL]) {
        guard !isImporting else { return }
        isImporting = true
        importError = nil
        importSuccess = nil
        Task {
            let error = await model.importPacks(urls)
            isImporting = false
            if let error {
                importError = error
                return
            }
            importSuccess = urls.count == 1
                ? "Added \(urls[0].deletingPathExtension().lastPathComponent)."
                : "Added \(urls.count) packs."
            successToken += 1
            let token = successToken
            try? await Task.sleep(for: .seconds(4))
            if successToken == token { importSuccess = nil }
        }
    }
}
