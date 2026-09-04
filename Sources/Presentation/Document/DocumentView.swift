import SwiftUI

public struct DocumentView: View {
    @State private var model: DocumentModel
    @State private var editedPageID: PageID?
    @State private var isExporting = false
    @State private var isRenaming = false
    @State private var draftName = ""

    private let services: AppServices

    public init(document: Document, services: AppServices) {
        self.services = services
        _model = State(initialValue: DocumentModel(document: document, documents: services.documents))
    }

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 160), spacing: 12)]

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                    pageCell(page: page, number: index + 1)
                }
            }
            .padding(16)
        }
        .navigationTitle(model.document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { exportBar }
        .alert("document.rename", isPresented: $isRenaming) {
            TextField("document.name", text: $draftName)
            Button("common.cancel", role: .cancel) {}
            Button("common.save") {
                Task { await model.rename(to: draftName) }
            }
        }
        .sheet(item: $editedPageID) { pageID in
            NavigationStack {
                PageEditorView(pageID: pageID, model: model, services: services)
            }
        }
        .sheet(isPresented: $isExporting) {
            NavigationStack {
                ExportView(document: model.document, services: services)
            }
        }
        .overlay(alignment: .bottom) { failureNotice }
    }

    private func pageCell(page: Page, number: Int) -> some View {
        VStack(spacing: 6) {
            PageThumbnail(pageID: page.id, loader: services.thumbnails)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if page.redactions.isEmpty == false {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
                .rotationEffect(.degrees(Double(page.rotation.rawValue)))
                .animation(.snappy, value: page.rotation)

            Text(verbatim: "\(number)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onTapGesture { editedPageID = page.id }
        .contextMenu {
            Button {
                Task { await model.rotateRight(page.id) }
            } label: {
                Label("document.rotate", systemImage: "rotate.right")
            }

            Button {
                editedPageID = page.id
            } label: {
                Label("document.edit", systemImage: "slider.horizontal.3")
            }

            if number < model.pages.count {
                Button {
                    Task { _ = await model.split(after: number - 1, tailName: model.document.name) }
                } label: {
                    Label("document.split", systemImage: "scissors")
                }
            }

            Button(role: .destructive) {
                Task { await model.deletePage(page.id) }
            } label: {
                Label("common.delete", systemImage: "trash")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    draftName = model.document.name
                    isRenaming = true
                } label: {
                    Label("document.rename", systemImage: "pencil")
                }

                Button {
                    Task { await model.rotateAllRight() }
                } label: {
                    Label("document.rotateAll", systemImage: "rotate.right")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var exportBar: some View {
        Button {
            isExporting = true
        } label: {
            Label("document.export", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(.prominentAccent)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var failureNotice: some View {
        if case let .failed(messageKey) = model.state {
            Text(LocalizedStringKey(messageKey))
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 76)
                .transition(.opacity)
        }
    }
}
