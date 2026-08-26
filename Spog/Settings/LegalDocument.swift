import SwiftUI

/// Un document légal : une suite de sections titrées.
/// Les textes vivent dans le catalogue de traduction, jamais en dur ici.
struct LegalDocument: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let updated: LocalizedStringKey
    /// Clés des sections, dans l'ordre. Chaque clé a un `.title` et un `.body`.
    let sections: [String]

    static let privacy = LegalDocument(
        id: "privacy",
        title: "legal.privacy.title",
        updated: "legal.updated",
        sections: ["privacy.collect", "privacy.photos", "privacy.place",
                   "privacy.account", "privacy.share", "privacy.keep",
                   "privacy.rights", "privacy.contact"])

    static let terms = LegalDocument(
        id: "terms",
        title: "legal.terms.title",
        updated: "legal.updated",
        sections: ["terms.object", "terms.access", "terms.safety",
                   "terms.fairplay", "terms.subscription", "terms.accuracy",
                   "terms.property", "terms.contact"])
}

struct LegalDocumentView: View {
    let document: LegalDocument
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(document.updated)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.textMuted)

                    ForEach(document.sections, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(LocalizedStringKey(key + ".title"))
                                .font(Theme.display(16, .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(LocalizedStringKey(key + ".body"))
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
            }
            .background(Theme.background)
            .navigationTitle(Text(document.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("common.close") }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
