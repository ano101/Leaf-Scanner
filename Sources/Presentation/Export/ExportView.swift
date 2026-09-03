import SwiftUI

public struct ExportView: View {
    @State private var model: ExportModel
    @State private var shareURL: URL?
    @Environment(\.dismiss) private var dismiss

    private let documentName: String

    public init(document: Document, services: AppServices) {
        _model = State(initialValue: ExportModel(document: document, fitter: services.makeFitter()))
        self.documentName = document.name
    }

    public var body: some View {
        Form {
            presetSection
            if model.isCustomLimit { customSizeSection }
            colorSection
            passwordSection
            resultSection
        }
        .navigationTitle("export.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("common.close") { dismiss() }
            }
        }
        .task { await model.prepare() }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
    }

    private var presetSection: some View {
        Section("export.preset") {
            Picker("export.preset", selection: Binding(
                get: { model.presetID },
                set: { newValue in
                    model.selectPreset(newValue)
                    Task { await model.prepare() }
                }
            )) {
                ForEach(model.presets) { preset in
                    Text(LocalizedStringKey(preset.titleKey)).tag(preset.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var customSizeSection: some View {
        Section("export.size") {
            VStack(alignment: .leading, spacing: 8) {
                Text("export.size.value \(ByteText.string(model.limitBytes))")
                    .font(.body.weight(.medium))

                Slider(
                    value: Binding(
                        get: { model.customLimitMegabytes },
                        set: { model.customLimitMegabytes = $0 }
                    ),
                    in: 0.2...25,
                    step: 0.1
                ) {
                    Text("export.size")
                } onEditingChanged: { editing in
                    guard editing == false else { return }
                    Task { await model.prepare() }
                }
                .tint(Theme.accent)
            }
        }
    }

    private var colorSection: some View {
        Section("export.color") {
            Picker("export.color", selection: Binding(
                get: { model.colorMode },
                set: { newValue in
                    model.colorMode = newValue
                    Task { await model.prepare() }
                }
            )) {
                ForEach(ColorMode.allCases, id: \.self) { mode in
                    Text(LocalizedStringKey(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var passwordSection: some View {
        Section {
            SecureField("export.password", text: Binding(
                get: { model.password },
                set: { model.password = $0 }
            ))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            Text("export.password")
        } footer: {
            Text("export.password.hint")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        Section("export.result") {
            switch model.outcome {
            case .idle, .working:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("export.working").foregroundStyle(.secondary)
                }

            case let .ready(bytes, heaviest):
                VStack(alignment: .leading, spacing: 6) {
                    Text("export.ready \(ByteText.string(bytes))")
                        .font(.headline)
                    if let heaviest {
                        Text("export.heaviest \(heaviest)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                actions(bytes: bytes)

            case let .suggestion(_, achievable):
                VStack(alignment: .leading, spacing: 10) {
                    Text("export.suggestion")
                        .font(.subheadline)
                    Button {
                        Task { await model.acceptSuggestion() }
                    } label: {
                        Text("export.suggestion.accept")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }

            case let .impossible(bestBytes, _):
                VStack(alignment: .leading, spacing: 6) {
                    Text("export.impossible \(ByteText.string(bestBytes))")
                        .font(.subheadline)
                    Text("export.impossible.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            case let .failed(messageKey):
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey(messageKey)).font(.subheadline)
                    Button("common.retry") {
                        Task { await model.prepare() }
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(bytes: Int) -> some View {
        if let data = model.data {
            Button {
                shareURL = try? ExportDelivery.writeTemporaryFile(data, name: documentName)
            } label: {
                Label("export.share", systemImage: "square.and.arrow.up")
            }

            Button {
                ExportDelivery.print(data, name: documentName)
            } label: {
                Label("export.print", systemImage: "printer")
            }
        }
    }
}


/// Системный лист «Поделиться». Отдельный тип нужен, потому что делиться
/// приходится файлом на диске: получатель должен получить документ, а не
/// снимок экрана.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
