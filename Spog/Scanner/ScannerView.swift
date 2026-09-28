import SwiftUI

/// Écran de capture. La caméra en direct est la seule source d'une prise :
/// pas d'import depuis la photothèque, c'est la règle du jeu.
struct ScannerView: View {
    @Environment(AppState.self) private var app
    @Environment(GarageStore.self) private var garage
    @Environment(ProgressStore.self) private var progress
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(PlayerProfile.self) private var profile
    @Environment(LocationProvider.self) private var location

    /// Seuil de blocage du scan, **exprimé dans le système du pays** : 30 km/h là où on
    /// compte en kilomètres, 20 mph là où on compte en miles. Ce sont deux façons de dire
    /// la même règle pratique — annoncer un chiffre rond et bloquer sur un autre serait
    /// une promesse fausse, et « 30 km/h » ne dit rien à un Américain.
    ///
    /// Le seuil laisse passer l'arrêt, la marche et le pas d'un embouteillage, jamais la
    /// conduite. C'est la parade au risque le plus grave de l'app : pousser quelqu'un à
    /// photographier en roulant.
    static var maxScanSpeed: Measurement<UnitSpeed> {
        Locale.current.measurementSystem == .metric
            ? Measurement(value: 30, unit: .kilometersPerHour)
            : Measurement(value: 20, unit: .milesPerHour)
    }

    /// Le même seuil en km/h, unité dans laquelle la position est mesurée.
    static var maxScanSpeedKmh: Double {
        maxScanSpeed.converted(to: .kilometersPerHour).value
    }

