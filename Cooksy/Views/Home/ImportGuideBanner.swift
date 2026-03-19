import SwiftUI

struct ImportGuideBanner: View {
    let title: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Text("🚀")
                    .font(.system(size: 24))

                Text(title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CooksyTheme.secondaryText)
            }
            .padding(.horizontal, 18)
            .frame(height: 68)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: 0xFAF4E8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(hex: 0xEEE6D7), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 16, y: 8)
        }
        .buttonStyle(.plain)
    }
}
