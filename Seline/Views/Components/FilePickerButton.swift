import SwiftUI
import UniformTypeIdentifiers

struct FilePickerButton: View {
    @State private var isPresentingFilePicker = false
    var onFileSelected: (URL) -> Void

    var body: some View {
        Button(action: { isPresentingFilePicker = true }) {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .semibold))
        }
        .fileImporter(
            isPresented: $isPresentingFilePicker,
            allowedContentTypes: [
                .pdf,
                .image,
                .plainText,
                .commaSeparatedText,
                UTType(filenameExtension: "csv") ?? .plainText,
                UTType(filenameExtension: "xlsx") ?? .spreadsheet
            ],
            onCompletion: { result in
                switch result {
                case .success(let url):
                    onFileSelected(url)
                case .failure(let error):
                    print("❌ File picker error: \(error.localizedDescription)")
                }
            }
        )
    }
}

#Preview {
    FilePickerButton { url in
        print("Selected: \(url.lastPathComponent)")
    }
}
