import PhotosUI
import SwiftUI

public struct ArchiveView: View {
    @State private var model: ArchiveModel
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var openedDocument: Document?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isChoosingFile = false
    @State private var isPickingPhotos = false
    @State private var isSelecting = false
    @State private var isMerging = false
    @State private var isShowingSettings = false
    @State private var mergeName = ""
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
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionActions
                } else if model.isEmpty == false || model.isSearching {
                    scanButton
                }
            }
            .photosPicker(
                isPresented: $isPickingPhotos,
                selection: $photoSelection,
                matching: .images,
                photoLibrary: .shared()
            )
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
            // Показ камеры висит на корне экрана, а не на нижней панели.
            // Панель скрыта, пока архив пуст, — и раньше первое в жизни
            // нажатие «Сканировать» не открывало ничего: экран, которому
            // полагалось появиться, в этот момент не существовал.
            .fullScreenCover(isPresented: Binding(
                get: { services.scanner.isPresenting },
                set: { if $0 == false { services.scanner.fail(with: ScanError.cancelled) } }
            )) {
                DocumentCamera(source: services.scanner).ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingSettings) {
                NavigationStack {
                    SettingsView(settings: services.settings, lock: services.lock, expiry: services.expiry)
                }
            }
            .navigationDestination(item: $openedDocument) { document in
                DocumentView(document: document, services: services)
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    newFolderName = ""
                    isCreatingFolder = true
                } label: {
                    Label("archive.folder.new", systemImage: "folder.badge.plus")
                }

                Button {
                    isSelecting.toggle()
                    if isSelecting == false { model.selection = [] }
                } label: {
                    Label(isSelecting ? "common.selection.done" : "common.select",
                          systemImage: "checkmark.circle")
                }

                Divider()

                Button {
                    isShowingSettings = true
                } label: {
                    Label("settings.title", systemImage: "gearshape")
                }

                Divider()

                Button {
                    isPickingPhotos = true
                } label: {
                    Label("archive.import.photos", systemImage: "photo.on.rectangle")
                }

                Button {
                    isChoosingFile = true
                } label: {
                    Label("archive.import.files", systemImage: "folder")
                }
            } label: {
                Label("common.more", systemImage: "ellipsis.circle")
            }
        }
    }

    /// Диалог создания папки висит на содержимом, а не на корне экрана.
    /// Несколько диалогов на одном представлении перекрывают друг друга —
    /// работает последний, а остальные молча не открываются.
    @ViewBuilder
    private var content: some View {
        stateContent
            .alert("archive.folder.new", isPresented: $isCreatingFolder) {
                TextField("archive.folder.name", text: $newFolderName)
                Button("common.cancel", role: .cancel) {}
                Button("common.create") {
                    Task { await model.createFolder(named: newFolderName) }
                }
            }
    }

    @ViewBuilder
    private var stateContent: some View {
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
                                PlainTitle(folder.name).font(.headline)
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
                            if isSelecting {
                                model.toggleSelection(document.id)
                            } else {
                                openedDocument = document
                            }
                        } label: {
                            DocumentRow(
                                document: document,
                                loader: services.thumbnails,
                                selection: isSelecting
                                    ? (model.selection.contains(document.id) ? .chosen : .available)
                                    : .off
                            )
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
                    PlainTitle(hit.documentName).font(.headline)
                    Text(hit.snippet).documentSubtitleStyle()
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
    }

    private var scanButton: some View {
        HStack(spacing: 10) {
            Button {
                Task { await scan(duplex: false) }
            } label: {
                Label("archive.scan", systemImage: "doc.viewfinder")
            }
            .buttonStyle(.prominentAccent)

            Button {
                Task { await scan(duplex: true) }
            } label: {
                Label("archive.scan.duplex", systemImage: "doc.on.doc")
            }
            .buttonStyle(.secondaryAccent)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// Действия над выделенными документами. Объединение было написано
    /// и покрыто тестами с самого начала, но нажать его было негде —
    /// для человека функции не существовало.
    private var selectionActions: some View {
        HStack(spacing: 10) {
            Button {
                mergeName = model.defaultMergeName()
                isMerging = true
            } label: {
                Label("archive.merge", systemImage: "square.stack")
            }
            .buttonStyle(.prominentAccent)

            Button(role: .destructive) {
                Task { await model.deleteSelection() }
            } label: {
                Label("common.delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.secondaryAccent)
        }
        .disabled(model.selection.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.bar)
        .alert("archive.merge", isPresented: $isMerging) {
            TextField("archive.merge.name", text: $mergeName)
            Button("common.cancel", role: .cancel) {}
            Button("archive.merge") {
                Task {
                    await model.mergeSelection(into: mergeName)
                    isSelecting = false
                }
            }
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

            // Разбор идёт в фоне, но его итог виден сразу, как только готов:
            // имя, уточнённое по заголовку, не должно ждать перезапуска
            // приложения — человек решит, что уточнение не работает.
            Task(priority: .utility) { [services] in
                try? await services.recognition.process(documentID: document.id)
                await scheduleExpiry(for: document.id)
                await model.load()
            }
        } catch {
            importFailureKey = "archive.import.failed"
        }
    }

    /// Напоминания ставятся только если человек их включил: приложение,
    /// которое начинает слать уведомления само, отключают целиком.
    private func scheduleExpiry(for id: DocumentID) async {
        guard services.settings.expiryRemindersEnabled else { return }
        guard let document = try? await services.documents.document(id) else { return }
        await services.expiry.schedule(for: document)
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

            // Разбор текста идёт после того, как документ уже виден,
            // а список обновляется, когда разбор закончен.
            Task(priority: .utility) { [services] in
                try? await services.recognition.process(documentID: document.id)
                await scheduleExpiry(for: document.id)
                await model.load()
            }
        } catch {
            // Отмена съёмки — обычное действие человека, а не сбой.
            await model.load()
        }
    }
}

struct DocumentRow: View {
    enum Selection {
        case off
        case available
        case chosen
    }

    let document: Document
    let loader: ThumbnailLoader
    var selection: Selection = .off

    var body: some View {
        HStack(spacing: 12) {
            if selection != .off {
                Image(systemName: selection == .chosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selection == .chosen ? Theme.accent : .secondary)
            }

            Group {
                if let first = PageOrdering.sorted(document.pages).first {
                    PageThumbnail(pageID: first.id, loader: loader)
                } else {
                    RoundedRectangle(cornerRadius: Theme.pageCorner).fill(Theme.paper)
                }
            }
            .frame(width: 44, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                PlainTitle(document.name).font(.headline)

                if let expiry = document.expiresAt, let notice = ExpiryNotice(expiry: expiry) {
                    // Срок показывается вместо числа страниц, а не рядом:
                    // истекающий документ — единственное, что человеку важно
                    // знать об этой строке прямо сейчас.
                    Label {
                        Text(notice.textKey)
                    } icon: {
                        Image(systemName: notice.iconName)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(notice.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text("archive.pages \(document.pageCount)").documentSubtitleStyle()
                }
            }

            Spacer(minLength: 0)

            if selection == .off {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}


/// Как показать срок в списке. Показывается только то, что требует
/// действия: срок через год человеку в списке не нужен, он лишь занимает
/// строку и приучает не читать её.
struct ExpiryNotice {
    let textKey: LocalizedStringKey
    let iconName: String
    let tint: Color

    init?(expiry: Date, now: Date = Date()) {
        if ExpiryReminder.isExpired(expiry, now: now) {
            textKey = "expiry.expired"
            iconName = "exclamationmark.triangle.fill"
            tint = .red
            return
        }

        guard ExpiryReminder.isExpiringSoon(expiry, now: now) else { return nil }

        let days = max(Calendar.current.dateComponents([.day], from: now, to: expiry).day ?? 0, 0)
        textKey = "expiry.soon \(days)"
        iconName = "clock.badge.exclamationmark"
        tint = .orange
    }
}
