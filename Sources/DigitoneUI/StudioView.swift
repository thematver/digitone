import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let sysEx = UTType(exportedAs: "studio.digitone.sysex", conformingTo: .data)
}

struct StudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.sysEx, .data, .json, .midi, .audio] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
