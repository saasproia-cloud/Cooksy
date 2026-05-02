import SwiftUI

struct ProfileSettingsView: View {
    enum Units: String, CaseIterable, Identifiable {
        case metric
        case imperial

        var id: String { rawValue }

        var label: String {
            switch self {
            case .metric: return "Métrique (g, ml)"
            case .imperial: return "Impérial (oz, cup)"
            }
        }
    }

    @AppStorage("cooksy.settings.notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("cooksy.settings.units") private var unitsRaw: String = Units.metric.rawValue

    @State private var toastMessage: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            CooksyTheme.background
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Mon profil")
                    culinaryCard

                    sectionTitle("Préférences")
                    preferencesCard

                    sectionTitle("Informations légales")
                    legalCard

                    sectionTitle("À propos")
                    aboutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            if let toastMessage {
                ComingSoonToast(message: toastMessage)
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Paramètres")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(CooksyTheme.secondaryText)
            .padding(.horizontal, 4)
            .padding(.top, 6)
    }

    private var culinaryCard: some View {
        ProfileSectionCard {
            NavigationLink(destination: CulinaryPreferencesView()) {
                HStack(spacing: 14) {
                    rowIcon("sparkles.rectangle.stack")

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Préférences culinaires")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(CooksyTheme.primaryText)
                        Text("Objectif, régime, cuisines, allergies…")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CooksyTheme.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CooksyTheme.secondaryText.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var preferencesCard: some View {
        ProfileSectionCard {
            settingsToggleRow(
                systemImage: "bell.badge",
                title: "Notifications",
                isOn: $notificationsEnabled
            )

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(height: 1)
                .padding(.leading, 66)

            settingsPickerRow(
                systemImage: "ruler",
                title: "Unités de mesure",
                selection: Binding(
                    get: { Units(rawValue: unitsRaw) ?? .metric },
                    set: { unitsRaw = $0.rawValue }
                )
            )

            Rectangle()
                .fill(CooksyTheme.dividerSubtle)
                .frame(height: 1)
                .padding(.leading, 66)

            languageRow
        }
    }

    private var languageRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                rowIcon("globe")

                Text("Langue")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                Text("Français")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text("Cooksy est disponible uniquement en français pour le moment.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText.opacity(0.85))
                .padding(.leading, 66)
                .padding(.trailing, 16)
                .padding(.bottom, 12)
        }
    }

    private var legalCard: some View {
        ProfileSectionCard {
            ProfileNavigationRow(
                systemImage: "lock.shield",
                title: "Politique de confidentialité"
            ) {
                PrivacyPolicyView()
            }

            ProfileNavigationRow(
                systemImage: "doc.text",
                title: "Conditions d'utilisation",
                isLast: true
            ) {
                TermsOfServiceView()
            }
        }
    }

    private var aboutCard: some View {
        ProfileSectionCard {
            settingsReadOnlyRow(
                systemImage: "info.circle",
                title: "Version",
                value: aboutVersionString,
                isLast: true
            )
        }
    }

    private var aboutVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func settingsToggleRow(
        systemImage: String,
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 14) {
            rowIcon(systemImage)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(CooksyTheme.ctaOrange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func settingsPickerRow(
        systemImage: String,
        title: String,
        selection: Binding<Units>
    ) -> some View {
        HStack(spacing: 14) {
            rowIcon(systemImage)

            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(CooksyTheme.primaryText)

            Spacer(minLength: 0)

            Menu {
                Picker(selection: selection, label: EmptyView()) {
                    ForEach(Units.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.wrappedValue.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CooksyTheme.ctaOrangeDark)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingsReadOnlyRow(
        systemImage: String,
        title: String,
        value: String,
        isLast: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                rowIcon(systemImage)

                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)

                Spacer(minLength: 0)

                Text(value)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func rowIcon(_ systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CooksyTheme.blush.opacity(0.55))
                .frame(width: 36, height: 36)

            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            toastMessage = message
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }
}
