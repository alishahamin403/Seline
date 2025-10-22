import SwiftUI
import PhotosUI

struct PhotoCalendarImportView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var isProcessing = false
    @State private var extractionResponse: CalendarPhotoExtractionResponse?
    @State private var showReviewSheet = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    var body: some View {
        ZStack {
            // Background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if selectedImage == nil && !isProcessing && extractionResponse == nil {
                // Camera/Gallery Selection Screen
                VStack(spacing: 24) {
                    Spacer()

                    // Icon and title
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        VStack(spacing: 8) {
                            Text("Import Schedule from Photo")
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text("Take a picture of your calendar, printed schedule, or email calendar to automatically add events")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        // Camera button
                        Button(action: { openCamera() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                Text("Take Photo")
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }

                        // Gallery button
                        Button(action: { openGallery() }) {
                            HStack(spacing: 12) {
                                Image(systemName: "photo.fill")
                                Text("Choose from Library")
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(Color.gray)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        Button(action: { dismiss() }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .padding(24)
            } else if isProcessing {
                // Processing screen
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)

                    VStack(spacing: 8) {
                        Text("Analyzing Schedule...")
                            .font(.headline)
                        Text("Extracting times, titles, and attendees")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            } else if let response = extractionResponse {
                // Result handling
                Group {
                    if response.status == .failed {
                        // Failure screen
                        VStack(spacing: 20) {
                            Spacer()

                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.orange)

                                VStack(spacing: 8) {
                                    Text("Couldn't Read Schedule")
                                        .font(.headline)

                                    VStack(spacing: 12) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                            Text("Date/time information unclear")
                                                .font(.subheadline)
                                        }
                                        HStack(spacing: 12) {
                                            Image(systemName: "xmark.circle")
                                                .foregroundColor(.red)
                                            Text("Event titles not readable")
                                                .font(.subheadline)
                                        }
                                    }

                                    Text(response.errorMessage ?? "Please retake the photo with better lighting and clarity")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            .multilineTextAlignment(.center)

                            Spacer()

                            VStack(spacing: 12) {
                                // Tips for better photos
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Tips for a better photo:")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.gray)

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "lightbulb.fill")
                                                .foregroundColor(.yellow)
                                                .font(.caption)
                                            Text("Make sure it's well-lit")
                                                .font(.caption)
                                        }
                                        HStack(spacing: 8) {
                                            Image(systemName: "frame")
                                                .foregroundColor(.blue)
                                                .font(.caption)
                                            Text("Keep schedule centered")
                                                .font(.caption)
                                        }
                                        HStack(spacing: 8) {
                                            Image(systemName: "reflect.2")
                                                .foregroundColor(.cyan)
                                                .font(.caption)
                                            Text("Avoid glare and shadows")
                                                .font(.caption)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)

                                Button(action: {
                                    resetAndRetry()
                                }) {
                                    Text("Take Another Photo")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(height: 50)
                                        .frame(maxWidth: .infinity)
                                        .background(Color.blue)
                                        .cornerRadius(12)
                                }

                                Button(action: { dismiss() }) {
                                    Text("Cancel")
                                        .font(.headline)
                                        .foregroundColor(.blue)
                                        .frame(height: 50)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    } else {
                        // Success or partial - show review sheet
                        EmptyView()
                            .onAppear { showReviewSheet = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            CameraAndLibraryPicker(image: $selectedImage, sourceType: sourceType)
                .onDisappear {
                    if selectedImage != nil {
                        processImage()
                    }
                }
        }
        .sheet(isPresented: $showReviewSheet) {
            if let response = extractionResponse {
                ReviewExtractedEventsView(
                    extractionResponse: response,
                    onDismiss: { dismiss() }
                )
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") { resetAndRetry() }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Private Methods

    private func openCamera() {
        sourceType = .camera
        showImagePicker = true
    }

    private func openGallery() {
        sourceType = .photoLibrary
        showImagePicker = true
    }

    private func processImage() {
        guard let image = selectedImage else { return }

        isProcessing = true
        Task {
            do {
                let response = try await CalendarPhotoExtractionService.shared.extractEventsFromPhoto(image)
                await MainActor.run {
                    extractionResponse = response
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    extractionResponse = CalendarPhotoExtractionResponse(
                        status: .failed,
                        errorMessage: error.localizedDescription
                    )
                    isProcessing = false
                }
            }
        }
    }

    private func resetAndRetry() {
        selectedImage = nil
        extractionResponse = nil
        errorMessage = nil
        showReviewSheet = false
    }
}

// MARK: - Camera and Library Picker

struct CameraAndLibraryPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraAndLibraryPicker

        init(_ parent: CameraAndLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

#Preview {
    PhotoCalendarImportView()
}
