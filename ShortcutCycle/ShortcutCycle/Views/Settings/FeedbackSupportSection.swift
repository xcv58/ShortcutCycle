import SwiftUI

struct FeedbackSupportSection: View {
    let selectedLanguage: String

    var body: some View {
        Section {
            supportRow(
                icon: "bubble.left",
                title: "Help improve ShortcutCycle",
                description: "Report a bug or suggest a feature.",
                buttonTitle: "Send Feedback...",
                destination: AppSupportLinks.feedback,
                destinationDescription: "Opens GitHub Issues in your browser."
            )

            supportRow(
                icon: "star",
                title: "App Store Review",
                description: "Share your experience on the App Store.",
                buttonTitle: "Write a Review...",
                destination: AppSupportLinks.writeReview,
                destinationDescription: "Opens the App Store review page."
            )
        } header: {
            Text("Feedback & Support".localized(language: selectedLanguage))
        }
    }

    private func supportRow(
        icon: String,
        title: String,
        description: String,
        buttonTitle: String,
        destination: URL,
        destinationDescription: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.localized(language: selectedLanguage), systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Link(buttonTitle.localized(language: selectedLanguage), destination: destination)
                .buttonStyle(.bordered)
                .help(destinationDescription.localized(language: selectedLanguage))
                .accessibilityHint(destinationDescription.localized(language: selectedLanguage))

            Text(description.localized(language: selectedLanguage))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
