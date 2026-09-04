import SwiftUI

/// Состояние «Страницы»: порядок, выделение, разделение, удаление.
struct PageGridView: View {
    let model: DocumentModel
    let services: AppServices
    @Binding var isSelecting: Bool
    let onOpen: (PageID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 156), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                    cell(page: page, number: index + 1)
                }
            }
            .padding(16)
        }
    }

    private func cell(page: Page, number: Int) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                // Высота клетки задана, а страница вписывается в неё
                // по центру: и портретный, и повёрнутый лист занимают
                // одинаковое место, и сетка не прыгает при повороте.
                ProcessedPageView(page: page, look: page.look, cache: services.renders, maxSide: 400)
                    .frame(height: 150)

                if isSelecting {
                    Image(systemName: model.selection.contains(page.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .font(.title3)
                        .foregroundStyle(model.selection.contains(page.id) ? Theme.accent : .secondary)
                        .background(Circle().fill(.background).padding(2))
                        .padding(6)
                }

                if page.redactions.isEmpty == false {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption2)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Text(verbatim: "\(number)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                model.toggleSelection(page.id)
            } else {
                onOpen(page.id)
            }
        }
        .contextMenu {
            Button {
                Task { await model.rotateRight(page.id) }
            } label: {
                Label("document.rotate", systemImage: "rotate.right")
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
}
