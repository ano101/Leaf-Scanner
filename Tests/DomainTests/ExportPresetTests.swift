import Testing
@testable import Leaf

@Suite("Пресеты требований учреждений")
struct ExportPresetTests {
    @Test("ключи пресетов уникальны")
    func presetKeysAreUnique() {
        let keys = ExportPreset.all.map(\.id)
        #expect(Set(keys).count == keys.count)
    }

    @Test("у каждого пресета кроме свободного задан предел веса")
    func everyPresetExceptCustomHasLimit() {
        for preset in ExportPreset.all where preset.id != ExportPreset.customKey {
            #expect(preset.limitBytes != nil, "у пресета \(preset.id) нет предела веса")
        }
    }

    @Test("свободный размер не навязывает предел")
    func customPresetImposesNoLimit() {
        let custom = ExportPreset.all.first { $0.id == ExportPreset.customKey }
        #expect(custom != nil)
        #expect(custom?.limitBytes == nil)
    }

    @Test("ключ пресета совпадает с ключом локализации")
    func presetKeyMatchesLocalizationKey() {
        for preset in ExportPreset.all {
            #expect(preset.titleKey == "export.preset.\(preset.id)")
        }
    }
}
