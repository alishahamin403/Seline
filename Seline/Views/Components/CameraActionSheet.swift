import SwiftUI

struct CameraActionSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedImage: UIImage?
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var showImagePicker = false
    @State private var isProcessing = false
    @State private var extractionResponse: CalendarPhotoExtractionResponse?
    @State private var selectedSource: ImageSource?

    enum ImageSource {
        case camera
        case library
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if isProcessing {
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
                                            .foregroundColor(.gray)
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
                                    .background(Color(red: 0.27, green: 0.27, blue: 0.27))
                                    .cornerRadius(12)
                            }

                            Button(action: { dismiss() }) {
                                Text("Cancel")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .frame(height: 50)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                } else {
                    // Success or partial - show review screen directly
                    ReviewExtractedEventsView(
                        extractionResponse: response,
                        onDismiss: {
                            resetAndRetry()
                        }
                    )
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
        .confirmationDialog("Import Schedule", isPresented: .constant(selectedSource == nil && !isProcessing && extractionResponse == nil)) {
            Button("Take Photo") {
                sourceType = .camera
                showImagePicker = true
                selectedSource = .camera
            }
            Button("Choose from Library") {
                sourceType = .photoLibrary
                showImagePicker = true
                selectedSource = .library
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Select a source to import your schedule")
        }
    }

    // MARK: - Private Methods

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
        selectedSource = nil
        showImagePicker = false
    }
}

#Preview {
    CameraActionSheet()
}
