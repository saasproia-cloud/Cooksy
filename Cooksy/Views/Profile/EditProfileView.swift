import PhotosUI
import SwiftUI
import UIKit

/// Sheet pushed from `ProfileView`'s "Modifier le profil" button.
///
/// Lets the user change:
///   - the display name (TextField)
///   - the profile photo (PhotosPicker → Supabase Storage `avatars` bucket)
///
/// Persists via `SessionStore.uploadAvatar` + `SessionStore.updateProfile`.
@MainActor
struct EditProfileView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var initialDisplayName: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var initialAvatarURL: URL?

    @State private var isSaving = false
    @State private var errorMessage: String?

    @FocusState private var nameFieldFocused: Bool

    private let nameMaxLength = 40

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        let nameChanged = trimmedName != initialDisplayName
        let photoChanged = selectedImage != nil
        return nameChanged || photoChanged
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CooksyTheme.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        avatarBlock
                            .padding(.top, 12)

                        nameBlock

                        if let errorMessage {
                            errorCard(errorMessage)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                if isSaving {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }
            }
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onAppear { hydrateFromSession() }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                if let data = try? await selectedPhotoItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    selectedImage = img
                }
            }
        }
    }

    // MARK: Sub-views

    private var avatarBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CooksyTheme.accentGradient)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                    )
                    .shadow(color: CooksyTheme.ctaOrange.opacity(0.25), radius: 18, y: 8)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else if let url = initialAvatarURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        default:
                            Text(initial)
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                } else {
                    Text(initial)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                PremiumCrownBadge(isPremium: sessionStore.isPremium, size: 30)
                    .offset(x: 6, y: -2)
            }
            .overlay(alignment: .bottomTrailing) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(CooksyTheme.primaryText)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle()
                                    .stroke(CooksyTheme.background, lineWidth: 3)
                            )

                        Image(systemName: "camera.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 2)
            }

            Text("Touche l'appareil photo pour changer ta photo")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nom affiché")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(CooksyTheme.secondaryText)
                .padding(.leading, 4)

            HStack {
                TextField("Ton prénom ou pseudo", text: $displayName)
                    .focused($nameFieldFocused)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: displayName) { _, newValue in
                        if newValue.count > nameMaxLength {
                            displayName = String(newValue.prefix(nameMaxLength))
                        }
                    }

                if !displayName.isEmpty {
                    Button {
                        displayName = ""
                        nameFieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(CooksyTheme.secondaryText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CooksyTheme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CooksyTheme.stroke, lineWidth: 1)
            )

            Text("\(trimmedName.count)/\(nameMaxLength) caractères")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.8))
                .padding(.leading, 4)
        }
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: 0xC9471D))
        )
    }

    // MARK: Helpers

    private var initial: String {
        let source = trimmedName.isEmpty ? initialDisplayName : trimmedName
        return source.first.map { String($0).uppercased() } ?? "C"
    }

    private func hydrateFromSession() {
        let raw = sessionStore.profile?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        displayName = raw
        initialDisplayName = raw
        initialAvatarURL = sessionStore.profile?.avatarURL
    }

    // MARK: Save

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            // 1. Upload the photo if changed.
            var newAvatarURL: URL? = nil
            if let img = selectedImage,
               let data = compressForUpload(img) {
                newAvatarURL = try await sessionStore.uploadAvatar(data)
            }

            // 2. Persist name + (maybe) avatar URL.
            let nameToSave = trimmedName != initialDisplayName ? trimmedName : nil
            try await sessionStore.updateProfile(
                displayName: nameToSave,
                avatarURL: newAvatarURL
            )

            dismiss()
        } catch {
            errorMessage = "Impossible d'enregistrer pour le moment. Réessaie dans un instant."
        }
    }

    /// Resizes to a max edge of 1024px and re-encodes as JPEG q=0.8.
    /// Keeps uploads well under the 5 MB Supabase Storage cap.
    private func compressForUpload(_ image: UIImage) -> Data? {
        let maxEdge: CGFloat = 1024
        let maxDimension = max(image.size.width, image.size.height)
        let scale = maxDimension > maxEdge ? maxEdge / maxDimension : 1
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

#Preview {
    EditProfileView()
}
