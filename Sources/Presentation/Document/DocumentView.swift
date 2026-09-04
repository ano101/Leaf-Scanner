import SwiftUI

/// Экран документа в трёх состояниях.
///
/// Порядок «просмотр → правка → страницы» человек уже знает по «Фото»
/// и «Файлам». Раньше нажатие на документ вело сразу в сетку страниц —
/// служебный экран, тогда как чаще всего документ открывают, чтобы
/// посмотреть его или сразу отправить. Просмотр стоит ноль действий.
public struct DocumentView: View {
    enum Mode: Equatable {
        case viewing
        case editing
        case pages
    }

    @State private var model: DocumentModel
    @State private var mode: Mode = .viewing
    @State private var current: PageID?
    @State private var isExporting = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isSelecting = false

    private let services: AppServices

    public init(document: Document, services: AppServices) {
        self.services = services
        _model = State(initialValue: DocumentModel(document: document, documents: services.documents))
        _current = State(initialValue: PageOrdering.sorted(document.pages).first?.id)
    }

    public var body: some View {
        Group {
            switch mode {
            case .viewing, .editing:
                pager
            case .pages:
                PageGridView(model: model, services: services, isSelecting: $isSelecting) { pageID in
                    current = pageID
                    mode = .viewing
                }
            }
        }
        .navigationTitle(model.document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("document.rename", isPresented: $isRenaming) {
            TextField("document.name", text: $draftName)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") { Task { await model.rename(to: draftName) } }
        }
        .sheet(isPresented: $isExporting) {
            NavigationStack {
                ExportView(
                    document: model.document,
                    pageIDs: model.selection.isEmpty ? nil : model.selection,
                    services: services
                )
            }
        }
        .overlay(alignment: .bottom) { failureNotice }
    }

    // MARK: - Просмотр и правка

    private var pager: some View {
        TabView(selection: $current) {
            ForEach(model.pages) { page in
                ZoomablePage(page: page, look: page.look, cache: services.renders)
                    .padding(.horizontal, mode == .editing ? 12 : 0)
                    .tag(Optional(page.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.paper.opacity(0.35))
    }

    @ViewBuilder
    private var bottomBar: some View {
        switch mode {
        case .viewing:
            filmstrip
        case .editing:
            editingTools
        case .pages:
            if isSelecting {
                selectionActions
            } else {
                exportButton
            }
        }
    }

    /// Лента миниатюр: видно, сколько страниц, и можно перескочить,
    /// не листая всё подряд.
    private var filmstrip: some View {
        VStack(spacing: 8) {
            if model.pages.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                                Button {
                                    withAnimation(.snappy) { current = page.id }
                                } label: {
                                    PageThumbnail(pageID: page.id, loader: services.thumbnails)
                                        .frame(width: 38, height: 50)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Theme.pageCorner)
                                                .strokeBorder(
                                                    page.id == current ? Theme.accent : Color.clear,
                                                    lineWidth: 2
                                                )
                                        }
                                        .accessibilityLabel(Text(verbatim: "\(index + 1)"))
                                }
                                .buttonStyle(.plain)
                                .id(page.id)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 56)
                    .onChange(of: current) { _, id in
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }

            exportButton
        }
        .background(.bar)
    }

    private var editingTools: some View {
        VStack(spacing: 10) {
            if let page = currentPage {
                LookStrip(page: page, selected: page.look, cache: services.renders) { look in
                    Task { await model.setLook(look, for: page.id) }
                }
            }

            HStack(spacing: 8) {
                ToolButton(titleKey: "document.rotate.left", systemImage: "rotate.left") {
                    Task { await rotate(left: true) }
                }

                ToolButton(titleKey: "document.rotate.right", systemImage: "rotate.right") {
                    Task { await rotate(left: false) }
                }

                ToolButton(titleKey: "document.redact", systemImage: "eye.slash") {
                    if let page = currentPage { redactedPage = page.id }
                }

                ToolButton(
                    titleKey: "common.undo",
                    systemImage: "arrow.uturn.backward",
                    isEnabled: model.canUndo
                ) {
                    Task { await undoLastChange() }
                }
            }

            // Вместо кнопки «Сохранить», которая ничего бы не делала:
            // правки записываются сразу, и человеку нужно знать это, а не
            // нажимать лишнее. Вопрос снимается одной строкой навсегда.
            Text("document.saved.hint")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .sheet(item: $redactedPage) { pageID in
            NavigationStack {
                PageEditorView(pageID: pageID, model: model, services: services)
            }
        }
    }

    @State private var redactedPage: PageID?

    private var selectionActions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.rotateSelectionRight() }
            } label: {
                Label("document.rotate", systemImage: "rotate.right")
            }

            Button {
                isExporting = true
            } label: {
                Label("document.export.selected", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                Task { await model.deleteSelection() }
            } label: {
                Label("common.delete", systemImage: "trash")
            }
        }
        .buttonStyle(.secondaryAccent)
        .labelStyle(.iconOnly)
        .disabled(model.selection.isEmpty)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var exportButton: some View {
        Button {
            isExporting = true
        } label: {
            Label("document.export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.prominentAccent)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Панель сверху

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // Правка — состояние с началом и концом. Пока она идёт, переключатель
        // режимов убран: он предлагал бы уйти в сторону вместо того, чтобы
        // закончить начатое.
        if mode == .editing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.done") {
                    withAnimation(.snappy) { mode = .viewing }
                }
                .font(.body.weight(.semibold))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("document.mode", selection: $mode) {
                    Image(systemName: "eye").tag(Mode.viewing)
                    Image(systemName: "slider.horizontal.3").tag(Mode.editing)
                    Image(systemName: "square.grid.2x2").tag(Mode.pages)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 132)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        draftName = model.document.name
                        isRenaming = true
                    } label: {
                        Label("document.rename", systemImage: "pencil")
                    }

                    if mode == .pages {
                        Button {
                            isSelecting.toggle()
                            if isSelecting == false { model.selection = [] }
                        } label: {
                            Label(isSelecting ? "common.selection.done" : "common.select",
                                  systemImage: "checkmark.circle")
                        }
                    }

                    Menu {
                        ForEach(PageLook.allCases, id: \.self) { look in
                            Button(LocalizedStringKey(look.titleKey)) {
                                Task { await model.setLookForAllPages(look) }
                            }
                        }
                    } label: {
                        Label("document.look.all", systemImage: "wand.and.stars")
                    }
                } label: {
                    Label("common.more", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var failureNotice: some View {
        if case let .failed(messageKey) = model.state {
            Text(LocalizedStringKey(messageKey))
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 120)
        }
    }

    private var currentPage: Page? {
        model.pages.first { $0.id == current } ?? model.pages.first
    }

    /// После отката пересчитываются все страницы: откат мог вернуть не ту,
    /// что открыта сейчас, и прежняя картинка всплыла бы при листании.
    private func undoLastChange() async {
        await model.undo()
        for page in model.pages {
            await services.renders.forget(page.id)
        }
    }

    private func rotate(left: Bool) async {
        guard let page = currentPage else { return }
        await (left ? model.rotateLeft(page.id) : model.rotateRight(page.id))
        await services.renders.forget(page.id)
    }
}
