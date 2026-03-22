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
        Color.appTextPrimary(colorScheme)
    }

    private var secondaryTextColor: Color {
        Color.appTextSecondary(colorScheme)
    }

    private var tertiaryTextColor: Color {
        Color.appTextSecondary(colorScheme).opacity(0.72)
    }

    private var cardFillColor: Color {
        Color.appSurface(colorScheme)
    }

    private var cardBorderColor: Color {
        Color.appBorder(colorScheme)
    }

    private var isEditing: Bool {
        person != nil
    }

    private var heroEyebrowText: String {
        isEditing ? "EDIT PERSON" : "NEW PERSON"
    }

    private var heroTitleText: String {
        isEditing ? "Refine this person card" : "Create a cleaner people card"
    }

    private var heroSupportingText: String {
        "Keep it lightweight: start with a photo, name, relationship, and only the details you actually revisit."
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
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .topLeading)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topActionBar
                    photoPickerSection
                    basicInfoSection
                    personalAttributesSection
                    contactInfoSection
                    notesSection
                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .selinePrimaryPageScroll()
        }
    }

    private var topActionBar: some View {
        HStack(spacing: 12) {
            topPillButton(title: "Cancel", systemImage: "xmark", action: onCancel)

            Spacer(minLength: 8)

            Text(isEditing ? "Edit Person" : "Add Person")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            topPillButton(title: "Save", systemImage: "checkmark", action: savePerson, isDisabled: !isValid, isPrimary: true)
        }
    }

    private func topPillButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void,
        isDisabled: Bool = false,
        isPrimary: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(FontManager.geist(size: 14, weight: .semibold))
            }
            .foregroundColor(
                isPrimary
                    ? .black.opacity(isDisabled ? 0.4 : 1)
                    : (isDisabled ? tertiaryTextColor : primaryTextColor)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(
                        isPrimary
                            ? Color.homeGlassAccent.opacity(isDisabled ? 0.45 : 1)
                            : Color.appChip(colorScheme)
                    )
            )
            .overlay(
                Capsule()
                    .stroke(isPrimary ? Color.clear : cardBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
    
    // MARK: - Photo Picker Section
    
    private var photoPickerSection: some View {
        HStack(alignment: .center, spacing: 18) {
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
                                .fill(Color.appChip(colorScheme))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(FontManager.geist(size: 38, weight: .light))
                                        .foregroundColor(tertiaryTextColor)
                                )
                        }
                    } else {
                        Circle()
                            .fill(Color.appChip(colorScheme))
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(FontManager.geist(size: 38, weight: .light))
                                    .foregroundColor(tertiaryTextColor)
                            )
                    }
                    
                    Circle()
                        .fill(Color.homeGlassAccent)
                        .overlay(
                            Image(systemName: selectedImage != nil || photoURL != nil ? "pencil.circle.fill" : "camera.fill")
                                .font(FontManager.geist(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        )
                        .frame(width: 40, height: 40)
                }
                .frame(width: 104, height: 104)
                .overlay(
                    Circle()
                        .stroke(cardBorderColor, lineWidth: 1.2)
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                Text(heroEyebrowText)
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .tracking(1.2)

                Text(heroTitleText)
                    .font(FontManager.geist(size: 24, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text(heroSupportingText)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text(selectedImage != nil || photoURL != nil ? "Tap the photo to replace it." : "Tap the photo to add one.")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .background(sectionCardBackground(cornerRadius: 28))
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
                formTextField(
                    title: "Name",
                    placeholder: "Enter name",
                    text: $name,
                    icon: "person.fill",
                    isRequired: true
                )
                
                formTextField(
                    title: "Nickname",
                    placeholder: "Optional nickname",
                    text: $nickname,
                    icon: "quote.bubble.fill"
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Relationship")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RelationshipType.allCases, id: \.self) { type in
                                relationshipChip(type: type)
                            }
                        }
                    }
                }
                
                if relationship == .other {
                    formTextField(
                        title: "Custom Relationship",
                        placeholder: "e.g., Cousin, Doctor",
                        text: $customRelationship,
                        icon: "tag.fill"
                    )
                }
                
                Toggle(isOn: $isFavourite) {
                    HStack(spacing: 8) {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color.homeGlassAccent)
                        Text("Mark as Favourite")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(primaryTextColor)
                    }
                }
                .tint(Color.homeGlassAccent)
                .padding(14)
                .background(fieldCardBackground(cornerRadius: 12))
            }
            .padding(14)
            .background(sectionCardBackground(cornerRadius: 22))
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
                    .fill(relationship == type ? Color.homeGlassAccent : Color.appChip(colorScheme))
            )
            .foregroundColor(relationship == type ? .black : secondaryTextColor)
            .overlay(
                Capsule()
                    .stroke(relationship == type ? Color.clear : cardBorderColor, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
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
                                .foregroundColor(Color.homeGlassAccent)
                            Text("Birthday")
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(primaryTextColor)
                        }
                    }
                    .tint(Color.homeGlassAccent)
                    
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
            .padding(14)
            .background(sectionCardBackground(cornerRadius: 22))
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
            .padding(14)
            .background(sectionCardBackground(cornerRadius: 22))
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
            .padding(14)
            .background(sectionCardBackground(cornerRadius: 22))
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appChip(colorScheme))
                Image(systemName: icon)
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.1)
        }
        .foregroundColor(secondaryTextColor)
    }

    private func sectionCardBackground(cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.18) : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 10 : 16,
                x: 0,
                y: colorScheme == .dark ? 6 : 10
            )
    }

    private func fieldCardBackground(cornerRadius: CGFloat = 10) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.appInnerSurface(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
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
            .padding(14)
            .background(fieldCardBackground(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isRequired && text.wrappedValue.isEmpty ?
                        Color.homeGlassAccent.opacity(0.4) :
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
            .padding(14)
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
