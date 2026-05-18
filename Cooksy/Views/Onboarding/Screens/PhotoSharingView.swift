import SwiftUI

/// B-new — "À quelle fréquence tu prends en photo tes plats ?" Single-select.
struct PhotoSharingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        OnboardingChrome(
            title: "Tes plats…\ntu les partages ?",
            subtitle: "Pour savoir si on doit pousser le visuel ou rester sobre.",
            canAdvance: coordinator.canAdvance(from: .photoSharing),
            progress: progress(for: .photoSharing),
            showsBack: OnboardingStep.photoSharing.allowsBack,
            showsSkip: OnboardingStep.photoSharing.allowsSkip,
            onBack: onBack,
            onAdvance: onContinue
        ) {
            VStack(spacing: 12) {
                ForEach(OnboardingPhotoSharing.allCases) { option in
                    BigChoiceCard(
                        systemImage: option.systemImage,
                        title: option.title,
                        subtitle: option.subtitle,
                        isSelected: coordinator.answers.photoSharing == option
                    ) {
                        coordinator.selectPhotoSharing(option)
                    }
                }
            }
        }
    }
}
