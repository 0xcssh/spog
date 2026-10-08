import CoreGraphics

/// Le cadrage d'une voiture détourée sur le studio unique (`StudioStage`).
///
/// Géométrie pure, sans UIKit ni Vision : c'est elle qui décide que toutes les voitures
/// ont la même présence, et elle se teste sans appareil.
///
/// Les rendus IA plaçaient chacun leur voiture à leur idée : plus haut, plus petite, plus
/// à droite. Côte à côte dans la chasse de la semaine, ça se voyait. Ici, la voiture est
/// mise à l'échelle **d'après sa propre boîte englobante** (la découpe est recadrée à ses
/// bords) : même largeur maximale, même hauteur maximale, posée sur la même ligne de sol,
/// centrée. Une découpe de 600 px et une de 900 px aux mêmes proportions tombent au même
/// endroit : la présence ne dépend jamais de la résolution de la source.
enum StudioStageLayout {

    /// Ligne de sol, en part de la hauteur du cadre (0 = haut). Le reste, en dessous,
    /// accueille le reflet et l'ombre.
    static let groundLine: CGFloat = 0.76
    /// Largeur maximale de la voiture, en part de la largeur du cadre : une marge égale de
    /// studio de chaque côté, assez pour que le léger grossissement de la parallaxe ne
    /// touche jamais un pare-chocs.
    static let maxWidth: CGFloat = 0.80
    /// Hauteur maximale, en part de la hauteur du cadre : sans elle, un utilitaire haut dans
    /// un cadre large passerait sous le bord supérieur.
    static let maxHeight: CGFloat = 0.58
    /// Profondeur du reflet, en part de la hauteur de la voiture.
    static let reflectionDepth: CGFloat = 0.42

    /// Où poser la découpe dans un cadre de taille `canvas`. `.zero` si l'une des deux
    /// tailles est vide.
    static func carRect(subject: CGSize, in canvas: CGSize) -> CGRect {
        guard subject.width > 0, subject.height > 0,
              canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = min(canvas.width * maxWidth / subject.width,
                        canvas.height * maxHeight / subject.height)
        let width = subject.width * scale
        let height = subject.height * scale
        let ground = canvas.height * groundLine
        return CGRect(x: (canvas.width - width) / 2, y: ground - height,
                      width: width, height: height)
    }

    /// Le reflet : la voiture retournée sous la ligne de sol, coupée à `reflectionDepth`.
    static func reflectionRect(for car: CGRect) -> CGRect {
        CGRect(x: car.minX, y: car.maxY, width: car.width, height: car.height * reflectionDepth)
    }

    /// Une découpe que Vision rend mais qu'on ne doit pas montrer.
    ///
    /// Les anciens rendus posent la voiture sur un sol miroir, entre des néons : Vision
    /// peut prendre le reflet avec la voiture (la boîte double de hauteur, la voiture
    /// paraît moitié plus petite et flotte), un néon seul, ou une découpe trouée. Une
    /// voiture vue de trois quarts est nettement plus large que haute, remplit bien sa boîte
    /// et occupe une bonne part de la largeur d'un rendu centré. Hors de ces bornes, mieux
    /// vaut le rendu tel quel en plein cadre qu'une voiture mal détourée.
    ///
    /// - Parameters:
    ///   - size: taille de la découpe, en pixels.
    ///   - fill: part de sa boîte que le sujet remplit (voir `SubjectLifter`).
    ///   - relativeWidth: largeur de la découpe rapportée à celle du rendu d'origine.
    static func isPlausibleCutout(size: CGSize, fill: Double, relativeWidth: CGFloat) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        let aspect = size.width / size.height
        return (1.15...4.2).contains(aspect) && fill >= 0.35 && relativeWidth >= 0.35
    }

    /// La rangée où les roues touchent le sol : la plus basse dont les pixels opaques
    /// couvrent au moins 4 % de la largeur (deux pneus vus de trois quarts y suffisent ;
    /// un voile d'ombre semi-transparent, non). On ne remonte jamais de plus d'un quart de
    /// la hauteur : au-delà, ce n'est plus un voile, c'est la carrosserie qu'on couperait.
    static func groundRow(solidPerRow: [Int], width: Int) -> Int {
        let last = solidPerRow.count - 1
        guard last >= 0, width > 0 else { return max(0, last) }
        let needed = max(1, width * 4 / 100)
        let floor = last - solidPerRow.count / 4
        var y = last
        while y > floor && solidPerRow[y] < needed { y -= 1 }
        return y
    }
}
