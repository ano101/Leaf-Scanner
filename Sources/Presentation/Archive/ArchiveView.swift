import PhotosUI
import SwiftUI

public struct ArchiveView: View {
    @State private var model: ArchiveModel
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var openedDocument: Document?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isChoosingFile = false
    @State private var importFailureKey: String?

    private let services: AppServices

    public init(services: AppServices, folderID: FolderID? = nil, title: String? = nil) {
        self.services = services
        let model = ArchiveModel(
            documents: services.documents,
            folders: services.folders,
            search: services.search
        )
        model.folderID = folderID
        _model = State(initialValue: model)
        self.folderTitle = title
    }

    private let folderTitle: String?

    public var body: some View {
        content
            .navigationTitle(folderTitle ?? String(localized: "archive.title"))
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("archive.search.prompt")
            )
            .onChange(of: model.query) { _, _ in
                Task { await model.runSearch() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            newFolderName = ""
                            isCreatingFolder = true
                        } label: {
                            Label("archive.folder.new", systemImage: "folder.badge.plus")
                        }

                        Divider()

                        Button {
                            isChoosingFile = true
                        } label: {
                            Label("archive.import.files", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(
                        selection: $photoSelection,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("archive.import.photos", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // На пустом архиве действие уже предложено в центре экрана.
                // Две одинаковые кнопки на одном экране заставляют выбирать
                // между ними, хотя выбора нет.
                if model.isEmpty == false || model.isSearching {
                    scanButton
                }
            }
            .alert("archive.folder.new", isPresented: $isCreatingFolder) {
                TextField("archive.folder.name", text: $newFolderName)
                Button("common.cancel", role: .cancel) {}
                Button("common.create") {
                    Task { await model.createFolder(named: newFolderName) }
                }
            }
            .navigationDestination(item: $openedDocument) { document in
                DocumentView(document: document, services: services)
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.pdf, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                Task { await importFile(at: url) }
            }
            .onChange(of: photoSelection) { _, items in
                guard items.isEmpty == false else { return }
                Task { await importPhotos(items) }
            }
            .alert(
                "archive.import.failed",
                isPresented: Binding(
                    get: { importFailureKey != nil },
                    set: { if $0 == false { importFailureKey = nil } }
                )
            ) {
                Button("common.close", role: .cancel) {}
            }
            .task { await model.load() }
            .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(messageKey):
            FailureView(messageKey: LocalizedStringKey(messageKey)) {
                Task { await model.load() }
            }

        case .ready:
            if model.isSearching {
                searchResults
            } else if model.isEmpty {
                EmptyStateView(
                    iconName: "doc.viewfinder",
                    titleKey: "archive.empty.title",
                    messageKey: "archive.empty.message",
                    actionKey: "archive.scan"
                ) {
                    Task { await scan(duplex: false) }
                }
            } else {
                documentList
            }
        }
    }

    private var documentList: some View {
        List {
            if model.folders.isEmpty == false {
                Section("archive.group.folders") {
                    ForEach(model.folders) { folder in
                        NavigationLink {
                            ArchiveView(services: services, folderID: folder.id, title: folder.name)
                        } label: {
                            Label {
                                Text(folder.name).documentTitleStyle()
                            } icon: {
                                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            ForEach(model.groups) { group in
                Section(LocalizedStringKey(group.titleKey)) {
                    ForEach(group.documents) { document in
                        Button {
                            openedDocument = document
                        } label: {
                            DocumentRow(document: document, loader: services.thumbnails)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.delete(document.id) }
                            } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var searchResults: some View {
        if model.hits.isEmpty {
            // «Ничего не найдено» — тупик. Вместо него предложение снять
            // недостающий документ прямо сейчас.
            EmptyStateView(
                iconName: "text.magnifyingglass",
                titleKey: "archive.search.empty.title",
                messageKey: "archive.search.empty.message",
                actionKey: "archive.scan"
            ) {
                Task { await scan(duplex: false) }
            }
        } else {
            List(model.hits) { hit in
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.documentName).documentTitleStyle()
                    Text(hit.snippet).documentSubtitleStyle()
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
    }

    private var scanButton: some View {
        HStack(spacing: 12) {
            Button {
                Task { await scan(duplex: false) }
            } label: {
                Label("archive.scan", systemImage: "doc.viewfinder")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                Task { await scan(duplex: true) }
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.body.weight(.semibold))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityLabel(Text("archive.scan.duplex"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.bar)
        .fullScreenCover(isPresented: Binding(
            get: { services.scanner.isPresenting },
            set: { if $0 == false { services.scanner.fail(with: ScanError.cancelled) } }
        )) {
            DocumentCamera(source: services.scanner).ignoresSafeArea()
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var data: [Data] = []
        for item in items {
            if let loaded = try? await item.loadTransferable(type: Data.self) {
                data.append(loaded)
            }
        }
        photoSelection = []

        await store(pages: {
            try await DocumentImporter(importer: services.importer).pages(fromImageData: data)
        })
    }

    private func importFile(at url: URL) async {
        await store(pages: {
            let importer = DocumentImporter(importer: services.importer)
            if url.pathExtension.lowercased() == "pdf" {
                return try await importer.pages(fromPDF: url)
            }

            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            return try await importer.pages(fromImageData: [try Data(contentsOf: url)])
        })
    }

    /// Общий путь для съёмки и импорта: документ появляется в архиве сразу,
    /// разбор текста идёт следом.
    private func store(pages make: () async throws -> [Page]) async {
        do {
            let pages = try await make()
            guard pages.isEmpty == false else { return }

            let document = Document(
                name: ScanImporter.suggestedName(from: nil, date: Date()),
                folderID: model.folderID,
                pages: pages
            )
            try await services.documents.save(document)
            await model.load()

            Task.detached(priority: .utility) { [services] in
                try? await services.recognition.process(documentID: document.id)
            }
        } catch {
            importFailureKey = "archive.import.failed"
        }
    }

    private func scan(duplex: Bool) async {
        do {
            let fronts = try await services.scanner.scan()
            var pages = try await services.importer.makePages(from: fronts)

            if duplex {
                let backs = try await services.scanner.scan()
                let backPages = try await services.importer.makePages(from: backs)
                pages = DuplexInterleaver.interleave(fronts: pages, backs: backPages)
            }

            guard pages.isEmpty == false else { return }

            let document = Document(
                name: ScanImporter.suggestedName(from: nil, date: Date()),
                folderID: model.folderID,
                pages: pages
            )
            try await services.documents.save(document)
            await model.load()

            // Разбор текста идёт после того, как документ уже виден.
            Task.detached(priority: .utility) { [services] in
                try? await services.recognition.process(documentID: document.id)
            }
        } catch {
            // Отмена съёмки — обычное действие человека, а не сбой.
            await model.load()
        }
    }
}

struct DocumentRow: View {
    let document: Document
    let loader: ThumbnailLoader

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let first = PageOrdering.sorted(document.pages).first {
                    PageThumbnail(pageID: first.id, loader: loader)
                } else {
                    RoundedRectangle(cornerRadius: Theme.pageCorner).fill(Theme.paper)
                }
            }
            .frame(width: 44, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.name).documentTitleStyle()
                Text("archive.pages \(document.pageCount)").documentSubtitleStyle()
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
