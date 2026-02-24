import SwiftUI
import PhotosUI

struct PersonEditForm: View {
    let person: Person?
    @ObservedObject var peopleManager: PeopleManager
    let colorScheme: ColorScheme
    let onSave: (Person) -> Void
    let onCancel: () -> Void
    
    // Form state
    @State private var name: String = ""
    @State private var nickname: String = ""
    @State private var relationship: RelationshipType = .friend
    @State private var customRelationship: String = ""
    @State private var birthday: Date = Date()
    @State private var hasBirthday: Bool = false
    @State private var favouriteFood: String = ""
    @State private var favouriteGift: String = ""
    @State private var favouriteColor: String = ""
    @State private var interests: String = ""
    @State private var notes: String = ""
    @State private var howWeMet: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var address: String = ""
    @State private var instagram: String = ""
    @State private var linkedIn: String = ""
    @State private var isFavourite: Bool = false
    
    // Image picker state
    @State private var selectedImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var showingImagePicker = false
    @State private var photoURL: String? = nil
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color.black.opacity(0.64)
    }

    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.52) : Color.black.opacity(0.5)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var cardBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var isEditing: Bool {
        person != nil
    }
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    init(person: Person?, peopleManager: PeopleManager, colorScheme: ColorScheme, onSave: @escaping (Person) -> Void, onCancel: @escaping () -> Void) {
        self.person = person
        self.peopleManager = peopleManager
        self.colorScheme = colorScheme
        self.onSave = onSave
        self.onCancel = onCancel
        
        // Initialize state from person if editing
        if let person = person {
            _name = State(initialValue: person.name)
            _nickname = State(initialValue: person.nickname ?? "")
            _relationship = State(initialValue: person.relationship)
            _customRelationship = State(initialValue: person.customRelationship ?? "")
            _hasBirthday = State(initialValue: person.birthday != nil)
            _birthday = State(initialValue: person.birthday ?? Date())
            _favouriteFood = State(initialValue: person.favouriteFood ?? "")
            _favouriteGift = State(initialValue: person.favouriteGift ?? "")
            _favouriteColor = State(initialValue: person.favouriteColor ?? "")
            _interests = State(initialValue: person.interests?.joined(separator: ", ") ?? "")
            _notes = State(initialValue: person.notes ?? "")
            _howWeMet = State(initialValue: person.howWeMet ?? "")
            _phone = State(initialValue: person.phone ?? "")
            _email = State(initialValue: person.email ?? "")
            _address = State(initialValue: person.address ?? "")
            _instagram = State(initialValue: person.instagram ?? "")
            _linkedIn = State(initialValue: person.linkedIn ?? "")
            _isFavourite = State(initialValue: person.isFavourite)
            _photoURL = State(initialValue: person.photoURL)
        }
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                topActionBar

                // Photo picker section
                photoPickerSection

                // Basic info section
                basicInfoSection

                // Personal attributes section
                personalAttributesSection

                // Contact info section
                contactInfoSection

                // Notes section
                notesSection

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .background(colorScheme == .dark ? Color.black : Color(uiColor: .systemGroupedBackground))
    }

    private var topActionBar: some View {
        HStack(spacing: 12) {
            topPillButton(title: "Cancel", action: onCancel)

            Spacer(minLength: 8)

            Text(isEditing ? "Edit Person" : "Add Person")
                .font(FontManager.geist(size: 22, weight: .bold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            topPillButton(title: "Save", action: savePerson, isDisabled: !isValid)
        }
    }

    private func topPillButton(title: String, action: @escaping () -> Void, isDisabled: Bool = false) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 15, weight: .semibold))
                .foregroundColor(isDisabled ? tertiaryTextColor : primaryTextColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(cardFillColor)
                )
                .overlay(
                    Capsule()
                        .stroke(cardBorderColor, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
    
    // MARK: - Photo Picker Section
    
    private var photoPickerSection: some View {
        VStack(spacing: 16) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                ZStack {
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let photoURL = photoURL, !photoURL.isEmpty {
                        CachedAsyncImage(url: photoURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(FontManager.geist(size: 40, weight: .light))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                                )
                        }
                    } else {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(FontManager.geist(size: 40, weight: .light))
                                    .foregroundColor(tertiaryTextColor)
                            )
                    }
                    
                    // Overlay with edit icon
                    Circle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.45) : Color.white.opacity(0.92))
                        .overlay(
                            Image(systemName: selectedImage != nil || photoURL != nil ? "pencil.circle.fill" : "camera.fill")
                                .font(FontManager.geist(size: 22, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        )
                        .frame(width: 42, height: 42)
                }
                .frame(width: 116, height: 116)
                .overlay(
                    Circle()
                        .stroke(cardBorderColor, lineWidth: 1.2)
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(selectedImage != nil || photoURL != nil ? "Tap to change photo" : "Tap to add photo")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(tertiaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(sectionCardBackground(cornerRadius: 20))
        .onChange(of: selectedPhotoItem) { newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            selectedImage = image
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Basic Info Section
    
    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Basic Info", icon: "person.fill")
            
            VStack(spacing: 12) {
                // Name (required)
                formTextField(
                    title: "Name",
                    placeholder: "Enter name",
                    text: $name,
                    icon: "person.fill",
                    isRequired: true
                )
                
                // Nickname
                formTextField(
                    title: "Nickname",
                    placeholder: "Optional nickname",
                    text: $nickname,
                    icon: "quote.bubble.fill"
                )
                
                // Relationship picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relationship")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RelationshipType.allCases, id: \.self) { type in
                                relationshipChip(type: type)
                            }
                        }
                    }
                }
                
                // Custom relationship (if "Other" is selected)
                if relationship == .other {
                    formTextField(
                        title: "Custom Relationship",
                        placeholder: "e.g., Cousin, Doctor",
                        text: $customRelationship,
                        icon: "tag.fill"
                    )
                }
                
                // Favourite toggle
                Toggle(isOn: $isFavourite) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        Text("Mark as Favourite")
                            .font(FontManager.geist(size: 14, weight: .medium))
                    }
                }
                .tint(colorScheme == .dark ? .white : .black)
                .padding(12)
                .background(fieldCardBackground(cornerRadius: 12))
            }
            .padding(12)
            .background(sectionCardBackground(cornerRadius: 16))
        }
    }
    
    private func relationshipChip(type: RelationshipType) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                relationship = type
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(FontManager.geist(size: 11, weight: .medium))
                Text(type.displayName)
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(relationship == type ?
                          (colorScheme == .dark ? Color.white : Color.black) :
                          (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
            )
            .foregroundColor(relationship == type ?
                             (colorScheme == .dark ? Color.black : Color.white) :
                             secondaryTextColor)
            .overlay(
                Capsule()
                    .stroke(relationship == type ? Color.clear : cardBorderColor, lineWidth: 0.8)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Personal Attributes Section
    
    private var personalAttributesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Personal Details", icon: "heart.fill")
            
            VStack(spacing: 12) {
                // Birthday toggle and picker
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $hasBirthday) {
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            Text("Birthday")
                                .font(FontManager.geist(size: 14, weight: .medium))
                        }
                    }
                    .tint(colorScheme == .dark ? .white : .black)
                    
                    if hasBirthday {
                        DatePicker(
                            "Select Birthday",
                            selection: $birthday,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    }
                }
                .padding(12)
                .background(fieldCardBackground(cornerRadius: 12))
                
                // Favourite food
                formTextField(
                    title: "Favourite Food",
                    placeholder: "e.g., Pizza, Sushi",
                    text: $favouriteFood,
                    icon: "fork.knife"
                )
                
                // Gift ideas
                formTextField(
                    title: "Gift Ideas",
                    placeholder: "e.g., Books, Tech gadgets",
                    text: $favouriteGift,
                    icon: "giftcard.fill"
                )
                
                // Favourite color
                formTextField(
                    title: "Favourite Color",
                    placeholder: "e.g., Blue, Green",
                    text: $favouriteColor,
                    icon: "paintpalette.fill"
                )
                
                // Interests
                formTextField(
                    title: "Interests",
                    placeholder: "e.g., Music, Sports, Art (comma separated)",
                    text: $interests,
                    icon: "heart.fill"
                )
            }
            .padding(12)
            .background(sectionCardBackground(cornerRadius: 16))
        }
    }
    
    // MARK: - Contact Info Section
    
    private var contactInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Contact Info", icon: "phone.fill")
            
            VStack(spacing: 12) {
                // Phone
                formTextField(
                    title: "Phone",
                    placeholder: "+1 (555) 123-4567",
                    text: $phone,
                    icon: "phone.fill",
                    keyboardType: .phonePad
                )
                
                // Email
                formTextField(
                    title: "Email",
                    placeholder: "email@example.com",
                    text: $email,
                    icon: "envelope.fill",
                    keyboardType: .emailAddress
                )
                
                // Address
                formTextField(
                    title: "Address",
                    placeholder: "123 Main St, City",
                    text: $address,
                    icon: "map.fill"
                )
                
                // Instagram
                formTextField(
                    title: "Instagram",
                    placeholder: "username (without @)",
                    text: $instagram,
                    icon: "camera.fill"
                )
                
                // LinkedIn
                formTextField(
                    title: "LinkedIn",
                    placeholder: "profile-name",
                    text: $linkedIn,
                    icon: "link"
                )
            }
            .padding(12)
            .background(sectionCardBackground(cornerRadius: 16))
        }
    }
    
    // MARK: - Notes Section
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Notes", icon: "note.text")
            
            VStack(spacing: 12) {
                // How we met
                formTextArea(
                    title: "How We Met",
                    placeholder: "Describe how you met this person...",
                    text: $howWeMet,
                    icon: "hand.wave.fill"
                )
                
                // General notes
                formTextArea(
                    title: "Notes",
                    placeholder: "Any other notes about this person...",
                    text: $notes,
                    icon: "note.text"
                )
            }
            .padding(12)
            .background(sectionCardBackground(cornerRadius: 16))
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                Image(systemName: icon)
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(width: 20, height: 20)

            Text(title)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.55)
        }
        .foregroundColor(secondaryTextColor)
    }

    private func sectionCardBackground(cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(cardBorderColor, lineWidth: 0.8)
            )
    }

    private func fieldCardBackground(cornerRadius: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.6)
            )
    }
    
    private func formTextField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String,
        isRequired: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(secondaryTextColor)
                
                if isRequired {
                    Text("*")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(primaryTextColor)
                }
            }
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
                    .frame(width: 20)
                
                TextField(placeholder, text: text)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .emailAddress ? .none : .words)
            }
            .padding(12)
            .background(fieldCardBackground(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isRequired && text.wrappedValue.isEmpty ?
                        (colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.24)) :
                        Color.clear,
                        lineWidth: 1
                    )
            )
        }
    }
    
    private func formTextArea(
        title: String,
        placeholder: String,
        text: Binding<String>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(secondaryTextColor)
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
                    .frame(width: 20)
                    .padding(.top, 2)
                
                TextEditor(text: text)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .overlay(
                        Group {
                            if text.wrappedValue.isEmpty {
                                Text(placeholder)
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .foregroundColor(tertiaryTextColor)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                            }
                        },
                        alignment: .topLeading
                    )
            }
            .padding(12)
            .background(fieldCardBackground(cornerRadius: 12))
        }
    }
    
    // MARK: - Save
    
    private func savePerson() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Parse interests from comma-separated string
        let interestsArray: [String]? = interests.isEmpty ? nil : interests.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        
        // Upload image if selected
        Task {
            var finalPhotoURL = photoURL
            
            if let selectedImage = selectedImage,
               let imageData = selectedImage.jpegData(compressionQuality: 0.8),
               let userId = SupabaseManager.shared.getCurrentUser()?.id {
                do {
                    let fileName = "person-\(person?.id.uuidString ?? UUID().uuidString).jpg"
                    finalPhotoURL = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)
                } catch {
                    print("❌ Error uploading person photo: \(error)")
                }
            }
            
            await MainActor.run {
                var newPerson = Person(
                    id: person?.id ?? UUID(),
                    name: trimmedName,
                    nickname: nickname.isEmpty ? nil : nickname,
                    relationship: relationship,
                    customRelationship: relationship == .other ? (customRelationship.isEmpty ? nil : customRelationship) : nil,
                    birthday: hasBirthday ? birthday : nil,
                    favouriteFood: favouriteFood.isEmpty ? nil : favouriteFood,
                    favouriteGift: favouriteGift.isEmpty ? nil : favouriteGift,
                    favouriteColor: favouriteColor.isEmpty ? nil : favouriteColor,
                    interests: interestsArray,
                    notes: notes.isEmpty ? nil : notes,
                    howWeMet: howWeMet.isEmpty ? nil : howWeMet,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    address: address.isEmpty ? nil : address,
                    instagram: instagram.isEmpty ? nil : instagram,
                    linkedIn: linkedIn.isEmpty ? nil : linkedIn,
                    photoURL: finalPhotoURL,
                    linkedPeople: person?.linkedPeople,
                    favouritePlaceIds: person?.favouritePlaceIds,
                    isFavourite: isFavourite
                )
                
                // Preserve dates if editing
                if let existingPerson = person {
                    newPerson.dateCreated = existingPerson.dateCreated
                }
                
                onSave(newPerson)
            }
        }
    }
}

#Preview {
    PersonEditForm(
        person: nil,
        peopleManager: PeopleManager.shared,
        colorScheme: .dark,
        onSave: { _ in },
        onCancel: { }
    )
}