    static var maxScanSpeedText: String {
        maxScanSpeed.formatted(.measurement(width: .abbreviated,
                                            numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    @State private var camera = CameraController()
    @State private var working = false
    @State private var pulse = false
    /// Nombre de plaques masquées sur la dernière prise, montré brièvement.
    @State private var maskedPlates = 0
    @State private var showingPaywall = false
    /// Carte a reveler juste apres une prise.
    @State private var reveal: Reveal?
    /// Prise en attente d'une confirmation du joueur : l'IA n'etait pas assez sure.
    @State private var pending: Pending?
    /// Message d'erreur traduit, quand la prise n'a pas abouti.
    @State private var failure: String?

    struct Reveal: Identifiable {
        let id = UUID()
        let card: CardData
        let isNewModel: Bool
        let questReward: Int
    }

    /// Photo deja masquee, en attente que le joueur designe la voiture.
    struct Pending: Identifiable {
        let id = UUID()
        let photo: UIImage
        let reading: String
        let candidates: [Vehicle]
        let paint: UInt32?
        /// Ce que l'IA a lu, en pieces detachees : de quoi ajouter le modele au
        /// catalogue si le joueur confirme qu'elle avait raison.
        let make: String
        let model: String
        let body: String
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(overline: "scan.section", title: String(localized: "scan.title"))
                .padding(.horizontal, 20)

            viewfinder
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer(minLength: 12)
            Overline(text: hint)
            Spacer(minLength: 14)

            shutter
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .onDisappear { location.stopWatchingSpeed() }
        .task {
            await camera.start()
            // La vitesse n'est suivie que sur cet écran : ailleurs, ce serait
            // de la batterie brûlée pour rien.
            location.startWatchingSpeed()
            // « Ta position te suit en voyage » est promis à l'onboarding : sans ce
            // rafraîchissement, le pays restait celui du jour de l'installation.
            refreshCountryIfAutomatic()
        }
        .onDisappear { camera.stop() }
        .fullScreenCover(isPresented: $showingPaywall) { PaywallView() }
        .fullScreenCover(item: $reveal) { item in
            CatchRevealView(card: item.card, isNewModel: item.isNewModel,
                            questReward: item.questReward,
                            onScanAgain: { Task { await shoot() } })
        }
        .fullScreenCover(item: $pending) { item in
            ConfirmVehicleView(photo: item.photo,
                               reading: item.reading,
                               candidates: item.candidates,
                               onPick: { vehicle in
                                   let photo = item.photo, paint = item.paint
                                   pending = nil
                                   Task { await complete(vehicle, photo: photo, paint: paint) }
                               },
                               onLearn: {
                                   // Le joueur confirme que l'IA avait bien lu : le modèle
                                   // entre au catalogue et sera reconnu d'emblée ensuite.
                                   guard let vehicle = CatalogStore.shared.learn(
                                       make: item.make, model: item.model, body: item.body)
                                   else { return }
                                   let photo = item.photo, paint = item.paint
                                   pending = nil
                                   Task { await complete(vehicle, photo: photo, paint: paint) }
                               },
                               onCancel: { pending = nil })
        }
        .alert(String(localized: "scan.failedTitle"),
               isPresented: Binding(get: { failure != nil },
                                    set: { if !$0 { failure = nil } })) {
            Button(String(localized: "common.ok"), role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    /// Vrai quand l'appareil bouge trop vite pour qu'un scan soit raisonnable.
    /// Une vitesse **inconnue** ne bloque jamais : on ne punit pas un joueur
    /// parce que son GPS ne capte pas.
    private var tooFast: Bool {
        guard let speed = location.speedKmh else { return false }
        return speed > Self.maxScanSpeedKmh
    }

    private var hint: LocalizedStringKey {
        if tooFast { return "scan.tooFast" }
        if working { return "scan.working" }
        if maskedPlates > 0 { return "scan.plateMasked" }
        switch camera.state {
        case .denied:      return "scan.denied"
        case .unavailable: return "scan.noCamera"
        default:           return "scan.hint"
        }
    }

    // MARK: Viseur

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surface)
                .overlay(DotGrid(spacing: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))

            if camera.state == .running {
                CameraPreview(session: camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                RadialGradient(colors: [Theme.accent.opacity(0.18), .clear],
                               center: .center, startRadius: 4, endRadius: 200)
                Image(systemName: camera.state == .denied ? "lock.fill" : "camera.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.textMuted.opacity(0.4))
            }

            if working {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.accentBright, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .shadow(color: Theme.accentBright, radius: 8)
                    .offset(y: pulse ? 120 : -120)
            }

            CornerBrackets(color: tooFast ? RarityTier.trophyGold
                                 : (working ? Theme.accentBright : Theme.accent))
                .padding(18)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        .shadow(color: Theme.accent.opacity(0.3), radius: 20)
    }

    // MARK: Déclencheur

    private var shutter: some View {
        VStack(spacing: 12) {
            if camera.state == .denied {
                Button { openSettings() } label: {
                    Text("scan.openSettings")
                        .font(Theme.label(12)).tracking(1)
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 22).padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button { Task { await shoot() } } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Theme.accentBright, Theme.accent],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 68, height: 68)
                            .shadow(color: Theme.accent.opacity(0.7), radius: 16)
                        Image(systemName: "viewfinder")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(Theme.background)
                    }
                    .opacity(working || tooFast ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(working || tooFast)
            }

            if let left = freeScansLeft {
                Overline(text: "scan.freeLeft \(left)",
                         color: left == 0 ? Color(hex: 0xF5B942) : Theme.textMuted)
            } else {
                Overline(text: "scan.cameraOnly")
            }
        }
    }

    /// Remet le pays à jour quand le joueur a choisi le mode automatique.
    /// Silencieux et sans blocage : une position indisponible ne doit jamais
    /// empêcher un scan, elle laisse simplement le dernier pays connu.
    private func refreshCountryIfAutomatic() {
        guard app.locationMode == .automatic else { return }
        location.currentCountry { code in
            guard let code else { return }
            @Bindable var state = app
            state.country = code
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Prise

    /// Prises restantes avant le paywall. Nil si l'utilisateur est abonne.
    private var freeScansLeft: Int? {
        ScanAllowance.remaining(performed: app.scansPerformed,
                                hasAccess: subscriptions.hasAccess)
    }

    private func shoot() async {
        // Garde-fou : le declencheur est deja desactive, mais une prise lancee
        // juste avant l'acceleration ne doit pas passer non plus.
        guard !tooFast else { return }

        // Le paywall se presente ici, pas a l'ouverture de l'app :
        // il arrive quand le joueur a deja vu ce qu'il achete.
        if ScanAllowance.mustPay(performed: app.scansPerformed,
                                 hasAccess: subscriptions.hasAccess) {
            await MainActor.run { showingPaywall = true }
            return
        }

        working = true
        pulse = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        defer { working = false }

        // Le simulateur n'a pas de caméra : une illustration embarquée y tient lieu de
        // photo, pour que la chaîne réelle (masquage, serveur, rapprochement, confirmation)
        // reste éprouvable sans appareil.
        //
        // Sur un téléphone, une capture ratée doit se dire. Sans cette garde, une panne
        // d'appareil photo offrait une carte tirée au sort pour une voiture jamais vue —
        // et consommait une prise, plus un appel facturé, pour la fabriquer.
        #if targetEnvironment(simulator)
        let raw = await camera.capture() ?? Self.simulatedPhoto()
        #else
        guard let raw = await camera.capture() else {
            await MainActor.run { failure = String(localized: "scan.captureFailed") }
            return
        }
        #endif

        // Masquage des plaques AVANT tout enregistrement : la photo conservée
        // sur l'appareil est déjà anonymisée, pas seulement celle qui part au serveur.
        let (photo, plates) = await PlateBlurrer.mask(raw)
        await MainActor.run { maskedPlates = plates }

        let identification: Identification
        do {
            identification = try await IdentifyService.identify(photo)
        } catch {
            await MainActor.run { failure = error.localizedDescription }
            return
        }

        // Le serveur a répondu : la prise est consommée, même si le joueur renonce
        // à l'écran de confirmation. Sinon l'appel à l'IA serait gratuit à l'infini.
        await MainActor.run {
            @Bindable var state = app
            state.scansPerformed += 1
        }

        let paint = CarPaint.fromServer(identification.color)
        let catalog = CatalogStore.shared

        // Au-dessus du seuil, la carte se crée seule : soit le catalogue connaît la
        // voiture, soit il **l'apprend**. Un modèle absent du catalogue n'est pas une
        // faute du joueur, et lui poser une question à laquelle aucune réponse ne
        // convient serait une impasse — c'est le cas de la moitié des voitures qui
        // roulent hors d'Europe.
        if identification.confidence >= catalog.confidenceThreshold {
            let vehicle = await MainActor.run {
                catalog.match(identification.fullText)
                    ?? catalog.learn(make: identification.make,
                                     model: identification.model,
                                     body: identification.body)
            }
            if let vehicle {
                await complete(vehicle, photo: photo, paint: paint,
                               price: identification.price)
                return
            }
        }

        // En dessous du seuil, c'est le joueur qui tranche : une mauvaise carte est pire
        // qu'une question.
        let candidates = catalog.candidates(for: identification.fullText)
        await MainActor.run {
            pending = Pending(photo: photo, reading: identification.fullText,
                              candidates: candidates, paint: paint,
                              make: identification.make, model: identification.model,
                              body: identification.body)
        }
    }

    /// Met la photo en scène, enregistre la carte et la révèle au joueur.
    private func complete(_ vehicle: Vehicle, photo: UIImage, paint: UInt32?,
                          price: PriceBracket? = nil) async {
        let glow = garage.glowColor(vehicleID: vehicle.id, country: app.country)
        let shot = await CardArtStylizer.stylize(photo, glow: glow)
            ?? StyledShot(stylized: photo, original: photo)
        await MainActor.run { reveal = record(vehicle, shot: shot, paint: paint, price: price) }
    }

    #if targetEnvironment(simulator)
    /// Photo de substitution sur simulateur : un rendu embarqué tiré au sort, que le
    /// serveur identifie pour de vrai. Ne se compile pas dans l'app livrée.
    private static func simulatedPhoto() -> UIImage {
        for vehicle in CatalogStore.shared.vehicles.shuffled() {
            if let art = CarArt.image(for: vehicle.id) { return art }
        }
        return DebugPhoto.sample()
    }
    #endif

    /// Enregistre la prise, entretient la série, valide la quête si elle est remplie,
    /// et rend de quoi révéler la carte au joueur.
    private func record(_ vehicle: Vehicle, shot: StyledShot?, paint: UInt32?,
                        price: PriceBracket? = nil) -> Reveal? {
        let isNew = !garage.hasModel(vehicle.id)
        let item = garage.add(vehicleID: vehicle.id, country: app.country,
                              verified: app.isVerifiedCapture, paint: paint, shot: shot,
                              price: price)

        let quest = QuestFactory.quest(for: Date(), country: app.country,
                                        favourites: profile.favouriteList)
        let tier = CatalogStore.shared.resolve(vehicle, in: app.country).tier
        let satisfied = quest.isSatisfied(vehicle: vehicle, tier: tier,
                                          isNewModel: isNew, todayCount: garage.todayCount)
        let reward = progress.register(satisfies: quest, satisfied: satisfied)

        guard let card = garage.card(item) else { return nil }
        return Reveal(card: card, isNewModel: isNew, questReward: reward)
    }
}

/// Quatre équerres lumineuses, repère de cadrage.
private struct CornerBrackets: View {
    let color: Color
    private let length: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: 0, y: length));      p.addLine(to: .zero); p.addLine(to: CGPoint(x: length, y: 0))
                p.move(to: CGPoint(x: w - length, y: 0));  p.addLine(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: w, y: length))
                p.move(to: CGPoint(x: w, y: h - length));  p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: w - length, y: h))
                p.move(to: CGPoint(x: length, y: h));      p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 0, y: h - length))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.9), radius: 7)
        }
    }
}
