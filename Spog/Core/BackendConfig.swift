import Foundation

/// Coordonnees du backend.
/// La fonction `identify` tourne sur Neon Functions, dans un projet dedie a Spog
/// (`damp-fire-11684360`) : l'ancien projet Supabase etait partage avec Cyranox, en
/// plan gratuit, et reste bloque depuis septembre 2026. Le code est dans `backend/`.
/// Aucune cle ici : l'URL est publique par nature, et la cle OpenAI ne vit que cote serveur.
enum BackendConfig {
    static let identifyURL = "https://br-plain-fog-b7f3ate2-identify.compute.c-13.us-east-1.aws.neon.tech/"
}
