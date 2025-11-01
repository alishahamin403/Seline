import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedImages: [UIImage]
    @Environment(\.presentationMode) var presentationMode
    var allowMultiple: Bool = false

    init(selectedImage: Binding<UIImage?>) {
        self._selectedImage = selectedImage
        self._selectedImages = .constant([])
        self.allowMultiple = false
    }

    init(selectedImages: Binding<[UIImage]>) {
        self._selectedImage = .constant(nil)
        self._selectedImages = selectedImages
        self.allowMultiple = true
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = allowMultiple ? 10 : 1

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
            super.init()
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.presentationMode.wrappedValue.dismiss()

            if parent.allowMultiple {
                // Handle multiple images
                var loadedImages: [UIImage] = []
                let group = DispatchGroup()

                for result in results {
                    group.enter()
                    if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                        result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                            if let uiImage = image as? UIImage {
                                loadedImages.append(uiImage)
                            }
                            group.leave()
                        }
                    } else {
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    self.parent.selectedImages = loadedImages
                }
            } else {
                // Handle single image (backward compatibility)
                guard let provider = results.first?.itemProvider else { return }

                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { image, _ in
                        DispatchQueue.main.async {
                            self.parent.selectedImage = image as? UIImage
                        }
                    }
                }
            }
        }
    }
}
