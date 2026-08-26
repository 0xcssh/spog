import Foundation

/// Coordonnees du backend Supabase.
/// L'anon key est une cle PUBLIQUE (concue pour etre embarquee dans l'app) —
/// la cle OpenAI, elle, ne vit que cote serveur.
enum BackendConfig {
    /// URL du projet Supabase. Partage avec l'autre app de l'editeur : une seule facture.
    static let supabaseURL = "https://pymrhossbzvhsertjhtc.supabase.co"
    /// Cle "anon / public" du projet Supabase (publique par conception).
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB5bXJob3NzYnp2aHNlcnRqaHRjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ0NjgxNjAsImV4cCI6MjEwMDA0NDE2MH0.0_MV0CDHLOB0_Topq5t-WdGfQiN5Cshz2V2BB5grSnk"

    static var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
