import SwiftUI

/// Выбор вида по примерам, а не по названию.
///
/// «Цветной скан» и «Серый скан» ничего не объясняют человеку, который
/// не знает, что приложение делает с изображением. Четыре миниатюры его
/// собственной страницы объясняют это без единого слова.
struct LookStrip: View {
    let page: Page
    let selected: PageLook
    let cache: PageRenderCache
    let onSelect: (PageLook) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(PageLook.allCases, id: \.self) { look in
                    Button {
                        onSelect(look)
                    } label: {
                        VStack(spacing: 6) {
                            ProcessedPageView(page: page, look: look, cache: cache, maxSide: 220)
                                .frame(width: 62, height: 82)
                                .contentShape(Rectangle())
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.pageCorner)
                                        .strokeBorder(
                                            look == selected ? Theme.accent : Color.clear,
                                            lineWidth: 2.5
                                        )
                                }

                            Text(LocalizedStringKey(look.titleKey))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(look == selected ? Theme.accent : .secondary)
                        }
                        .frame(width: 78)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
    }
}
