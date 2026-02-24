import SwiftUI

struct CameraActionSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedImage: UIImage?
    @State private var sourceType: UIImagePickerController.SourceType = .camera
    @State private var showImagePicker = false
    @State private var showActionSheet = true
    @State private var isProcessing = false
    @State private var extractionResponse: CalendarPhotoExtractionResponse?

    var body: some View {
        if isProcessing {
            // Processing screen
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

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
            }
        } else if let response = extractionResponse {
            // Result handling
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                if response.status == .failed {
                    // Failure screen
                    VStack(spacing: 20) {
                        Spacer()

                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(FontManager.geist(size: 50, weight: .regular))
                                .foregroundColor(.primary)

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
        } else {
            // Show loading screen while waiting for user to select image
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)

                    VStack(spacing: 8) {
                        Text("Ready to import...")
                            .font(.headline)
                        Text("Select an image from camera or gallery")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                    CameraAndLibraryPicker(image: $selectedImage, sourceType: sourceType)
                        .onDisappear {
                            if selectedImage != nil {
                                processImage()
                            } else {
                                // User cancelled - show action sheet again
                                showActionSheet = true
                            }
                        }
                }
            .presentationBg()
                .confirmationDialog("Import Schedule", isPresented: $showActionSheet) {
                    Button("Take Photo") {
                        sourceType = .camera
                        showActionSheet = false
                        showImagePicker = true
                    }
                    Button("Choose from Library") {
                        sourceType = .photoLibrary
                        showActionSheet = false
                        showImagePicker = true
                    }
                    Button("Cancel", role: .cancel) {
                        showActionSheet = false
                        dismiss()
                    }
                } message: {
                    Text("Select a source to import your schedule")
                }
        }
    }

    // MARK: - Private Methods

    private func processImage() {
        guard let image = selectedImage else { return }

        isProcessing = true
        Task {
            do {
                var response = try await CalendarPhotoExtractionService.shared.extractEventsFromPhoto(image)

                // Check if events already exist in the calendar
                let taskManager = TaskManager.shared
                print("📸 Checking for duplicate events...")
                for i in 0..<response.events.count {
                    let event = response.events[i]
                    let exists = taskManager.doesEventExist(
                        title: event.title,
                        date: event.startTime,
                        time: event.startTime,
                        endTime: event.endTime
                    )

                    print("📸 Event: '\(event.title)' - Exists: \(exists) - Date: \(event.startTime) - Time: \(event.startTime)")

                    response.events[i].alreadyExists = exists
                    // Auto-deselect events that already exist to prevent duplicates
                    if exists {
                        response.events[i].isSelected = false
                        print("📸 Auto-deselecting duplicate event: \(event.title)")
                    }
                }

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
        showActionSheet = true
        showImagePicker = false
    }
}

#Preview {
    CameraActionSheet()
}
