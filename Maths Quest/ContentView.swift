//  Created by Abdullah Ozdemir on 30/12/2024.
import SwiftUI
import AVFoundation
import PencilKit
import Firebase
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleMobileAds
import StoreKit
import Network

/// What is saved under the "GameSettings" key in UserDefaults, as JSON. Every field is read leniently (a missing or
/// unreadable one gets its default and never discards the others), because players already have saves written by
/// earlier versions. The earliest published format (1.3) also had an `adsRemoved` field. Reading ignores it: Remove Ads
/// comes only from StoreKit (see PurchaseManager), never from a saved flag. Writing always includes it as `false`,
/// because 1.3's decoder requires the key: without it, a player who goes back to 1.3 (a TestFlight tester reinstalling
/// from the App Store, say) sees an empty save, and 1.3's first save then overwrites their progress. `false` is what 1.3
/// itself wrote for every player, paid or not; only a removed cheat code ever wrote `true`.
struct GameSettings: Codable, Equatable {
    var points: Int
    var totalQuestionsAnswered: Int
    var sfxvolume: Double
    var username: String
    var backgroundColourHex: String
    var backgroundOpacity: Double
    var unlockedColours: [String: [Double]]
}

extension GameSettings {
    /// The colour every player starts with. The shop's keys are "#RRGGBB", and so are these. Saves written by earlier
    /// versions used "0000FF" for it, and `normalised()` rewrites those.
    static let defaultColourHex = "#0000FF"
    static let defaultOpacity = 0.8

    static var defaults: GameSettings {
        GameSettings(
            points: 0,
            totalQuestionsAnswered: 0,
            sfxvolume: 0.5,
            username: "",
            backgroundColourHex: defaultColourHex,
            backgroundOpacity: defaultOpacity,
            unlockedColours: [defaultColourHex: [defaultOpacity]]
        )
    }

    enum CodingKeys: String, CodingKey {
        case points, totalQuestionsAnswered, sfxvolume, username, backgroundColourHex, backgroundOpacity, unlockedColours
        /// Written for 1.3, never read. See the type's comment.
        case legacyAdsRemoved = "adsRemoved"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
        try c.encode(totalQuestionsAnswered, forKey: .totalQuestionsAnswered)
        try c.encode(sfxvolume, forKey: .sfxvolume)
        try c.encode(username, forKey: .username)
        try c.encode(backgroundColourHex, forKey: .backgroundColourHex)
        try c.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try c.encode(unlockedColours, forKey: .unlockedColours)
        try c.encode(false, forKey: .legacyAdsRemoved)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings.defaults
        points = (try? c.decodeIfPresent(Int.self, forKey: .points)) ?? d.points
        totalQuestionsAnswered = (try? c.decodeIfPresent(Int.self, forKey: .totalQuestionsAnswered)) ?? d.totalQuestionsAnswered
        sfxvolume = (try? c.decodeIfPresent(Double.self, forKey: .sfxvolume)) ?? d.sfxvolume
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? d.username
        backgroundColourHex = (try? c.decodeIfPresent(String.self, forKey: .backgroundColourHex)) ?? d.backgroundColourHex
        backgroundOpacity = (try? c.decodeIfPresent(Double.self, forKey: .backgroundOpacity)) ?? d.backgroundOpacity
        unlockedColours = (try? c.decodeIfPresent([String: [Double]].self, forKey: .unlockedColours)) ?? d.unlockedColours
    }

    /// "0000FF", "#0000ff" and "0000ff" are all the colour "#0000FF". Anything that isn't six hex digits is kept as it is.
    static func canonicalColourHex(_ hex: String) -> String {
        let digits = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        guard digits.count == 6, digits.allSatisfy({ $0.isHexDigit }) else { return hex }
        return "#" + digits
    }

    static func sameOpacity(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

    /// The same save with anything impossible put right and nothing valid lost: colour keys written with and without
    /// the "#" are merged (keeping every unlocked strength once), the starting colour and the selected colour are
    /// always unlocked, and numbers are kept in range.
    func normalised() -> GameSettings {
        var result = self
        result.points = max(0, points)
        result.totalQuestionsAnswered = max(0, totalQuestionsAnswered)
        result.sfxvolume = sfxvolume.isFinite ? min(max(sfxvolume, 0), 1) : GameSettings.defaults.sfxvolume
        result.backgroundOpacity = (backgroundOpacity.isFinite && backgroundOpacity > 0 && backgroundOpacity <= 1)
            ? backgroundOpacity : GameSettings.defaultOpacity
        result.backgroundColourHex = GameSettings.canonicalColourHex(backgroundColourHex)

        var merged: [String: [Double]] = [:]
        func add(_ hex: String, _ opacity: Double) {
            guard opacity.isFinite, opacity > 0, opacity <= 1 else { return }
            var list = merged[hex] ?? []
            if !list.contains(where: { GameSettings.sameOpacity($0, opacity) }) {
                list.append(opacity)
            }
            merged[hex] = list
        }
        for (hex, opacities) in unlockedColours {
            let key = GameSettings.canonicalColourHex(hex)
            for opacity in opacities { add(key, opacity) }
        }
        add(GameSettings.defaultColourHex, GameSettings.defaultOpacity)
        add(result.backgroundColourHex, result.backgroundOpacity)
        result.unlockedColours = merged.mapValues { $0.sorted() }
        return result
    }
}

enum ColourPurchaseResult: Equatable {
    case purchased
    case alreadyUnlocked
    case notEnoughPoints
    case invalidPrice
}

/// The player's saved progress. There is exactly one: the app creates it and every screen receives it as an environment
/// object. Two instances would each write their own copy of the save over the other's.
class GameData: ObservableObject {
    @Published var points: Int = 0
    @Published var totalQuestionsAnswered: Int = 0
    @Published var sfxvolume: Double = 0.5
    @Published var username: String = ""
    @Published var backgroundColourHex: String = GameSettings.defaultColourHex
    @Published var backgroundOpacity: Double = GameSettings.defaultOpacity
    @Published var unlockedColours: [String: [Double]] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Tidying an old save (for example the "0000FF" key) is written back at once, so it happens only once. So is a
        // save 1.3 couldn't read, so that going back to 1.3 never shows an empty game.
        if loadData() { saveData() }
    }

    func saveData() {
        let settings = GameSettings(
            points: points,
            totalQuestionsAnswered: totalQuestionsAnswered,
            sfxvolume: sfxvolume,
            username: username,
            backgroundColourHex: backgroundColourHex,
            backgroundOpacity: backgroundOpacity,
            unlockedColours: unlockedColours
        )
        saveSettings(settings, to: defaults)

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }


    func skipQuestion(resetQuestion: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            resetQuestion()
        }
    }

    /// Replaces every value with what is saved, so loading again can't duplicate anything.
    /// Returns whether the saved copy should be rewritten (nothing saved yet, it needed tidying, or 1.3 couldn't read it).
    @discardableResult
    func loadData() -> Bool {
        let stored = loadSettings(from: defaults)
        let settings = stored.settings.normalised()
        points = settings.points
        totalQuestionsAnswered = settings.totalQuestionsAnswered
        sfxvolume = settings.sfxvolume
        username = settings.username
        backgroundColourHex = settings.backgroundColourHex
        backgroundOpacity = settings.backgroundOpacity
        unlockedColours = settings.unlockedColours
        return !stored.found || settings != stored.settings || !savedSettingsReadableBy13(in: defaults)
    }

    // MARK: Shop

    func isColourUnlocked(_ hex: String, opacity: Double) -> Bool {
        let key = GameSettings.canonicalColourHex(hex)
        return (unlockedColours[key] ?? []).contains { GameSettings.sameOpacity($0, opacity) }
            || isColourSelected(key, opacity: opacity)
    }

    func isColourSelected(_ hex: String, opacity: Double) -> Bool {
        GameSettings.canonicalColourHex(hex) == GameSettings.canonicalColourHex(backgroundColourHex)
            && GameSettings.sameOpacity(opacity, backgroundOpacity)
    }

    /// Takes the price and unlocks the colour, once. An unlocked colour costs nothing, points never go below zero, and
    /// the check and the change happen together, so a second tap before the screen redraws can't pay again.
    @discardableResult
    func purchaseColour(hex: String, opacity: Double, price: Int) -> ColourPurchaseResult {
        guard price >= 0, opacity.isFinite, opacity > 0, opacity <= 1 else { return .invalidPrice }
        if isColourUnlocked(hex, opacity: opacity) { return .alreadyUnlocked }
        guard points >= price else { return .notEnoughPoints }
        points -= price
        unlockedColours[GameSettings.canonicalColourHex(hex), default: []].append(opacity)
        saveData()
        return .purchased
    }

    /// Makes an unlocked colour the background. A locked one is refused, so a selection is always an unlocked colour.
    @discardableResult
    func selectColour(hex: String, opacity: Double) -> Bool {
        guard isColourUnlocked(hex, opacity: opacity) else { return false }
        backgroundColourHex = GameSettings.canonicalColourHex(hex)
        backgroundOpacity = opacity
        saveData()
        return true
    }

    /// Takes points away (the shop's "Spend Points"). Refused when it is not a positive amount or is more than the balance.
    @discardableResult
    func spendPoints(_ amount: Int) -> Bool {
        guard amount > 0, amount <= points else { return false }
        points -= amount
        saveData()
        return true
    }
}

func safeAreaTopInset() -> CGFloat {
    guard let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })
    else {
        return 0
    }
    return window.safeAreaInsets.top
}

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)
    
    @Published var isConnected: Bool = true

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}

@MainActor
class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()

    // The single source of truth for Remove Ads. It is only true while StoreKit reports a
    // verified, unrevoked "removeads" transaction. The cached copy is just a fallback until
    // that check finishes at launch, and the check always overwrites it.
    @Published private(set) var adsRemoved: Bool
    @Published private(set) var product: Product?
    @Published private(set) var productLoadFailed = false
    @Published private(set) var isBusy = false
    @Published private(set) var isPending = false
    @Published private(set) var statusMessage: String?

    private let productID = "removeads"
    private static let cacheKey = "adsRemoved"
    private var updatesTask: Task<Void, Never>?
    private var productLoadTask: Task<Void, Never>?
    private var entitlementCheckID = 0

    init() {
        adsRemoved = UserDefaults.standard.bool(forKey: Self.cacheKey)
        // The only Transaction.updates listener. It picks up Ask to Buy approvals, purchases
        // made on other devices, refunds and revocations, and transactions left unfinished.
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await refreshEntitlements()
            await fetchProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func fetchProducts() async {
        if product != nil { return }
        // Callers share one request, so a slow failed load can't overwrite a successful one.
        if let task = productLoadTask {
            await task.value
            return
        }
        let task = Task {
            productLoadFailed = false
            let loaded = try? await Product.products(for: [productID]).first
            product = loaded
            productLoadFailed = (loaded == nil)
            productLoadTask = nil
        }
        productLoadTask = task
        await task.value
    }

    // Returns whether StoreKit currently reports a verified, unrevoked Remove Ads purchase.
    @discardableResult
    func refreshEntitlements() async -> Bool {
        entitlementCheckID += 1
        let checkID = entitlementCheckID
        var entitled = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == productID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        // Only the latest answer is applied. A newer check, or a verified purchase, has already set it.
        if checkID == entitlementCheckID {
            setAdsRemoved(entitled)
        }
        return entitled
    }

    func buyRemoveAds() async {
        guard !isBusy else { return }
        guard let product = product else {
            statusMessage = "Remove Ads couldn't be loaded from the App Store. Please check your internet connection and try again."
            await fetchProducts()
            return
        }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await apply(transaction)
                await transaction.finish()
            case .success(.unverified(_, _)):
                // Nothing is granted. The transaction is left unfinished so StoreKit offers it again.
                statusMessage = "Your purchase couldn't be verified, so ads have not been removed. Please try Restore Purchases, or contact support if this keeps happening."
            case .pending:
                isPending = true
                statusMessage = "Your purchase is waiting for approval (for example, Ask to Buy). Ads will be removed automatically once it's approved."
            case .userCancelled:
                statusMessage = "Purchase cancelled. You have not been charged."
            @unknown default:
                statusMessage = "The purchase didn't complete. You have not been charged."
            }
        } catch {
            statusMessage = purchaseErrorMessage(for: error)
        }
    }

    func restorePurchases() async {
        guard !isBusy else { return }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            statusMessage = "Restore cancelled."
            return
        } catch {
            let entitled = await refreshEntitlements()
            statusMessage = entitled
                ? "Remove Ads is already active on this device."
                : "Couldn't connect to the App Store to restore purchases. Please check your internet connection and try again."
            return
        }
        let entitled = await refreshEntitlements()
        statusMessage = entitled
            ? "Purchase restored. Ads have been removed."
            : "No Remove Ads purchase was found for this Apple Account."
    }

    func clearStatusMessage() {
        if !isPending {
            statusMessage = nil
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        // Never grant anything from a transaction StoreKit couldn't verify.
        guard case .verified(let transaction) = result else { return }
        if transaction.productID == productID {
            let wasPending = isPending
            await apply(transaction)
            if wasPending && adsRemoved {
                statusMessage = "Your purchase was approved. Ads have been removed."
            }
        }
        await transaction.finish()
    }

    private func apply(_ transaction: StoreKit.Transaction) async {
        if transaction.revocationDate == nil {
            setAdsRemoved(true)
        } else {
            // Refunded or revoked, so ask StoreKit what this Apple Account is still entitled to.
            await refreshEntitlements()
        }
    }

    private func setAdsRemoved(_ value: Bool) {
        entitlementCheckID += 1
        if adsRemoved != value {
            adsRemoved = value
        }
        if value {
            isPending = false
        }
        UserDefaults.standard.set(value, forKey: Self.cacheKey)
    }

    private func purchaseErrorMessage(for error: Error) -> String {
        switch error {
        case StoreKitError.userCancelled:
            return "Purchase cancelled. You have not been charged."
        case StoreKitError.networkError(_):
            return "Couldn't connect to the App Store. Please check your internet connection and try again."
        case StoreKitError.notAvailableInStorefront, Product.PurchaseError.productUnavailable:
            return "Remove Ads isn't available in your country or region."
        case Product.PurchaseError.purchaseNotAllowed:
            return "Purchases aren't allowed on this device. Please check Screen Time restrictions and try again."
        default:
            return "The purchase couldn't be completed, and you have not been charged. Please try again later."
        }
    }
}

// MARK: - Advertising in a children's app

/// The ad units Maths Quest requests from. Debug builds, which include the unit tests and
/// simulator runs, use Google's sample units, so they only ever get test ads. Release builds use
/// the app's own AdMob units.
/// https://developers.google.com/admob/ios/test-ads
struct AdUnitIDs: Equatable {
    let interstitial: String
    let rewardedInterstitial: String

    static let googleTest = AdUnitIDs(
        interstitial: "ca-app-pub-3940256099942544/4411468910",
        rewardedInterstitial: "ca-app-pub-3940256099942544/6978759866"
    )

    static let production = AdUnitIDs(
        interstitial: "ca-app-pub-4802921306068209/3600942466",
        rewardedInterstitial: "ca-app-pub-4802921306068209/1060347527"
    )

    static func forBuild(isDebug: Bool) -> AdUnitIDs {
        isDebug ? googleTest : production
    }

    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    static let current = forBuild(isDebug: isDebugBuild)
}

/// The Google Mobile Ads request settings that AdPrivacy sets. RequestConfiguration is the real
/// one, and the tests use a recorder.
protocol AdRequestConfiguring: AnyObject {
    var tagForChildDirectedTreatment: NSNumber? { get set }
    var tagForUnderAgeOfConsent: NSNumber? { get set }
    var maxAdContentRating: GADMaxAdContentRating? { get set }
    var publisherPrivacyPersonalizationState: PublisherPrivacyPersonalizationState { get set }
    func setPublisherFirstPartyIDEnabled(_ enabled: Bool)
}

extension RequestConfiguration: AdRequestConfiguring {}

/// Maths Quest is made for primary-school children, so every ad request is:
/// - Child-directed. tagForChildDirectedTreatment is how Google Mobile Ads 12.x asks for the
///   Child age treatment. ageRestrictedTreatment replaced it in 13.3.0. Child treatment turns off
///   personalised ads, remarketing and requests to third-party ad vendors.
/// - Limited to ads rated G.
/// - Non-personalised.
/// - Sent without the publisher first-party ID.
///
/// tagForUnderAgeOfConsent is left unset because Google says not to set it alongside
/// child-directed treatment, which takes precedence. See
/// https://developers.google.com/admob/ios/targeting.
enum AdPrivacy {
    static func apply(to configuration: AdRequestConfiguring) {
        configuration.tagForChildDirectedTreatment = true
        configuration.tagForUnderAgeOfConsent = nil
        configuration.maxAdContentRating = .general
        configuration.publisherPrivacyPersonalizationState = .disabled
        configuration.setPublisherFirstPartyIDEnabled(false)
    }
}

/// Every ad request is made by makeRequest(). Each time, it applies AdPrivacy first, and the first
/// time it also starts Google Mobile Ads, so the settings are in place before the SDK starts and
/// before any ad is requested, as Google asks. Only AdManager's loads call it, and they stop once
/// Remove Ads is bought, so the SDK is never started for purchasers.
@MainActor
final class AdSDK {
    static let shared = AdSDK(
        configuration: MobileAds.shared.requestConfiguration,
        startSDK: { MobileAds.shared.start(completionHandler: nil) }
    )

    private let configuration: AdRequestConfiguring
    private let startSDK: () -> Void
    private(set) var isStarted = false

    init(configuration: AdRequestConfiguring, startSDK: @escaping () -> Void) {
        self.configuration = configuration
        self.startSDK = startSDK
    }

    func makeRequest() -> Request {
        AdPrivacy.apply(to: configuration)
        if !isStarted {
            isStarted = true
            startSDK()
        }
        return Request()
    }
}

/// When the interstitial may appear. It's shown only at a break: when a menu (the main menu or a
/// year menu) comes on screen and no activity is on screen. It therefore can't interrupt a
/// question, a form or the app opening. At least three minutes always pass after launch, and after
/// any full-screen ad including a Skip ad, before the next one. See
/// https://support.google.com/admob/answer/6201362.
struct InterstitialSchedule {
    static let minimumInterval: TimeInterval = 180
    /// How long a menu has to stay on screen before the ad can appear. This gives the screen being
    /// left time to disappear, and lets a quick tap into an activity get there first.
    static let settleDelay: TimeInterval = 0.8

    /// Launch time, or the end of the last full-screen ad.
    private(set) var noAdsSince: Date
    /// The activity screens currently on screen.
    private(set) var questionScreens: Set<UUID> = []

    init(appLaunched: Date = Date()) {
        noAdsSince = appLaunched
    }

    mutating func questionScreenAppeared(_ id: UUID) {
        questionScreens.insert(id)
    }

    mutating func questionScreenDisappeared(_ id: UUID) {
        questionScreens.remove(id)
    }

    mutating func fullScreenAdEnded(at date: Date) {
        noAdsSince = date
    }

    func canShowAtBreak(now: Date, adsRemoved: Bool, adOnScreen: Bool) -> Bool {
        !adsRemoved && !adOnScreen && questionScreens.isEmpty
            && now.timeIntervalSince(noAdsSince) >= Self.minimumInterval
    }
}

/// What happens when Skip Question is tapped. A rewarded interstitial has to be introduced by a
/// screen that says what the reward is and lets the user decline. So the ad plays only after the
/// child chooses "Watch ad", and saying no leaves them on the question. See
/// https://support.google.com/admob/answer/7313578.
enum SkipAdStep: Equatable {
    /// Remove Ads was bought, so the question is skipped with no ad and no prompt.
    case skipWithoutAd
    /// An ad, or the question about watching one, is already on screen.
    case ignore
    /// No ad is loaded, so the question isn't skipped.
    case adNotReady
    /// Ask whether to watch the ad.
    case askToWatchAd
    /// The child chose to watch and the ad is still ready.
    case showAd
    /// The child said no thanks.
    case stay

    static func onTap(adsRemoved: Bool, adOnScreen: Bool, askingToWatch: Bool, adReady: Bool) -> SkipAdStep {
        if adsRemoved { return .skipWithoutAd }
        if adOnScreen || askingToWatch { return .ignore }
        return adReady ? .askToWatchAd : .adNotReady
    }

    static func onAnswer(watch: Bool, adsRemoved: Bool, adOnScreen: Bool, adReady: Bool) -> SkipAdStep {
        if !watch { return .stay }
        if adsRemoved { return .skipWithoutAd }
        if adOnScreen { return .ignore }
        return adReady ? .showAd : .adNotReady
    }
}

@MainActor
class AdManager: NSObject, FullScreenContentDelegate {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    private var interstitialLoadedAt: Date?
    private var isLoadingInterstitial = false
    private var interstitialRetries = 0
    private let interstitialAdUnitID = AdUnitIDs.current.interstitial

    private var rewardedInterstitial: RewardedInterstitialAd?
    private var rewardedLoadedAt: Date?
    private var isLoadingRewarded = false
    private var rewardedRetries = 0
    private let rewardedInterstitialAdUnitID = AdUnitIDs.current.rewardedInterstitial

    // Holds the ad on screen until it's dismissed, and stops a second ad opening on top of it.
    private var presentedAd: FullScreenPresentingAd?
    // True while the child is being asked whether to watch a Skip ad.
    private var isAskingToWatchSkipAd = false
    private var schedule = InterstitialSchedule()

    // Loaded ads expire after an hour, so older ones are replaced instead of shown.
    private let adLifetime: TimeInterval = 55 * 60
    nonisolated static let maxLoadRetries = 4

    private var adsRemoved: Bool { PurchaseManager.shared.adsRemoved }

    private override init() {
        super.init()
        loadInterstitialAd()
        loadRewardedInterstitialAd()
    }

    /// Ads are never requested once Remove Ads is bought, or while an ad is on screen, already
    /// loading, or loaded and still fresh.
    nonisolated static func shouldLoad(adsRemoved: Bool, adOnScreen: Bool, isLoading: Bool, hasFreshAd: Bool) -> Bool {
        !adsRemoved && !adOnScreen && !isLoading && !hasFreshAd
    }

    func loadInterstitialAd() {
        guard Self.shouldLoad(adsRemoved: adsRemoved, adOnScreen: presentedAd != nil, isLoading: isLoadingInterstitial,
                              hasFreshAd: interstitial != nil && isFresh(interstitialLoadedAt)) else { return }
        isLoadingInterstitial = true
        let request = AdSDK.shared.makeRequest()
        Task {
            let ad = try? await InterstitialAd.load(with: interstitialAdUnitID, request: request)
            isLoadingInterstitial = false
            if let ad = ad {
                ad.fullScreenContentDelegate = self
                interstitial = ad
                interstitialLoadedAt = Date()
                interstitialRetries = 0
            } else if interstitialRetries < Self.maxLoadRetries {
                interstitialRetries += 1
                retry(after: interstitialRetries) { $0.loadInterstitialAd() }
            }
        }
    }

    // Activity screens report themselves here, so the interstitial can't appear over a question.
    func questionScreenAppeared(_ id: UUID) {
        schedule.questionScreenAppeared(id)
    }

    func questionScreenDisappeared(_ id: UUID) {
        schedule.questionScreenDisappeared(id)
    }

    /// Called by a menu once it has been on screen for InterstitialSchedule.settleDelay.
    func showInterstitialAtBreak() {
        guard schedule.canShowAtBreak(now: Date(), adsRemoved: adsRemoved,
                                      adOnScreen: presentedAd != nil || isAskingToWatchSkipAd) else { return }
        guard let ad = interstitial, isFresh(interstitialLoadedAt) else {
            interstitial = nil
            loadInterstitialAd()
            return
        }
        // Never over an alert, such as the No Internet message.
        guard let presenter = topViewController(from: nil), !(presenter is UIAlertController) else { return }
        presentedAd = ad
        ad.present(from: presenter)
    }

    func loadRewardedInterstitialAd() {
        guard Self.shouldLoad(adsRemoved: adsRemoved, adOnScreen: presentedAd != nil, isLoading: isLoadingRewarded,
                              hasFreshAd: rewardedInterstitial != nil && isFresh(rewardedLoadedAt)) else { return }
        isLoadingRewarded = true
        let request = AdSDK.shared.makeRequest()
        Task {
            let ad = try? await RewardedInterstitialAd.load(with: rewardedInterstitialAdUnitID, request: request)
            isLoadingRewarded = false
            if let ad = ad {
                ad.fullScreenContentDelegate = self
                rewardedInterstitial = ad
                rewardedLoadedAt = Date()
                rewardedRetries = 0
            } else if rewardedRetries < Self.maxLoadRetries {
                rewardedRetries += 1
                retry(after: rewardedRetries) { $0.loadRewardedInterstitialAd() }
            }
        }
    }

    private var isRewardedAdReady: Bool {
        rewardedInterstitial != nil && isFresh(rewardedLoadedAt)
    }

    func showRewardedInterstitialAd(from viewController: UIViewController, onRewardEarned: @escaping () -> Void) {
        switch SkipAdStep.onTap(adsRemoved: adsRemoved, adOnScreen: presentedAd != nil,
                                askingToWatch: isAskingToWatchSkipAd, adReady: isRewardedAdReady) {
        case .skipWithoutAd:
            onRewardEarned()
        case .adNotReady:
            showRewardedAdNotReady(from: viewController)
        case .askToWatchAd:
            askToWatchSkipAd(from: viewController, onRewardEarned: onRewardEarned)
        case .ignore, .showAd, .stay:
            break
        }
    }

    private func askToWatchSkipAd(from viewController: UIViewController, onRewardEarned: @escaping () -> Void) {
        guard let presenter = topViewController(from: viewController) else { return }
        isAskingToWatchSkipAd = true
        let alert = UIAlertController(
            title: "Skip this question?",
            message: "To skip, watch a short video ad. You won't get a point for this question.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "No thanks", style: .cancel) { [weak self] _ in
            self?.answerSkipAdQuestion(watch: false, from: viewController, onRewardEarned: onRewardEarned)
        })
        alert.addAction(UIAlertAction(title: "Watch ad", style: .default) { [weak self] _ in
            self?.answerSkipAdQuestion(watch: true, from: viewController, onRewardEarned: onRewardEarned)
        })
        presenter.present(alert, animated: true)
    }

    private func answerSkipAdQuestion(watch: Bool, from viewController: UIViewController, onRewardEarned: @escaping () -> Void) {
        isAskingToWatchSkipAd = false
        switch SkipAdStep.onAnswer(watch: watch, adsRemoved: adsRemoved, adOnScreen: presentedAd != nil,
                                   adReady: isRewardedAdReady) {
        case .skipWithoutAd:
            onRewardEarned()
        case .adNotReady:
            showRewardedAdNotReady(from: viewController)
        case .showAd:
            guard let ad = rewardedInterstitial else { return }
            presentedAd = ad
            ad.present(from: topViewController(from: viewController)) {
                onRewardEarned()
            }
        case .ignore, .askToWatchAd, .stay:
            break
        }
    }

    private func showRewardedAdNotReady(from viewController: UIViewController) {
        rewardedInterstitial = nil
        rewardedRetries = 0
        loadRewardedInterstitialAd()
        showMessage(
            title: "Ad Not Ready",
            message: "Skipping a question needs a short video ad, and one hasn't loaded yet. Please check your internet connection and try again in a few seconds.",
            from: viewController
        )
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        presentedAd = nil
        schedule.fullScreenAdEnded(at: Date())
        if ad is InterstitialAd {
            interstitial = nil
            loadInterstitialAd()
        } else if ad is RewardedInterstitialAd {
            rewardedInterstitial = nil
            loadRewardedInterstitialAd()
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        presentedAd = nil
        if ad is InterstitialAd {
            interstitial = nil
            loadInterstitialAd()
        } else if ad is RewardedInterstitialAd {
            rewardedInterstitial = nil
            loadRewardedInterstitialAd()
            showMessage(
                title: "Ad Not Available",
                message: "The video ad couldn't be shown, so the question wasn't skipped. Please try again in a few seconds.",
                from: nil
            )
        }
    }

    func adDidRecordClick(_ ad: FullScreenPresentingAd) {}

    func adDidRecordImpression(_ ad: FullScreenPresentingAd) {}

    private func isFresh(_ loadedAt: Date?) -> Bool {
        guard let loadedAt = loadedAt else { return false }
        return Date().timeIntervalSince(loadedAt) < adLifetime
    }

    // Waits 10, 20, 40 then 80 seconds between attempts.
    nonisolated static func retryDelay(forAttempt attempt: Int) -> TimeInterval {
        10 * pow(2, Double(attempt - 1))
    }

    private func retry(after attempt: Int, _ load: @escaping (AdManager) -> Void) {
        let delay = Self.retryDelay(forAttempt: attempt)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if let self = self {
                load(self)
            }
        }
    }

    private func topViewController(from viewController: UIViewController?) -> UIViewController? {
        var top = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func showMessage(title: String, message: String, from viewController: UIViewController?) {
        guard let presenter = topViewController(from: viewController) else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}

/// Marks an activity screen. While one is on screen the interstitial can't appear, so an ad never
/// interrupts a question.
private struct QuestionScreen: ViewModifier {
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { AdManager.shared.questionScreenAppeared(id) }
            .onDisappear { AdManager.shared.questionScreenDisappeared(id) }
    }
}

/// Marks a menu. Arriving at one is a natural break, so the interstitial may appear there if
/// InterstitialSchedule allows it.
private struct AdBreakPoint: ViewModifier {
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isOnScreen = true
                DispatchQueue.main.asyncAfter(deadline: .now() + InterstitialSchedule.settleDelay) {
                    if isOnScreen {
                        AdManager.shared.showInterstitialAtBreak()
                    }
                }
            }
            .onDisappear { isOnScreen = false }
    }
}

extension View {
    func questionScreen() -> some View {
        modifier(QuestionScreen())
    }

    func adBreakPoint() -> some View {
        modifier(AdBreakPoint())
    }
}

let gameSettingsKey = "GameSettings"
/// Where an unreadable save is kept (once) before a fresh one is started, so it can still be recovered.
let unreadableGameSettingsKey = "GameSettings.unreadable"

func saveSettings(_ settings: GameSettings, to defaults: UserDefaults = .standard) {
    let encoder = JSONEncoder()
    do {
        let encoded = try encoder.encode(settings)
        defaults.set(encoded, forKey: gameSettingsKey)
    } catch {
    }
}

/// The save exactly as 1.3 decodes it: every key required, with these types. Used only to check that a player who goes
/// back to 1.3 can still read what is saved.
private struct Version13Save: Decodable {
    let points: Int
    let totalQuestionsAnswered: Int
    let sfxvolume: Double
    let username: String
    let backgroundColourHex: String
    let backgroundOpacity: Double
    let unlockedColours: [String: [Double]]
    let adsRemoved: Bool
}

/// Whether 1.3 could read the saved progress. One written by an earlier build of this version, without `adsRemoved`,
/// can't be.
func savedSettingsReadableBy13(in defaults: UserDefaults = .standard) -> Bool {
    guard let saved = defaults.data(forKey: gameSettingsKey) else { return false }
    return (try? JSONDecoder().decode(Version13Save.self, from: saved)) != nil
}

/// What is saved, and whether anything was. A save that can't be read at all starts a fresh game, but is copied aside
/// first; one that is missing fields or has odd values keeps everything that can be read.
func loadSettings(from defaults: UserDefaults = .standard) -> (settings: GameSettings, found: Bool) {
    guard let saved = defaults.data(forKey: gameSettingsKey) else {
        return (GameSettings.defaults, false)
    }
    do {
        return (try JSONDecoder().decode(GameSettings.self, from: saved), true)
    } catch {
        if defaults.data(forKey: unreadableGameSettingsKey) == nil {
            defaults.set(saved, forKey: unreadableGameSettingsKey)
        }
        return (GameSettings.defaults, false)
    }
}

class SFXPlayer: ObservableObject {
    var player: AVAudioPlayer?
    
    func playSound(named name: String, volume: Double) {
        if let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
            do {
                player = try AVAudioPlayer(contentsOf: url)
                player?.volume = Float(volume)
                player?.play()
            } catch {
            }
        }
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Draws a button's coloured box. It goes on the button's label rather than around the button, because only the
    /// label can be tapped: around the button, just the words in the box would respond. `tapMargin` lets a box that's
    /// shorter than 44 points be tapped just outside its edge too, without moving anything.
    func buttonBox(_ colour: Color, cornerRadius: CGFloat, tapMargin: CGFloat = 0) -> some View {
        background(colour)
            .cornerRadius(cornerRadius)
            .padding(tapMargin)
            .contentShape(Rectangle())
            .padding(-tapMargin)
    }

    /// A system font of `size` points that grows with a larger text size in Settings, up to `maximum` points. See
    /// `ScaledFont`.
    func scaledFont(size: CGFloat, maximum: CGFloat = ScaledFont.usualMaximum) -> some View {
        modifier(ScaledFont(size: size, maximum: maximum))
    }

    /// The margin between an answer box's text field and the edge of its white box. Goes straight on the `TextField`,
    /// in place of `.padding()`. A box drawn shorter than `tapHeight` can also be tapped just above and below it, up
    /// to that height, without taking up any more room. See `AnswerBoxMargin`.
    ///
    /// When another answer box is close above or below, `nextBox` says which side it is on and `centresApart` how far
    /// apart the two boxes' centres are. The tap area then stops halfway between them and is made up on the other side.
    func answerBoxMargin(_ length: CGFloat? = nil, tapHeight: CGFloat = 0, nextBox: VerticalEdge? = nil,
                         centresApart: CGFloat = 0) -> some View {
        modifier(AnswerBoxMargin(length: length, tapHeight: tapHeight, nextBox: nextBox, centresApart: centresApart))
    }

    /// The keyboard for an answer box, in place of `.keyboardType`. See `AnswerKeyboard`.
    func answerKeyboard(_ type: UIKeyboardType) -> some View {
        let shown = AnswerKeyboard.type(type, on: UIDevice.current.userInterfaceIdiom)
        return keyboardType(shown).autocorrectionDisabled(shown != type)
    }
}

/// The iPad has no number pad: for `.numberPad` and `.decimalPad` it shows the numbers page of its full keyboard. It
/// also shrinks that keyboard to a thin bar when a tap that follows typing lifts off, before the tap reaches the app,
/// so the screen moves under the finger and a tap on Enter does nothing. Asking for the numbers page by name shows the
/// same keys without that, and with autocorrection off it has no word suggestions either. iPhones keep their pads.
enum AnswerKeyboard {
    static func type(_ type: UIKeyboardType, on idiom: UIUserInterfaceIdiom) -> UIKeyboardType {
        guard idiom == .pad, type == .numberPad || type == .decimalPad else { return type }
        return .numbersAndPunctuation
    }
}

/// An answer box is a text field with a white margin round it. Only the text field itself responds to a tap, so a tap
/// on the margin, which looks like part of the box, would do nothing. This makes a tap anywhere on the box put the
/// cursor in the field.
struct AnswerBoxMargin: ViewModifier {
    let length: CGFloat?
    let tapHeight: CGFloat
    var nextBox: VerticalEdge? = nil
    var centresApart: CGFloat = 0
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .padding(.all, length)
            .contentShape(TapArea(minHeight: tapHeight, nextBox: nextBox, centresApart: centresApart))
            .onTapGesture { isFocused = true }
    }

    /// The box, made taller by the same amount above and below if it's shorter than `minHeight`. Next to another box,
    /// it grows towards that box only as far as halfway between their centres, and the rest of the way on its other
    /// side, so the two boxes' tap areas meet without overlapping.
    struct TapArea: Shape {
        let minHeight: CGFloat
        var nextBox: VerticalEdge? = nil
        var centresApart: CGFloat = 0

        func path(in rect: CGRect) -> Path {
            Path(area(of: rect))
        }

        func area(of rect: CGRect) -> CGRect {
            let extra = max(0, minHeight - rect.height)
            var (above, below) = (extra / 2, extra / 2)
            if let nextBox {
                let room = max(0, centresApart / 2 - rect.height / 2)
                switch nextBox {
                case .top:
                    above = min(above, room)
                    below = extra - above
                case .bottom:
                    below = min(below, room)
                    above = extra - below
                }
            }
            return CGRect(x: rect.minX, y: rect.minY - above, width: rect.width, height: rect.height + above + below)
        }
    }
}

/// A fraction typed into two answer boxes, the numerator above the denominator with the fraction bar between them. Each
/// box is as tall as its text and wide enough for its placeholder, so a larger text size in Settings makes the boxes
/// bigger rather than cutting their text off. See `FractionBoxLayout`.
struct FractionAnswerBoxes: View {
    @Binding var numerator: String
    @Binding var denominator: String
    /// What Return does in either box.
    let submit: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = FractionBoxLayout(textSize: FractionBoxLayout.textSize(for: dynamicTypeSize),
                                       screen: UIScreen.main.bounds.size)
        VStack(spacing: FractionBoxLayout.spacing) {
            box("Numerator", text: $numerator, hint: "The top number of the fraction.", nextBox: .bottom, layout)
            Rectangle()
                .frame(width: layout.boxSize.width, height: layout.barHeight)
                .cornerRadius(20)
                .foregroundStyle(.onBackground)
            box("Denominator", text: $denominator, hint: "The bottom number of the fraction.", nextBox: .top, layout)
        }
    }

    private func box(_ title: LocalizedStringKey, text: Binding<String>, hint: LocalizedStringKey,
                     nextBox: VerticalEdge, _ layout: FractionBoxLayout) -> some View {
        TextField(answerBox: title, text: text)
            .accessibilityHint(hint)
            .font(.system(size: layout.textSize))
            .answerBoxMargin(FractionBoxLayout.margin, tapHeight: 44, nextBox: nextBox,
                             centresApart: layout.centresApart)
            .frame(width: layout.boxSize.width, height: layout.boxSize.height)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(20)
            .frame(height: layout.roomHeight)
            .answerKeyboard(.numberPad)
            .multilineTextAlignment(.center)
            .onSubmit(submit)
    }
}

/// The sizes of a fraction's answer boxes for a text size and a screen. Each white box is a line of text with a margin
/// round it, wide enough for the longer placeholder, and takes up at least the room a box has always had, so at the
/// standard text size the boxes are where they were. Kept apart from the view so every text size and screen can be
/// checked.
struct FractionBoxLayout: Equatable {
    /// The white margin round the text.
    static let margin: CGFloat = 5
    /// The space either side of the fraction bar.
    static let spacing: CGFloat = 5
    static let placeholders = ["Numerator", "Denominator"]

    let textSize: CGFloat
    /// The white box.
    let boxSize: CGSize
    /// The height each box takes up, with the box in the middle of it.
    let roomHeight: CGFloat
    let barHeight: CGFloat

    /// How far apart the centres of the two boxes are: half of each box's room, the bar and the space either side of
    /// the bar.
    var centresApart: CGFloat { roomHeight + barHeight + 2 * Self.spacing }

    init(textSize: CGFloat, screen: CGSize) {
        let font = UIFont.systemFont(ofSize: textSize)
        let textWidth = Self.placeholders
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let boxHeight = font.lineHeight.rounded(.up) + 2 * Self.margin
        // Two points to spare, so that rounding never makes the text field shrink its placeholder to fit.
        let boxWidth = max(screen.width * 0.3, textWidth.rounded(.up) + 2 * Self.margin + 2)
        self.textSize = textSize
        boxSize = CGSize(width: min(boxWidth, screen.width - 32), height: boxHeight)
        roomHeight = max(screen.height * 0.04, boxHeight)
        barHeight = screen.height * 0.005
    }

    /// The size of body text, which the boxes had before they set a size, growing with a larger text size up to the
    /// app's usual maximum.
    static func textSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        ScaledFont.pointSize(17, maximum: ScaledFont.usualMaximum, for: dynamicTypeSize)
    }
}

/// The app sizes its text to fit the screen, which is right at the standard text size. With a larger text size, smaller
/// text grows the way the system's body text does, up to a maximum, so it stays readable without pushing buttons off
/// the screen. Text is never made smaller than `size`, and text that's already bigger than the maximum stays the same.
struct ScaledFont: ViewModifier {
    static let usualMaximum: CGFloat = 34

    let size: CGFloat
    let maximum: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(.system(size: Self.pointSize(size, maximum: maximum, for: dynamicTypeSize)))
    }

    static func pointSize(_ size: CGFloat, maximum: CGFloat, for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size, compatibleWith: traits)
        return max(size, min(scaled, maximum))
    }
}

struct LoadingView: View {
    @Binding var isLoading: Bool

    var body: some View {
        ZStack {
            Color.blue.opacity(0.8).edgesIgnoringSafeArea(.all)
            VStack {
                Text("Maths Quest")
                    .font(.system(size: UIScreen.main.bounds.width * 0.1))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isLoading = false
            }
        }
    }
}

struct NoInternetView: View {
    var body: some View {
        VStack {
            Text("No Internet Connection")
                .font(.title)
                .padding()
            Text("Please check your internet connection and try again.")
                .multilineTextAlignment(.center)
                .padding()
            Button(action: {
                UIApplication.shared.open(URL(string: "App-Prefs:root=WIFI")!)
            }) {
                Text("Go to Settings")
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.buttonBlue)
                    .cornerRadius(10)
            }
        }
    }
}

struct DrawingPadView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        // The pad is white in dark mode too, where PencilKit would otherwise draw the black ink as white.
        canvasView.overrideUserInterfaceStyle = .light
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = canvasView.drawing
    }
}

struct WorkingOutView: View {
    @Binding var canvasView: PKCanvasView
    /// The drawing pad's height. Volume and Probability make it shorter when a question wouldn't otherwise fit on the
    /// screen.
    var padHeight = WorkingOutView.usualPadHeight

    /// 30% of the screen's height.
    static var usualPadHeight: CGFloat {
        UIScreen.main.bounds.height * 0.3
    }

    var body: some View {
        VStack {
            DrawingPadView(canvasView: $canvasView)
                .frame(height: padHeight)
                .accessibilityLabel("Working-out pad")
                .accessibilityHint("Draw here to work out the answer. It isn't marked.")
                .background(Color.white)
                .cornerRadius(UIScreen.main.bounds.width * 0.02)
                .border(Color.gray, width: 1)
                .shadow(radius: 2)

            HStack {
                Button {
                    canvasView.drawing = PKDrawing()
                } label: {
                    padButtonLabel("Clear", colour: .buttonRed)
                }
                
                Button {
                    let strokes = canvasView.drawing.strokes
                    if !strokes.isEmpty {
                        let updatedStrokes = Array(strokes.dropLast())
                        canvasView.drawing = PKDrawing(strokes: updatedStrokes)
                    }
                } label: {
                    padButtonLabel("Undo", colour: .buttonBlue)
                }
            }
        }
        .padding(5)
    }

    /// The whole coloured box is the button, so it can all be tapped, and it's at least 44 points tall with its
    /// padding.
    private func padButtonLabel(_ title: String, colour: Color) -> some View {
        Text(title)
            .frame(
                width : UIScreen.main.bounds.width * 0.25,
                height : max(UIScreen.main.bounds.height * 0.05, 34)
            )
            .font(.system(size:UIScreen.main.bounds.width * 0.04))
            .fontWeight(.bold)
            .padding(5)
            .background(colour)
            .foregroundColor(.white)
            .cornerRadius(UIScreen.main.bounds.width * 0.02)
    }
}

/// One activity, in the order the year menus list them, three to a year.
enum Activity: String, CaseIterable, Hashable {
    case counting, addition, subtraction
    case multiplication, division, shapes
    case fractions, measurement, time
    case decimals, geometry, money
    case percentages, statistics, volume
    case algebra, probability, ratios

    /// The name on the year menu's button.
    var title: String { rawValue.capitalized }

    var year: Int { Activity.allCases.firstIndex(of: self)! / 3 + 1 }

    static func activities(inYear year: Int) -> [Activity] {
        allCases.filter { $0.year == year }
    }
}

/// A screen that can open on top of the main menu.
enum Screen: Hashable {
    case shop, feedback, information, removeAds, settings
    case year(Int)
    case activity(Activity)
}

/// Moves between screens. The main menu is always at the bottom of the stack and `path` is the screens on top of it,
/// so Home goes back to the original main menu rather than opening another copy of it on top.
@MainActor
final class AppNavigator: ObservableObject {
    @Published var path: [Screen] = []

    /// Opens `screen` on top of `source`, the screen whose button was tapped, or nil for the main menu. See
    /// `opening(_:from:in:)`.
    func open(_ screen: Screen, from source: Screen?) {
        path = Self.opening(screen, from: source, in: path)
    }

    /// Goes back to the main menu.
    func goHome() {
        path = []
    }

    /// Opens a screen from the sidebar, or the main menu for nil. It replaces whatever was open, so the sidebar can't
    /// build up a stack of screens.
    func show(_ screen: Screen?) {
        path = Self.showing(screen)
    }

    /// The path after a button on `source` opens `screen`. Nothing changes unless `source` is the screen on top, so a
    /// second tap that arrives after the first has already opened a screen, or a tap on two buttons at once, can't
    /// open a second screen.
    nonisolated static func opening(_ screen: Screen, from source: Screen?, in path: [Screen]) -> [Screen] {
        guard path.last == source, source != screen else { return path }
        return path + [screen]
    }

    nonisolated static func showing(_ screen: Screen?) -> [Screen] {
        screen.map { [$0] } ?? []
    }
}

extension EnvironmentValues {
    /// The screen a view is on, or nil on the main menu.
    @Entry var currentScreen: Screen? = nil
}

/// A button that opens another screen on top of this one.
struct ScreenButton<Label: View>: View {
    let screen: Screen
    let label: Label
    @EnvironmentObject private var navigator: AppNavigator
    @Environment(\.currentScreen) private var currentScreen

    init(to screen: Screen, @ViewBuilder label: () -> Label) {
        self.screen = screen
        self.label = label()
    }

    var body: some View {
        Button {
            navigator.open(screen, from: currentScreen)
        } label: {
            label
        }
    }
}

struct NavigationBar: View {
    @EnvironmentObject var gameData: GameData
    @EnvironmentObject private var navigator: AppNavigator
    @State var Back: Bool
    @State var Points: Bool
    @Binding var isSidebarOpen: Bool
    @Environment(\.colorScheme) private var colorScheme

    /// Grey, as before, but never too faint to read on the background colour the child has chosen.
    private var itemColour: Color {
        Color(Contrast.readableGrey(on: Contrast.background(
            hex: gameData.backgroundColourHex, opacity: gameData.backgroundOpacity, colorScheme: colorScheme)))
    }

    var body: some View {
        // At the largest text sizes "Points: 5,000" is too wide for the space between the buttons on an iPhone, and
        // wrapped onto two lines it ran into the screen's title. So the buttons give up their side margins first,
        // staying 44 points wide, and only if that still isn't enough do the points go on a line of their own.
        ViewThatFits(in: .horizontal) {
            HStack {
                leadingButton(compact: false)
                Spacer()
                pointsText
                Spacer()
                trailingButton(compact: false)
            }
            HStack(spacing: 0) {
                leadingButton(compact: true)
                Spacer(minLength: 4)
                pointsText
                Spacer(minLength: 4)
                trailingButton(compact: true)
            }
            VStack(spacing: 0) {
                HStack {
                    leadingButton(compact: false)
                    Spacer()
                    trailingButton(compact: false)
                }
                pointsText
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.clear)
        .padding(.top, 10)
    }

    private var pointsText: some View {
        Text(Points ? "Points: \(gameData.points)" : " ")
            .scaledFont(size: UIScreen.main.bounds.width * 0.05)
            .foregroundColor(Points ? itemColour : .clear)
            .fontWeight(.bold)
            .accessibilityHidden(!Points)
    }

    /// The space around a button's icon, which can be tapped too. When the points need the room it's narrower at the
    /// sides, but the button stays at least 44 points wide.
    private func margins(_ icon: some View, compact: Bool) -> some View {
        icon
            .padding(.vertical)
            .padding(.horizontal, compact ? 0 : nil)
            .frame(minWidth: compact ? 44 : nil)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func leadingButton(compact: Bool) -> some View {
        if Back {
            Button {
                navigator.goHome()
            } label: {
                margins(
                    Image(systemName: "house")
                        .resizable()
                        .frame(
                            width: UIScreen.main.bounds.width * 0.09,
                            height: UIScreen.main.bounds.width * 0.08
                        )
                        .foregroundColor(itemColour),
                    compact: compact)
            }
            .accessibilityLabel("Home")
            .accessibilityHint("Goes back to the main menu.")
            .accessibilityIdentifier("house")
        } else {
            Button(action: {
                hideKeyboard()
                withAnimation {
                    isSidebarOpen.toggle()
                }
            }) {
                margins(
                    Image(systemName: "line.horizontal.3")
                        .resizable()
                        .frame(
                            width: UIScreen.main.bounds.height * 0.04, height: UIScreen.main.bounds.height * 0.03
                        )
                        .foregroundColor(isSidebarOpen ? .clear : itemColour),
                    compact: compact)
            }
            // VoiceOver would otherwise read the symbol's own name, "Drag".
            .accessibilityLabel("Menu")
            .accessibilityHint("Opens the list of screens.")
            .accessibilityIdentifier("line.horizontal.3")
        }
    }

    @ViewBuilder
    private func trailingButton(compact: Bool) -> some View {
        if Back {
            ScreenButton(to: .settings) {
                margins(
                    Image(systemName: "gearshape")
                        .resizable()
                        .frame(
                            width: UIScreen.main.bounds.width * 0.09,
                            height: UIScreen.main.bounds.width * 0.09
                        )
                        .foregroundColor(itemColour),
                    compact: compact)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("gearshape")
        } else {
            margins(
                Image(systemName: "gearshape")
                    .resizable()
                    .frame(
                        width: UIScreen.main.bounds.width * 0.09,
                        height: UIScreen.main.bounds.height * 0.09
                    )
                    .foregroundColor(.clear),
                compact: compact)
                .disabled(true)
                .accessibilityHidden(true)
        }
    }
}

/// Marks the row with an activity's Enter and Skip buttons, so `QuestionLayout` can find it.
private enum QuestionSubmitRow: Hashable {
    case id
}

/// The screen layout every activity shares. The header (home, points and settings) has its own strip at the top
/// and the question is centred in the space below it, so a tall question or the "Correct!" message can't run into
/// the points or push the header off the screen. A question too tall for the space scrolls instead.
///
/// The keyboard takes space from the question rather than covering it. As the keyboard comes up, the question
/// scrolls so the row marked with `questionSubmitRow()` sits just above it. The answer box is above that row, so
/// the box and Enter both stay in view, and the player can tap Enter without hiding the keyboard first. The number
/// pad has no Return key, so this is the only way to submit while it's up.
///
/// A question with a tall picture or drawing pad can use `fitOnScreen` to make it shorter on a small screen, so the
/// answer box and Enter are in view with the keyboard down without scrolling.
///
/// The message after Enter makes the question taller for a moment. On a question that only just fits, that pushes the
/// row below the bottom of the space, so as the message comes in, the question scrolls to its end, where the row is.
/// That brings the row, and the message above it, back into view. The message goes in straight away, and only its
/// fade is animated (`AnyTransition.answerFeedback`). If the rest of the question slid down to make room for it, the
/// scroll view's content would grow a little at a time, and a scroll can't go past the end of the content as it is
/// when the scroll starts, so the question wouldn't move. The message goes out with the question sliding back, which
/// only makes it shorter.
struct QuestionLayout<Content: View>: View {
    @Binding var isSidebarOpen: Bool
    let content: Content
    @State private var roomWithoutKeyboard: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(Back: true, Points: true, isSidebarOpen: $isSidebarOpen)
                .frame(maxWidth: .infinity)
                .edgesIgnoringSafeArea(.top)
                .padding(.top, UIScreen.main.bounds.height * 0.002)

            GeometryReader { space in
                ScrollViewReader { scroller in
                    ScrollView {
                        content
                            .environment(\.questionRoom, roomWithoutKeyboard)
                            .frame(maxWidth: .infinity, minHeight: space.size.height)
                            // The scroll view covers the activity's background, which hides the keyboard when
                            // tapped, so the space around the question does the same. It's behind the question,
                            // so the buttons and answer boxes keep their own taps.
                            .background {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture { hideKeyboard() }
                            }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                    .modifier(RevealSubmitRowByScrolling(scroller: scroller))
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        withAnimation(reduceMotion ? nil : .default) {
                            scroller.scrollTo(QuestionSubmitRow.id, anchor: .bottom)
                        }
                    }
                }
            }
            // The keyboard makes the space shorter, but `fitOnScreen` sizes the question for the space without it,
            // so the question doesn't change size as the keyboard comes and goes.
            // It's measured inside `ignoresSafeArea`, where the space reaches down behind the keyboard.
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { roomWithoutKeyboard = $0 }
                    .ignoresSafeArea(.keyboard)
            }
        }
    }
}

/// The message after Enter, such as "Correct!" in green or "Incorrect. Try Again!" in red. The words say whether the
/// answer was right, so the colour isn't the only sign. The black outline keeps it readable on any background colour.
///
/// VoiceOver's focus stays on Enter, so it wouldn't notice the message appear. It reads the message out instead, once,
/// rather than once for every copy of the text that makes up the outline.
///
/// The message goes just above Enter, so on a question that only just fits it can push Enter and Skip below the bottom
/// of the screen. As it appears, it scrolls them back into view. See `QuestionLayout`.
struct AnswerFeedbackText: View {
    let message: String
    var outlined = true
    @Environment(\.revealSubmitRow) private var revealSubmitRow

    var body: some View {
        ZStack {
            if outlined {
                ForEach([-2, -1, 0, 1, 2], id: \.self) { xOffset in
                    ForEach([-2, -1, 0, 1, 2], id: \.self) { yOffset in
                        Text(message)
                            .foregroundColor(.black)
                            .font(.system(size: UIScreen.main.bounds.width * 0.075))
                            .fontWeight(.bold)
                            .offset(x: CGFloat(xOffset), y: CGFloat(yOffset))
                    }
                }
                .accessibilityHidden(true)
            }

            Text(message)
                .foregroundColor(message == "Correct!" ? .green : .red)
                .font(.system(size: UIScreen.main.bounds.width * 0.075))
                .fontWeight(.bold)
        }
        .onAppear {
            announce(message)
            revealSubmitRow()
        }
        .onChange(of: message) { _, newMessage in announce(newMessage) }
    }
}

extension AnyTransition {
    /// How the message after Enter comes and goes. The activities show it without animation, so it brings its own
    /// fade. See `QuestionLayout`.
    static var answerFeedback: AnyTransition {
        .opacity.animation(.default)
    }
}

/// Scrolls the row with Enter and Skip, and the message just above it, into view. `QuestionLayout` sets it; anywhere
/// else it does nothing.
struct RevealSubmitRow {
    let action: () -> Void

    func callAsFunction() {
        action()
    }
}

/// Sets `revealSubmitRow` for the question in `QuestionLayout`'s scroll view. From iOS 18 it scrolls to the end of the
/// question. iOS 17 can only scroll to a view, so there it scrolls the row to the bottom of the space instead, once the
/// question has been laid out again with the message in it. See `QuestionLayout`.
private struct RevealSubmitRowByScrolling: ViewModifier {
    let scroller: ScrollViewProxy

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(ScrollToTheEnd())
        } else {
            content.environment(\.revealSubmitRow, RevealSubmitRow {
                DispatchQueue.main.async {
                    scroller.scrollTo(QuestionSubmitRow.id, anchor: .bottom)
                }
            })
        }
    }
}

/// See `RevealSubmitRowByScrolling`.
@available(iOS 18.0, *)
private struct ScrollToTheEnd: ViewModifier {
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .environment(\.revealSubmitRow, RevealSubmitRow {
                position.scrollTo(edge: .bottom)
            })
    }
}

/// Has VoiceOver read out `message` straight away, for a message that appears somewhere other than where its focus is.
func announce(_ message: String) {
    guard !message.isEmpty else { return }
    var announcement = AttributedString(message)
    announcement.accessibilitySpeechAnnouncementPriority = .high
    AccessibilityNotification.Announcement(announcement).post()
}

/// Words for VoiceOver where it can't be relied on to read the maths as written: it can skip the "-" in "7 - 3", read
/// a ratio such as "6 : 12" as a time, skip brackets, and read "²/₄" as symbols. "×" is said as "times", as in class.
/// The words say the same maths, and never the answer.
enum SpokenMaths {
    /// Read in place of a gap such as "_" or "___".
    static let missingNumber = "missing number"

    private static let fractionNames: [Int: (one: String, many: String)] = [
        2: ("half", "halves"), 3: ("third", "thirds"), 4: ("quarter", "quarters"), 5: ("fifth", "fifths"),
        6: ("sixth", "sixths"), 7: ("seventh", "sevenths"), 8: ("eighth", "eighths"), 9: ("ninth", "ninths"),
        10: ("tenth", "tenths"), 12: ("twelfth", "twelfths"),
    ]

    /// "2 quarters" for 2/4 and "1 half" for 1/2, as fractions are said in class, or "5 over 11" for a denominator
    /// that isn't named here.
    static func fraction(numerator: Int, denominator: Int) -> String {
        guard let name = fractionNames[denominator] else { return "\(numerator) over \(denominator)" }
        return "\(numerator) \(numerator == 1 ? name.one : name.many)"
    }

    /// A fraction written "1/2" or "²/₄", read as `fraction(numerator:denominator:)` reads it. Nil if `written`
    /// isn't a fraction.
    static func fraction(_ written: String) -> String? {
        let digits = Array("0123456789")
        let superscripts = Array("⁰¹²³⁴⁵⁶⁷⁸⁹")
        let subscripts = Array("₀₁₂₃₄₅₆₇₈₉")
        let plain = String(written.map { character in
            if let index = superscripts.firstIndex(of: character) ?? subscripts.firstIndex(of: character) {
                return digits[index]
            }
            return character
        })
        let parts = plain.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let numerator = Int(parts[0]), let denominator = Int(parts[1]) else { return nil }
        return fraction(numerator: numerator, denominator: denominator)
    }

    /// "6 to 12" for the ratio 6:12.
    static func ratio(_ first: String, _ second: String) -> String {
        "\(first) to \(second)"
    }
}

extension EnvironmentValues {
    /// The height `QuestionLayout` has for the question with the keyboard down, or 0 before it's been measured.
    @Entry var questionRoom: CGFloat = 0
    @Entry var revealSubmitRow = RevealSubmitRow(action: {})
}

/// See `fitOnScreen(by:usual:minimum:paused:)`.
private struct FitOnScreen: ViewModifier {
    @Binding var height: CGFloat
    let usual: CGFloat
    let minimum: CGFloat
    let paused: Bool
    @Environment(\.questionRoom) private var room
    @State private var questionHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newHeight in
                questionHeight = newHeight
                fit()
            }
            .onChange(of: room) {
                fit()
            }
    }

    private func fit() {
        guard !paused, room > 0, questionHeight > 0 else { return }
        let spare = room - questionHeight
        // Heights are whole points and only grow back for a couple of points or more, so rounding can't make the
        // question flicker between two sizes.
        guard spare < 0 || (spare >= 2 && height < usual) else { return }
        let fitted = (height + spare).rounded(.down)
        let newHeight = fitted >= minimum ? min(usual, fitted) : usual
        if newHeight != height {
            height = newHeight
        }
    }
}

extension View {
    /// Puts an activity's question below the shared header. See `QuestionLayout`.
    func questionLayout(isSidebarOpen: Binding<Bool>) -> some View {
        QuestionLayout(isSidebarOpen: isSidebarOpen, content: self)
    }

    /// Marks the row with Enter and Skip, which `QuestionLayout` keeps above the keyboard.
    func questionSubmitRow() -> some View {
        id(QuestionSubmitRow.id)
    }

    /// Fits a question on the screen with the keyboard down by making one tall part of it, such as a picture or the
    /// drawing pad, shorter. `height` is that part's height. While the question is too tall, `height` shrinks by
    /// just enough for it to fit, and once there's room again it grows back to `usual`. If fitting would take it
    /// below `minimum`, it stays at `usual` and the question scrolls instead. Nothing changes while `paused`, such
    /// as while the "Correct!" message makes the question taller for a moment.
    func fitOnScreen(by height: Binding<CGFloat>, usual: CGFloat, minimum: CGFloat, paused: Bool) -> some View {
        modifier(FitOnScreen(height: height, usual: usual, minimum: minimum, paused: paused))
    }
}

/// The sidebar menu over a top-level screen. While it's open the screen behind it can't be used, and VoiceOver reads
/// only the menu.
private struct SidebarOverlay: ViewModifier {
    @Binding var isOpen: Bool
    let selectedTab: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isOpen)
                .accessibilityHidden(isOpen)

            if isOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { isOpen = false }
                    }
                    .accessibilityHidden(true)

                SidebarView(isSidebarOpen: $isOpen, selectedTab: selectedTab)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    .zIndex(2)
            }
        }
    }
}

extension View {
    /// Adds the sidebar menu, which opens from the menu button. `selectedTab` is this screen's entry in it.
    func sidebarOverlay(isOpen: Binding<Bool>, selectedTab: String) -> some View {
        modifier(SidebarOverlay(isOpen: isOpen, selectedTab: selectedTab))
    }
}

struct SidebarView: View {
    @Binding var isSidebarOpen: Bool
    @State var selectedTab: String
    @AccessibilityFocusState private var isCloseButtonFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable()
                            .frame(
                                width: UIScreen.main.bounds.width * 0.07,
                                height: UIScreen.main.bounds.width * 0.07
                            )
                            .foregroundColor(.black)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .padding(.top, 8)
                    .padding(.leading, 20)
                    .accessibilityLabel("Close menu")
                    .accessibilityIdentifier("xmark.circle.fill")
                    .accessibilityFocused($isCloseButtonFocused)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }

                // The entries scroll if they don't fit, such as with a large text size on a small phone.
                GeometryReader { space in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            SidebarButton(icon: "house.fill", title: "Main Menu", screen: nil, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            SidebarButton(icon: "cart", title: "Shop", screen: .shop, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            SidebarButton(icon: "bubble.left.and.bubble.right", title: "Feedback", screen: .feedback, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            SidebarButton(icon: "info.circle", title: "Information", screen: .information, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            ForEach(1...6, id: \.self) { year in
                                SidebarButton(icon: "\(year).square.fill", title: "Year \(year)", screen: .year(year), selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            }

                            Spacer(minLength: 20)

                            SidebarButton(icon: "nosign", title: "Remove Ads", screen: .removeAds, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                            SidebarButton(icon: "gear", title: "Settings", screen: .settings, selectedTab: $selectedTab, isSidebarOpen: $isSidebarOpen)
                        }
                        .padding()
                        .frame(minHeight: space.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(width: UIScreen.main.bounds.width / 2)
            // The white reaches under the status bar and home indicator, but the buttons stay clear of them.
            .background(Color.white.ignoresSafeArea())
            .shadow(radius: 5)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, close)

            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
        }
        .onAppear {
            isCloseButtonFocused = true
        }
    }

    private func close() {
        withAnimation {
            isSidebarOpen = false
        }
    }
}

struct SidebarButton: View {
    var icon: String
    var title: String
    /// The screen this opens, or nil for the main menu.
    var screen: Screen?
    @Binding var selectedTab: String
    @Binding var isSidebarOpen: Bool
    @EnvironmentObject private var navigator: AppNavigator

    var body: some View {
        Button {
            isSidebarOpen = false
            navigator.show(screen)
        } label: {
            HStack {
                Image(systemName: icon)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.04, maximum: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.04, maximum: 28)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .fontWeight(.bold)
            .background(selectedTab == title ? Color.blue.opacity(0.2) : Color.clear)
            .cornerRadius(UIScreen.main.bounds.width * 0.02)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selectedTab == title ? .isSelected : [])
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            (r, g, b) = (
                Double((int >> 16) & 0xFF) / 255,
                Double((int >> 8) & 0xFF) / 255,
                Double(int & 0xFF) / 255
            )
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: r, green: g, blue: b)
    }

    init(_ colour: Contrast.RGB) {
        self.init(red: colour.red, green: colour.green, blue: colour.blue)
    }
}

/// Contrast as WCAG measures it, used to pick colours that can be read on the background colour the child has chosen.
/// Small text needs 4.5:1 and large text and icons 3:1.
enum Contrast {
    struct RGB: Equatable {
        var red, green, blue: Double
    }

    static let black = RGB(red: 0, green: 0, blue: 0)
    static let white = RGB(red: 1, green: 1, blue: 1)
    /// SwiftUI's `.gray`, which is the same in light and dark mode.
    static let systemGrey = RGB(red: 142 / 255, green: 142 / 255, blue: 147 / 255)

    /// Read the same way as `Color(hex:)`.
    static func rgb(hex: String) -> RGB {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        guard hex.count == 6 else { return black }
        return RGB(red: Double((int >> 16) & 0xFF) / 255, green: Double((int >> 8) & 0xFF) / 255, blue: Double(int & 0xFF) / 255)
    }

    /// `colour` drawn at `opacity` on top of `background`.
    static func composite(_ colour: RGB, opacity: Double, over background: RGB) -> RGB {
        mix(background, colour, opacity)
    }

    static func luminance(_ colour: RGB) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(colour.red) + 0.7152 * linear(colour.green) + 0.0722 * linear(colour.blue)
    }

    static func ratio(_ first: RGB, _ second: RGB) -> Double {
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// The colour a screen shows behind its content: the chosen colour at its strength, on the system's white, or
    /// black in dark mode.
    static func background(hex: String, opacity: Double, colorScheme: ColorScheme) -> RGB {
        composite(rgb(hex: hex), opacity: opacity, over: colorScheme == .dark ? black : white)
    }

    /// The navigation bar's grey where it can be read, otherwise the nearest colour to it that can: the grey made
    /// lighter or darker, whichever the background needs.
    static func readableGrey(on background: RGB, minimum: Double = 4.5) -> RGB {
        readable(systemGrey, on: background, minimum: minimum)
    }

    /// `colour` where it can be read on `background`, otherwise the nearest colour to it that can: `colour` made
    /// lighter or darker, whichever the background needs, so it keeps its hue.
    static func readable(_ colour: RGB, on background: RGB, minimum: Double = 4.5) -> RGB {
        let toward = blackOrWhiteReadingBetter(on: background)
        // A little to spare, so rounding when the colour is drawn can't take it under the minimum.
        for step in 0...100 {
            let shaded = mix(colour, toward, Double(step) / 100)
            if ratio(shaded, background) >= minimum + 0.05 { return shaded }
        }
        return toward
    }

    /// `preferred` where it can be read on `background`, otherwise black or white, whichever reads better. One of the
    /// two always reaches 4.5:1, because their two contrasts with any colour multiply to 21.
    static func preferring(_ preferred: RGB, on background: RGB, minimum: Double = 4.5) -> RGB {
        ratio(preferred, background) >= minimum + 0.05 ? preferred : blackOrWhiteReadingBetter(on: background)
    }

    /// Black or white, whichever has the higher contrast with every one of `surfaces`, for something such as a label
    /// that crosses more than one.
    static func blackOrWhiteReadingBetter(on surfaces: [RGB]) -> RGB {
        let onWhite = surfaces.map { ratio(white, $0) }.min() ?? 21
        let onBlack = surfaces.map { ratio(black, $0) }.min() ?? 21
        return onBlack > onWhite ? black : white
    }

    static func blackOrWhiteReadingBetter(on background: RGB) -> RGB {
        blackOrWhiteReadingBetter(on: [background])
    }

    /// The lowest contrast `colour` has with any of `surfaces`.
    static func lowestRatio(_ colour: RGB, on surfaces: [RGB]) -> Double {
        surfaces.map { ratio(colour, $0) }.min() ?? 21
    }

    /// Black, as the shop has always drawn it, unless the background is too dark for black to be read.
    static func blackOrWhite(on background: RGB, minimum: Double = 4.5) -> RGB {
        ratio(black, background) >= minimum ? black : white
    }

    private static func mix(_ from: RGB, _ to: RGB, _ amount: Double) -> RGB {
        RGB(red: from.red + (to.red - from.red) * amount,
            green: from.green + (to.green - from.green) * amount,
            blue: from.blue + (to.blue - from.blue) * amount)
    }

    /// A system colour, which SwiftUI draws a little differently in dark mode.
    struct SystemColour: Equatable {
        let light: RGB
        let dark: RGB

        func rgb(in colorScheme: ColorScheme) -> RGB {
            colorScheme == .dark ? dark : light
        }
    }

    static let systemBlue = SystemColour(light: RGB(bytes: 0, 122, 255), dark: RGB(bytes: 10, 132, 255))
    static let systemRed = SystemColour(light: RGB(bytes: 255, 59, 48), dark: RGB(bytes: 255, 69, 58))
    static let systemGreen = SystemColour(light: RGB(bytes: 52, 199, 89), dark: RGB(bytes: 48, 209, 88))
    static let fixedWhite = SystemColour(light: white, dark: white)
    static let fixedBlack = SystemColour(light: black, dark: black)

    /// A button's box colour, darkened just enough for its white words to be read (4.5:1). The box is the same in
    /// light and dark mode, so the words can be read in both.
    static func boxForWhiteWords(_ colour: RGB) -> RGB {
        readable(colour, on: white)
    }
}

extension Contrast.RGB {
    /// From 0–255 values, as colours are usually written.
    init(bytes red: Int, _ green: Int, _ blue: Int) {
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

extension Color {
    /// Button boxes with white words on them: the system's blue, red, green and grey, darkened just enough for the
    /// words to be read. SwiftUI's own blue, red, green and grey are too light for white words, more so in dark mode.
    static let buttonBlue = Color(Contrast.boxForWhiteWords(Contrast.systemBlue.light))
    static let buttonRed = Color(Contrast.boxForWhiteWords(Contrast.systemRed.light))
    static let buttonGreen = Color(Contrast.boxForWhiteWords(Contrast.systemGreen.light))
    static let buttonGrey = Color(Contrast.boxForWhiteWords(Contrast.systemGrey))

    /// The hint in an empty white answer box, such as "Hours": the system's grey, darkened just enough to be read on
    /// white. The system's own placeholder grey is too pale to read there, and nearly white in dark mode.
    static let placeholderGrey = Color(Contrast.readableGrey(on: Contrast.white))
}

extension TextField where Label == Text {
    /// A text field in a white answer box. Its hint, such as "Answer" or "Hours", is drawn in `placeholderGrey`, so it
    /// can be read in light and dark mode. The title is still what VoiceOver reads.
    init(answerBox titleKey: LocalizedStringKey, text: Binding<String>) {
        self.init(titleKey, text: text, prompt: Text(titleKey).foregroundColor(.placeholderGrey))
    }
}

/// The background colour the child has chosen in the shop, at its strength. Every screen draws it over the system's
/// background, which is white, or black in dark mode, so the colour that's actually seen depends on both.
struct ChosenBackground: Equatable {
    var hex = GameSettings.defaultColourHex
    var opacity = GameSettings.defaultOpacity

    func rgb(in colorScheme: ColorScheme) -> Contrast.RGB {
        Contrast.background(hex: hex, opacity: opacity, colorScheme: colorScheme)
    }
}

private struct ChosenBackgroundKey: EnvironmentKey {
    static let defaultValue = ChosenBackground()
}

extension EnvironmentValues {
    /// Set by ContentView from GameData, so colours drawn on the background can be worked out from it.
    var chosenBackground: ChosenBackground {
        get { self[ChosenBackgroundKey.self] }
        set { self[ChosenBackgroundKey.self] = newValue }
    }
}

/// A colour for something drawn straight on the chosen background, worked out from that background as it's seen, in
/// light or dark mode. Use it wherever a colour would otherwise be fixed, as in `.foregroundStyle(.onBackground)`.
struct ReadableOnBackground: ShapeStyle {
    enum Rule: Equatable {
        /// The colour where it can be read, otherwise black or white, whichever reads better.
        case preferring
        /// The colour made darker or lighter until it can be read, so it keeps its hue.
        case shading
        /// Nothing where the colour itself stands out from the background, otherwise black or white, whichever reads
        /// better: an outline round a shape filled with the colour, drawn only when it's needed.
        case outlining
    }

    var colour: Contrast.SystemColour
    var minimum: Double
    var rule: Rule

    func resolve(in environment: EnvironmentValues) -> Color {
        guard let rgb = rgb(on: environment.chosenBackground, colorScheme: environment.colorScheme) else { return .clear }
        return Color(rgb)
    }

    /// The colour drawn, or nil for nothing.
    func rgb(on chosen: ChosenBackground, colorScheme: ColorScheme) -> Contrast.RGB? {
        let background = chosen.rgb(in: colorScheme)
        let colour = colour.rgb(in: colorScheme)
        switch rule {
        case .preferring:
            return Contrast.preferring(colour, on: background, minimum: minimum)
        case .shading:
            return Contrast.readable(colour, on: background, minimum: minimum)
        case .outlining:
            guard Contrast.ratio(colour, background) < minimum + 0.05 else { return nil }
            return Contrast.blackOrWhiteReadingBetter(on: background)
        }
    }
}

extension ShapeStyle where Self == ReadableOnBackground {
    /// Words, shapes and lines that have always been white on the background: white unless the background is too
    /// light for it, then black. 4.5:1, as small words need.
    static var onBackground: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.fixedWhite, minimum: 4.5, rule: .preferring)
    }

    /// Diagrams that have always been black: black unless the background is too dark for it, then white. 3:1, as a
    /// drawing's lines need.
    static var linesOnBackground: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.fixedBlack, minimum: 3, rule: .preferring)
    }

    /// A large green message, such as "Name Saved": green, made darker or lighter if the background needs it.
    static var largeGreenOnBackground: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.systemGreen, minimum: 3, rule: .shading)
    }

    /// A large red message, such as "No internet connection!".
    static var largeRedOnBackground: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.systemRed, minimum: 3, rule: .shading)
    }

    /// A green message in small words, such as "Ads removed! Thank you.", which need 4.5:1.
    static var greenOnBackground: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.systemGreen, minimum: 4.5, rule: .shading)
    }

    /// An outline for the red bar in Measurement, on a background too close to red for the bar to stand out.
    static var redBarOutline: ReadableOnBackground {
        ReadableOnBackground(colour: Contrast.systemRed, minimum: 3, rule: .outlining)
    }
}

/// Lets a system control that draws its own words, such as a wheel picker, read on the chosen background: it's drawn
/// as in dark mode, with white words, or light mode, with black, whichever the background needs.
struct ColorSchemeForBackground: ViewModifier {
    @Environment(\.chosenBackground) private var chosenBackground
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, Self.scheme(for: chosenBackground, in: colorScheme))
    }

    static func scheme(for chosen: ChosenBackground, in colorScheme: ColorScheme) -> ColorScheme {
        Contrast.blackOrWhiteReadingBetter(on: chosen.rgb(in: colorScheme)) == Contrast.white ? .dark : .light
    }
}

extension View {
    /// See `ColorSchemeForBackground`.
    func colorSchemeForBackground() -> some View {
        modifier(ColorSchemeForBackground())
    }

    /// Something always drawn on white, such as an answer box or a clock face, looks the same in dark mode, so the
    /// system's dark-mode colours for its words, placeholder and drawing don't end up white on white.
    func drawnOnWhite() -> some View {
        environment(\.colorScheme, .light)
    }
}

struct ShopOpacity: Identifiable {
    let id = UUID()
    let opacity: Double
    let price: Int
}

struct ShopColour: Identifiable {
    let id = UUID()
    let name: String
    let hexCode: String
    let opacities: [ShopOpacity]
}

let colours: [ShopColour] = [
    ShopColour(name: "Red", hexCode: "#FF0000", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Green", hexCode: "#00FF00", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Blue", hexCode: "#0000FF", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 0), // Free on purpose: Blue 80% is the colour every player starts with.
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Everglow", hexCode: "#FFD700", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Magenta", hexCode: "#FF00FF", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Cyan", hexCode: "#00FFFF", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Orange", hexCode: "#FFA500", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Purple", hexCode: "#800080", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Turquoise", hexCode: "#00CED1", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Pink", hexCode: "#FF1493", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Indigo", hexCode: "#4B0082", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Amber", hexCode: "#FF7E00", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Teal", hexCode: "#008080", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Violet", hexCode: "#9400D3", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ]),
    ShopColour(name: "Crimson", hexCode: "#DC143C", opacities: [
        ShopOpacity(opacity: 0.7, price: 25),
        ShopOpacity(opacity: 0.8, price: 50),
        ShopOpacity(opacity: 0.9, price: 75),
        ShopOpacity(opacity: 1.0, price: 100)
    ])
]

struct ShopView: View {
    @State private var isSidebarOpen = false
    @State private var pointsTakenString = ""
    @State private var showMessagePoints = false
    @State private var showMessageColour = false
    @EnvironmentObject var gameData: GameData
    @State private var colourMessage = ""
    @State private var pointsMessage = ""
    @State private var showAlert = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundView
                
                VStack {
                    NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                        .frame(maxWidth: .infinity)
                        .edgesIgnoringSafeArea(.top)
                        .padding(.top, UIScreen.main.bounds.height * 0.002)
                    
                    Spacer()
                }
                
                VStack {
                    Spacer()
                    
                    spendPointsSection
                    
                    Text("Background Colours")
                        .font(.system(size: geometry.size.width * 0.06))
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .accessibilityAddTraits(.isHeader)
                    
                    ScrollView {
                        VStack(spacing: geometry.size.height * 0.015) {
                            ForEach(colours) { colour in
                                HStack(spacing: geometry.size.width * 0.02) {
                                    ForEach(colour.opacities) { opacityOption in
                                        colourOptionView(colour: colour, opacityOption: opacityOption, geometry: geometry)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, geometry.size.width * 0.03)
                    }
                    .frame(height: geometry.size.height * 0.5)
                    
                    Spacer()
                }
                
                if showMessageColour {
                    Text(colourMessage)
                        .foregroundColor(messageColour)
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .multilineTextAlignment(.center)
                        .fontWeight(.bold)
                        .padding()
                        .cornerRadius(10)
                        .onAppear { announce(colourMessage) }
                }
                
                if showMessagePoints {
                    Text(pointsMessage)
                        .foregroundColor(messageColour)
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding()
                        .cornerRadius(10)
                        .onAppear { announce(pointsMessage) }
                }
            }
            .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Shop")
            .navigationBarBackButtonHidden(true)
        }
    }
    
    /// The messages are large text, so they need 3:1. They stay black unless the background is too dark for it.
    private var messageColour: Color {
        Color(Contrast.blackOrWhite(on: Contrast.background(
            hex: gameData.backgroundColourHex, opacity: gameData.backgroundOpacity, colorScheme: colorScheme), minimum: 3))
    }
    
    private var backgroundView: some View {
        Color(hex: gameData.backgroundColourHex)
            .opacity(gameData.backgroundOpacity)
            .ignoresSafeArea()
    }
    
    private var spendPointsSection: some View {
        VStack(spacing: 10) {
            Text("Spend Points")
                .font(.system(size: UIScreen.main.bounds.width * 0.06))
                .fontWeight(.bold)
                .foregroundStyle(.onBackground)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityAddTraits(.isHeader)
            
            HStack(spacing: UIScreen.main.bounds.width * 0.03) {
                TextField(answerBox: "Points to spend", text: $pointsTakenString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .drawnOnWhite()
                    .frame(width: UIScreen.main.bounds.width * 0.3)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.04)
                    .answerKeyboard(.numberPad)
                    .accessibilityHint("Points you spend here are taken away.")
                
                Button(action: {
                    hideKeyboard()
                    handlePointsTransaction()
                }) {
                    Text("Enter")
                        .scaledFont(size: UIScreen.main.bounds.width * 0.04)
                        .padding(UIScreen.main.bounds.width * 0.02)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        // The white box is small, so the space around it can be tapped too.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
    
    private func colourOptionView(colour: ShopColour, opacityOption: ShopOpacity, geometry: GeometryProxy) -> some View {
        let isUnlocked = gameData.isColourUnlocked(colour.hexCode, opacity: opacityOption.opacity)
        let isSelected = gameData.isColourSelected(colour.hexCode, opacity: opacityOption.opacity)
        let swatch = Self.swatchColour(colour, opacityOption, on: Contrast.background(
            hex: gameData.backgroundColourHex, opacity: gameData.backgroundOpacity, colorScheme: colorScheme))
        
        return Button(action: {
            if isUnlocked {
                selectColour(colour: colour, opacityOption: opacityOption)
            } else {
                purchaseColour(colour: colour, opacityOption: opacityOption)
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.02)
                    .fill(Color(hex: colour.hexCode).opacity(opacityOption.opacity))
                    .frame(width: geometry.size.width * 0.12, height: geometry.size.width * 0.12)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(Contrast.blackOrWhite(on: swatch, minimum: 3)))
                                .font(.title)
                        } else if isUnlocked {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(Color(Contrast.readableGrey(on: swatch, minimum: 3)))
                                .font(.title2)
                        }
                    }
                
                if !isUnlocked {
                    Text(Self.priceText(opacityOption.price))
                        .font(.system(size: geometry.size.width * 0.03))
                        .fontWeight(.bold)
                        .foregroundColor(Color(Self.priceColour(on: swatch)))
                }
            }
        }
        .accessibilityLabel(Self.accessibilityName(of: colour, opacityOption))
        .accessibilityValue(isSelected ? "Selected" : isUnlocked ? "Unlocked" : Self.lockedDescription(price: opacityOption.price))
        .accessibilityHint(isSelected ? "" : isUnlocked ? "Makes this the background colour." : "Unlocks this colour.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The swatch as it is seen: its colour at its strength, on the shop's own background.
    static func swatchColour(_ colour: ShopColour, _ opacityOption: ShopOpacity, on background: Contrast.RGB) -> Contrast.RGB {
        Contrast.composite(Contrast.rgb(hex: colour.hexCode), opacity: opacityOption.opacity, over: background)
    }

    /// A locked swatch's price, as shown on it. Blue 80% costs 0 points, which reads better as "Free". Every player
    /// starts with it unlocked, so in practice it never shows a price, but a free colour should never say "0".
    static func priceText(_ price: Int) -> String {
        price == 0 ? "Free" : "\(price)"
    }

    /// What VoiceOver says about a locked swatch.
    static func lockedDescription(price: Int) -> String {
        price == 0 ? "Locked, free" : "Locked, \(price) points"
    }

    /// Prices are small text, so they need 4.5:1. They stay black unless the swatch is too dark, as Purple, Indigo,
    /// Violet, Blue and Teal can be.
    static func priceColour(on swatch: Contrast.RGB) -> Contrast.RGB {
        Contrast.blackOrWhite(on: swatch, minimum: 4.5)
    }

    /// What VoiceOver calls a colour in the shop, such as "Red, 70 percent". Each colour comes in four strengths, so
    /// the name alone doesn't say which button it is.
    static func accessibilityName(of colour: ShopColour, _ opacityOption: ShopOpacity) -> String {
        "\(colour.name), \(Int((opacityOption.opacity * 100).rounded())) percent"
    }
    
    private func handlePointsTransaction() {
        guard let pointsTaken = Int(pointsTakenString), pointsTaken > 0 else {
            showMessagePoints = true
            pointsMessage = "Please enter a valid number of points."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showMessagePoints = false
            }
            return
        }
        
        if pointsTaken > gameData.points {
            showMessagePoints = true
            pointsMessage = "Not enough points."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showMessagePoints = false
            }
            return
        }
        
        gameData.spendPoints(pointsTaken)
        showMessagePoints = true
        pointsMessage = "\(pointsTaken) \(pointsTaken == 1 ? "point" : "points") taken."
        pointsTakenString = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showMessagePoints = false
        }
    }
    
    private func selectColour(colour: ShopColour, opacityOption: ShopOpacity) {
        gameData.selectColour(hex: colour.hexCode, opacity: opacityOption.opacity)
    }
    
    private func purchaseColour(colour: ShopColour, opacityOption: ShopOpacity) {
        switch gameData.purchaseColour(hex: colour.hexCode, opacity: opacityOption.opacity, price: opacityOption.price) {
        case .purchased:
            colourMessage = "\(colour.name) unlocked!"
        case .alreadyUnlocked:
            // A second tap before the screen redrew: it is already paid for, so it is just selected.
            selectColour(colour: colour, opacityOption: opacityOption)
            return
        case .notEnoughPoints, .invalidPrice:
            colourMessage = "Not enough points!"
        }
        showMessageColour = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showMessageColour = false
        }
    }
}

struct FeedbackView: View {
    static let privacyReminder = "Please don't write your name, school, address or anything else about you."

    @State private var feedbackText: String = ""
    @State private var showMessage = false
    @State private var isSidebarOpen: Bool = false
    @State private var isOffline = false
    @State private var navigationBarBottom: CGFloat = 0
    @EnvironmentObject var gameData: GameData
    
    private let db = Firestore.firestore()
    
    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            VStack {
                NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { navigationBarBottom = $0 }
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            
            VStack {
                Spacer(minLength: 0)

                // Given its room before the box, as before. If it can't all fit above the smallest box and Enter, as
                // at the largest text sizes with the keyboard up on a small iPhone, it scrolls instead of pushing
                // Enter down under the keyboard.
                ViewThatFits(in: .vertical) {
                    heading
                    ScrollView {
                        heading
                    }
                }
                .layoutPriority(2)

                ZStack(alignment: .topLeading) {
                    // A square box, which gets shorter when the keyboard comes up so Enter stays above it.
                    TextEditor(text: $feedbackText)
                        .frame(width: UIScreen.main.bounds.width * 0.75)
                        .frame(minHeight: 50, maxHeight: UIScreen.main.bounds.width * 0.75)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .font(.system(size: UIScreen.main.bounds.width * 0.075))
                        .accessibilityLabel("Your feedback")
                }
                .layoutPriority(1)
                
                if showMessage {
                    Text(isOffline ? "No internet connection!" : "Feedback submitted!")
                        .foregroundStyle(isOffline ? .largeRedOnBackground : .largeGreenOnBackground)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .fontWeight(.bold)
                        .padding()
                        .transition(.opacity)
                        .onAppear { announce(isOffline ? "No internet connection!" : "Feedback submitted!") }
                }
                
                Button {
                    hideKeyboard()
                    checkInternetConnection {
                        if isOffline {
                            showMessage = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showMessage = false
                            }
                        } else {
                            submitFeedback()
                        }
                    }
                } label: {
                    Text("Enter")
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.015)
                        // The white box is only as tall as the word, so the space around it can be tapped too.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundColor(.black)
                .font(.system(size: UIScreen.main.bounds.width * 0.075))
                .multilineTextAlignment(.center)
                .fontWeight(.bold)
            }
            // Below the navigation bar, so the title can't be pushed up over it when the keyboard is up. The bar reaches
            // up behind the status bar, so this starts from the top of the screen too. The gap at the bottom keeps Enter
            // off the edge of the keyboard.
            .padding(.top, navigationBarBottom)
            .padding(.bottom, 12)
            .ignoresSafeArea(.container, edges: .top)
            
            Spacer()
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Feedback")
        .navigationBarBackButtonHidden(true)
    }

    private var heading: some View {
        VStack {
            Text("Feedback")
                .font(.system(size: UIScreen.main.bounds.width * 0.08))
                .fontWeight(.bold)
                .foregroundStyle(.onBackground)
                .padding()
                .underline()
                .accessibilityAddTraits(.isHeader)

            // Feedback is stored without any name or ID, so ask children not to type personal details into it.
            Text(FeedbackView.privacyReminder)
                .scaledFont(size: UIScreen.main.bounds.width * 0.04, maximum: 28)
                .foregroundStyle(.onBackground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
    }

    private func submitFeedback() {
        hideKeyboard()
        
        if !feedbackText.isEmpty {
            let feedbackData: [String: Any] = [
                "text": feedbackText,
                "timestamp": Timestamp()
            ]
            
            db.collection("feedbacks").addDocument(data: feedbackData) { error in
                if error == nil {
                    feedbackText = ""
                    showMessage = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showMessage = false
                    }
                }
            }
        }
    }
    
    private func checkInternetConnection(completion: @escaping () -> Void) {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue.global(qos: .background)
        monitor.start(queue: queue)
        
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                isOffline = path.status != .satisfied
                completion()
                monitor.cancel()
            }
        }
    }
}

struct InformationView: View {
    @State private var isSidebarOpen: Bool = false
    @EnvironmentObject var gameData: GameData
    @State private var message: String = ""
    @State private var navigationBarHeight: CGFloat = 0
    
    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack {
                NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { navigationBarHeight = $0 }
                Spacer()
            }

            // The message stays in the middle of the screen. Larger text sizes can make it too tall to fit
            // between the header and the bottom of the screen, so then it scrolls instead.
            ViewThatFits(in: .vertical) {
                messageText
                ScrollView { messageText }
            }
            .padding(.vertical, navigationBarHeight)
            
            Spacer()
            
            .onAppear { loadMessage() }
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Information")
        .navigationBarBackButtonHidden(true)
    }

    private var messageText: some View {
        Text(message)
            .scaledFont(size: UIScreen.main.bounds.width * 0.05)
            .foregroundStyle(.onBackground)
            .fontWeight(.bold)
            .padding()
            .multilineTextAlignment(.center)
    }

    private func loadMessage() {
        message = """
        Message from the creator.

        Hi there \(gameData.username.isEmpty ? "Player" : gameData.username)!

        I hope this message finds you well. I've been working hard on this app and I'm constantly striving to improve it.

        If you have suggestions or ideas, please use the feedback section in the sidebar.

        Thank you for your support!

        Have Fun!
        Ewdo Ozdemir
        """
    }
}

struct RemoveAdsView: View {
    @StateObject var purchaseManager = PurchaseManager.shared
    @State private var isSidebarOpen: Bool = false
    @EnvironmentObject var gameData: GameData

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex)
                .opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()

            VStack {
                NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                
                Spacer()
            }

            VStack(spacing: 20) {
                Text("Remove Ads")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.04)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                    .accessibilityAddTraits(.isHeader)
                
                if purchaseManager.adsRemoved {
                    Text("✅ Ads removed! Thank you.")
                        .foregroundStyle(.greenOnBackground)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.04)
                        .fontWeight(.bold)
                        // VoiceOver would read the emoji as "check mark button".
                        .accessibilityLabel("Ads removed! Thank you.")
                    
                } else {
                    if let product = purchaseManager.product {
                        Button("Buy - \(product.displayPrice)") {
                            Task { await purchaseManager.buyRemoveAds() }
                        }
                        .frame(
                            minWidth: UIScreen.main.bounds.width * 0.3,
                            minHeight: UIScreen.main.bounds.height * 0.07
                        )
                        .scaledFont(size: UIScreen.main.bounds.width * 0.04)
                        .fontWeight(.bold)
                        .padding()
                        .background(Color.buttonGreen)
                        .foregroundColor(.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)

                    } else if purchaseManager.productLoadFailed {
                        Text("Couldn't load Remove Ads from the App Store.")
                            .foregroundStyle(.onBackground)
                            .multilineTextAlignment(.center)

                        Button("Try Again") {
                            Task { await purchaseManager.fetchProducts() }
                        }
                        .padding()
                        .background(Color.buttonGreen)
                        .foregroundColor(.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    } else {
                        ProgressView("Loading price...")
                            .tint(ReadableOnBackground.onBackground)
                            .foregroundStyle(.onBackground)
                    }

                    Button("Restore Purchases") {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }
                    .padding()
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }

                if let message = purchaseManager.statusMessage {
                    Text(message)
                        .foregroundStyle(.onBackground)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .onAppear { announce(message) }
                        .onChange(of: message) { _, newMessage in announce(newMessage) }
                }
            }
            .disabled(purchaseManager.isBusy)
            .onAppear {
                purchaseManager.clearStatusMessage()
                Task { await purchaseManager.fetchProducts() }
            }
            .padding()
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Remove Ads")
        .navigationBarBackButtonHidden(true)
    }
}

struct SettingsView: View {
    @State private var name: String = ""
    @State private var isSidebarOpen: Bool = false
    @EnvironmentObject var gameData: GameData
    @State private var showMessage: Bool = false

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack {
                NavigationBar(Back: false, Points: true, isSidebarOpen: $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)

                Spacer()
            }
            
            VStack{
                Text("Settings")
                    .font(.system(size: UIScreen.main.bounds.width * 0.1))
                    .underline()
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .padding()
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
            }
            
            VStack{
                Spacer()
                
                Text("Name")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                    .underline()
                    .padding()
                    .accessibilityAddTraits(.isHeader)

                TextField(
                    "",
                    text: $name,
                    prompt: Text(gameData.username.isEmpty ? "Enter your name" : gameData.username)
                        .foregroundColor(.black)
                )
                .onSubmit {
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        gameData.username = name
                        gameData.saveData()
                        showFeedback()
                    }
                }
                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
                .answerBoxMargin()
                .frame(
                    width: UIScreen.main.bounds.width * 0.8,
                    height: max(UIScreen.main.bounds.height * 0.06, 44)
                )
                .background(Color.white)
                .cornerRadius(10)
                .textFieldStyle(PlainTextFieldStyle())
                .accessibilityLabel("Name")

                if showMessage {
                    Text("Name Saved")
                        .foregroundStyle(.largeGreenOnBackground)
                        .font(.system(size: UIScreen.main.bounds.width * 0.075))
                        .fontWeight(.bold)
                        .padding()
                        .transition(.opacity)
                        .onAppear { announce("Name Saved") }
                }
                
                Button(action: {
                    gameData.username = name
                    gameData.saveData()
                    showFeedback()
                }) {
                    Text("Enter")
                        .padding()
                        .frame(
                            width: UIScreen.main.bounds.width * 0.4,
                            height: max(UIScreen.main.bounds.height * 0.06, 44)
                        )
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .fontWeight(.bold)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .padding(.bottom, 20)

                Spacer()
                Text("SFX Volume")
                    .fontWeight(.bold)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .underline()
                    .padding()
                    .accessibilityAddTraits(.isHeader)

                Slider(value: $gameData.sfxvolume, in: 0...1, onEditingChanged: { _ in
                    gameData.saveData()
                })
                .tint(ReadableOnBackground.onBackground)
                .accessibilityLabel("Sound effects volume")
                .frame(width: UIScreen.main.bounds.width / 1.5)
                .padding()
                
                Spacer()
            }
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Settings")
        .onAppear {
            name = gameData.username
        }
        // VoiceOver moves the slider without dragging it, so `onEditingChanged` might not save its volume.
        .onDisappear { gameData.saveData() }
        .navigationBarBackButtonHidden(true)
    }
    
    private func showFeedback() {
        withAnimation {
            showMessage = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
    
}

struct MainMenuView: View {
    @EnvironmentObject var gameData: GameData
    @State private var isSidebarOpen = false

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            VStack {
                ZStack {
                    NavigationBar(Back: false, Points: false, isSidebarOpen: $isSidebarOpen)
                        .frame(maxWidth: .infinity)
                        .edgesIgnoringSafeArea(.top)
                        .padding(.top, UIScreen.main.bounds.height * 0.002)
                    
                    Text("Maths Quest")
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundStyle(.onBackground)
                        .fontWeight(.bold)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                }
                
                Spacer()
                
                Text("Points: \(gameData.points)")
                    .font(.system(size: UIScreen.main.bounds.width * 0.1))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
            }
            VStack(spacing: UIScreen.main.bounds.height * 0.08) {
                Spacer()
                
                HStack {
                    ScreenButton(to: .year(1)) {
                        menuButton(title: "Year 1")
                    }
                                        
                    ScreenButton(to: .year(2)) {
                        menuButton(title: "Year 2")
                    }
                }
                                
                HStack {
                    ScreenButton(to: .year(3)) {
                        menuButton(title: "Year 3")
                    }
                    
                    Spacer()
                    
                    ScreenButton(to: .year(4)) {
                        menuButton(title: "Year 4")
                    }
                }
                                
                HStack {
                    ScreenButton(to: .year(5)) {
                        menuButton(title: "Year 5")
                    }
                    
                    Spacer()
                    
                    ScreenButton(to: .year(6)) {
                        menuButton(title: "Year 6")
                    }
                }
                
                Spacer()
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .disabled(isSidebarOpen)
            
            Spacer()
        }
        .sidebarOverlay(isOpen: $isSidebarOpen, selectedTab: "Main Menu")
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }

    private func menuButton(title: String) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: UIScreen.main.bounds.height * 0.15)
            .font(.system(size: UIScreen.main.bounds.width * 0.1))
            .fontWeight(.bold)
            .background(Color.white)
            .foregroundColor(.black)
            .cornerRadius(UIScreen.main.bounds.width * 0.0525)
    }
}

struct Year1View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    
    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                
            
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 1")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.counting)) {
                    Text("Counting")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.addition)) {
                    Text("Addition")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.subtraction)) {
                    Text("Subtraction")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

/// One Year 1 Counting question: ten numbers in order with one missing. Year 1 counts to and across
/// 100 from 0, 1 or any given number, so a sequence can start anywhere from 0 to 91.
struct Year1CountingQuestion: Equatable {
    static let length = 10
    static let largestNumber = 100
    static let starts = 0...(largestNumber - length + 1)

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var start: Int
    /// The position of the missing number, from 0 to 9.
    var missingIndex: Int

    static func random() -> Year1CountingQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year1CountingQuestion {
        Year1CountingQuestion(start: Int.random(in: starts, using: &generator),
                              missingIndex: Int.random(in: 0..<length, using: &generator))
    }

    var numbers: [Int] {
        Array(start..<start + Self.length)
    }

    var missingNumber: Int {
        start + missingIndex
    }

    func evaluate(_ text: String) -> Outcome {
        guard !TypedAnswer.isBlank(text) else { return .unanswered }
        return TypedAnswer.wholeNumber(text) == missingNumber ? .correct : .incorrect
    }
}

struct Year1CountingView: View {
    @State private var current = Year1CountingQuestion.random()
    @State private var isSidebarOpen : Bool = false
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            VStack(spacing: 20) {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<current.numbers.count, id: \.self) { index in
                        if index == current.missingIndex {
                            Text("_")
                                .accessibilityLabel(SpokenMaths.missingNumber)
                                .frame(width: UIScreen.main.bounds.width / 12)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.buttonGrey)
                                .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        } else {
                            // Three digits shrink to fit rather than wrapping.
                            Text("\(current.numbers[index])")
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: UIScreen.main.bounds.width / 12)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.buttonGrey)
                                .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        }
                    }
                }
                
                
                Text("What number is missing?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                    .padding()
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }
                
                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }
                
                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }
    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        current = Year1CountingQuestion.random()
        answerString = ""
        responseMessage = ""
        progress.reset()
    }
}

struct Year1AdditionView: View {
    @State private var randomnumber1 = Int.random(in: 0..<10)
    @State private var isSidebarOpen : Bool = false
    @State private var randomnumber2 = Int.random(in: 0..<10)
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 20) {
                Text("\(randomnumber1) + \(randomnumber2)")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                Text("What is the sum of these numbers?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func resetQuestion() {
        randomnumber1 = Int.random(in: 0..<10)
        randomnumber2 = Int.random(in: 0..<10)
        answerString = ""
        progress.reset()
    }
    
    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        guard !TypedAnswer.isBlank(answerString) else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        if let answerInt = TypedAnswer.wholeNumber(answerString), answerInt == randomnumber1 + randomnumber2 {
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        } else {
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

struct Year1SubtractionView: View {
    @State private var randomnumber1 = Int.random(in: 0..<10)
    @State private var isSidebarOpen : Bool = false
    @State private var randomnumber2 = Int.random(in: 0..<10)
    @State private var randomnumber3: Int = 0
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 20) {

                Text("\(randomnumber1) - \(randomnumber2)")
                    .accessibilityLabel("\(randomnumber1) minus \(randomnumber2)")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)

                Text("What is the result of this subtraction?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .onAppear {
            numberadjustment()
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        guard !TypedAnswer.isBlank(answerString) else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        if let answerInt = TypedAnswer.wholeNumber(answerString), answerInt == randomnumber1 - randomnumber2 {
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
            
        } else {
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }
    
    private func numberadjustment() {
        if randomnumber2 > randomnumber1 {
            randomnumber3 = randomnumber1
            randomnumber1 = randomnumber2
            randomnumber2 = randomnumber3
        } else {
            randomnumber3 = 0
        }
    }

    
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        randomnumber1 = Int.random(in: 0..<10)
        randomnumber2 = Int.random(in: 0..<10)
        answerString = ""
        responseMessage = ""
        progress.reset()
        numberadjustment()
    }
}

struct Year2View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    
    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 2")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.multiplication)) {
                    Text("Multiplication")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.division)) {
                    Text("Division")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.shapes)) {
                    Text("Shapes")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

/// One Year 2 Multiplication question from the 2, 5 and 10 times tables, up to 10 lots of each.
/// The table can come first or second, since Year 2 learns that multiplication can be done in
/// any order.
struct Year2MultiplicationQuestion: Equatable {
    static let tables = [2, 5, 10]
    static let multipliers = 1...10

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var first: Int
    var second: Int

    static func random() -> Year2MultiplicationQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year2MultiplicationQuestion {
        let table = tables.randomElement(using: &generator)!
        let multiplier = Int.random(in: multipliers, using: &generator)
        return Bool.random(using: &generator)
            ? Year2MultiplicationQuestion(first: table, second: multiplier)
            : Year2MultiplicationQuestion(first: multiplier, second: table)
    }

    var text: String {
        "\(first) × \(second)"
    }

    /// "times", rather than leaving VoiceOver to name the "×" sign.
    var spokenText: String {
        "\(first) times \(second)"
    }

    var product: Int {
        first * second
    }

    func evaluate(_ text: String) -> Outcome {
        guard !TypedAnswer.isBlank(text) else { return .unanswered }
        return TypedAnswer.wholeNumber(text) == product ? .correct : .incorrect
    }
}

struct Year2MultiplicationView: View {
    @State private var current = Year2MultiplicationQuestion.random()
    @State private var isSidebarOpen : Bool = false
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            VStack(spacing: 20) {
                Text(current.text)
                    .accessibilityLabel(current.spokenText)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                Text("What is the product of these numbers?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }
    
    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func resetQuestion() {
        current = Year2MultiplicationQuestion.random()
        answerString = ""
        responseMessage = ""
        progress.reset()
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

/// One Year 2 Division question using the division facts for the 2, 5 and 10 times tables. The
/// number divided is made from the answer, so every question divides exactly, never by zero, and
/// the first question is made the same way as every later one.
struct Year2DivisionQuestion: Equatable {
    static let divisors = [2, 5, 10]
    static let quotients = 1...10

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var divisor: Int
    var quotient: Int

    static func random() -> Year2DivisionQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year2DivisionQuestion {
        Year2DivisionQuestion(divisor: divisors.randomElement(using: &generator)!,
                              quotient: Int.random(in: quotients, using: &generator))
    }

    var dividend: Int {
        divisor * quotient
    }

    var text: String {
        "\(dividend) ÷ \(divisor)"
    }

    func evaluate(_ text: String) -> Outcome {
        guard !TypedAnswer.isBlank(text) else { return .unanswered }
        return TypedAnswer.wholeNumber(text) == quotient ? .correct : .incorrect
    }
}

struct Year2DivisionView: View {
    @State private var current = Year2DivisionQuestion.random()
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var isSidebarOpen : Bool = false
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 20) {

                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)

                Text("What is the result of this division?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }
    private func resetQuestion() {
        current = Year2DivisionQuestion.random()
        answerString = ""
        responseMessage = ""
        progress.reset()
    }
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

/// One Year 2 Shapes question. Sides are asked about as straight sides: a polygon's sides are
/// straight, and a circle has none, though some schemes describe its curved edge as one curved
/// side. Asking about straight sides gives every shape, the circle included, one clear answer.
struct Year2ShapeQuestion: Equatable {
    struct Figure: Equatable {
        var name: String
        var straightSides: Int
        var corners: Int
    }

    static let figures = [
        Figure(name: "circle", straightSides: 0, corners: 0),
        Figure(name: "triangle", straightSides: 3, corners: 3),
        Figure(name: "square", straightSides: 4, corners: 4),
        Figure(name: "pentagon", straightSides: 5, corners: 5),
        Figure(name: "hexagon", straightSides: 6, corners: 6),
        Figure(name: "octagon", straightSides: 8, corners: 8)
    ]

    enum Kind: Equatable {
        case sides, corners, name
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var kind: Kind
    /// Index into `figures`.
    var figureIndex: Int

    static func random() -> Year2ShapeQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year2ShapeQuestion {
        let figureIndex = Int.random(in: 0..<figures.count, using: &generator)
        let type = Int.random(in: 1...3, using: &generator) // 1: Sides, 2: Corners, 3: Name
        let kind: Kind = type == 1 ? .sides : type == 2 ? .corners : .name
        return Year2ShapeQuestion(kind: kind, figureIndex: figureIndex)
    }

    var figure: Figure {
        Self.figures[figureIndex]
    }

    var text: String {
        switch kind {
        case .sides:
            return "How many straight sides does this shape have?"
        case .corners:
            return "How many corners does this shape have?"
        case .name:
            return "What is this shape called?"
        }
    }

    /// Numbers are read as numbers. Names ignore capitals and spaces, as before, and punctuation at either end,
    /// so "Square." is right.
    func evaluate(_ text: String) -> Outcome {
        guard !TypedAnswer.isBlank(text) else { return .unanswered }
        switch kind {
        case .sides:
            return TypedAnswer.wholeNumber(text) == figure.straightSides ? .correct : .incorrect
        case .corners:
            return TypedAnswer.wholeNumber(text) == figure.corners ? .correct : .incorrect
        case .name:
            let name = text.trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            return name.lowercased().replacingOccurrences(of: " ", with: "") == figure.name ? .correct : .incorrect
        }
    }

    // MARK: VoiceOver

    /// A part of the shape's edge. VoiceOver can't see the picture, so it is given the edge to go round instead,
    /// a part at a time, the way a child would feel round a shape cut out of card. The parts are never numbered or
    /// counted for the child, and the shape is never named, so the child still does the counting and naming.
    enum OutlinePart: Equatable {
        case corner, straightSide, curvedEdge
    }

    /// The edge from the corner at the top, going round clockwise: a corner, the straight side after it, the next
    /// corner, and so on until the last side reaches the top again. A circle's edge is one curved edge.
    var outline: [OutlinePart] {
        guard figure.straightSides > 0 else { return [.curvedEdge] }
        return (0..<figure.straightSides).flatMap { _ in [OutlinePart.corner, .straightSide] }
    }

    /// Read first. It says only what a child sees at a glance without counting: the drawn shapes are regular, so a
    /// square is told apart from other four-sided shapes as it is in the picture.
    var pictureLabel: String {
        figure.straightSides > 0 ? "Shape picture. Its straight sides are all the same length." : "Shape picture."
    }

    static let pictureHint = "Swipe right to go round its edge, part by part."

    func spokenLabel(ofPartAt index: Int) -> String {
        switch outline[index] {
        case .curvedEdge:
            return "Curved edge. It goes all the way round and joins up with itself."
        case .corner:
            return index == 0 ? "Corner at the top. The edge starts here." : "Corner"
        case .straightSide:
            return index == outline.count - 1 ? "Straight side, back to the corner at the top" : "Straight side"
        }
    }

    /// Where each part of `outline` is in the picture: the corner itself, or the middle of the side.
    func outlinePoints(in rect: CGRect) -> [CGPoint] {
        let sides = figure.straightSides
        guard sides > 0 else { return [CGPoint(x: rect.midX, y: rect.midY)] }
        let corners = ShapeMaker.corners(sides: sides, in: rect)
        return (0..<sides).flatMap { i -> [CGPoint] in
            let start = corners[i], end = corners[(i + 1) % sides]
            return [start, CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)]
        }
    }
}

/// The Year 2 shape. VoiceOver reads the picture's description, then moves round its edge a part at a time.
struct Year2ShapePicture: View {
    let question: Year2ShapeQuestion
    let size: CGFloat

    var body: some View {
        let outline = question.outline
        Group {
            if question.figure.straightSides == 0 {
                Text("●")
                    .font(.system(size: size))
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
            } else {
                ShapeMaker(sides: question.figure.straightSides)
                    .fill(.onBackground)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(question.pictureLabel)
        .accessibilityHint(Year2ShapeQuestion.pictureHint)
        .accessibilityAddTraits(.isImage)
        .accessibilitySortPriority(Double(outline.count + 1))
        .overlay {
            GeometryReader { geometry in
                let points = question.outlinePoints(in: CGRect(origin: .zero, size: geometry.size))
                // Each part is a small invisible spot, so it doesn't cover the spots next to it.
                let spot = question.figure.straightSides == 0 ? geometry.size : CGSize(width: size * 0.12, height: size * 0.12)
                ForEach(outline.indices, id: \.self) { index in
                    Color.clear
                        .frame(width: spot.width, height: spot.height)
                        .position(points[index])
                        .accessibilityElement()
                        .accessibilityLabel(question.spokenLabel(ofPartAt: index))
                        .accessibilitySortPriority(Double(outline.count - index))
                }
            }
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }
}

struct Year2ShapesView: View {
    @State private var current = Year2ShapeQuestion.random()
    @State private var isSidebarOpen : Bool = false
    @State private var answerString: String = ""
    @State private var responseMessage: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack {
                Year2ShapePicture(question: current, size: UIScreen.main.bounds.width * 0.2)
                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }
                    .answerKeyboard(current.kind == .name ? .default : .numberPad)


                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        current = Year2ShapeQuestion.random()
        answerString = ""
        responseMessage = ""
        progress.reset()
    }
}

struct ShapeMaker: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        guard sides > 2 else { return Path() }
        var path = Path()
        path.addLines(Self.corners(sides: sides, in: rect))
        path.closeSubpath()
        return path
    }

    /// The corners, starting at the top and going round clockwise.
    static func corners(sides: Int, in rect: CGRect) -> [CGPoint] {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angle = 2 * .pi / CGFloat(sides)
        return (0..<sides).map { i in
            CGPoint(x: center.x + radius * cos(angle * CGFloat(i) - .pi / 2),
                    y: center.y + radius * sin(angle * CGFloat(i) - .pi / 2))
        }
    }
}

struct Year3View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    
    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 3")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.fractions)) {
                    Text("Fractions")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.measurement)) {
                    Text("Measurement")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.time)) {
                    Text("Time")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

struct Year3FractionsView: View {
    @State private var question: Int = Int.random(in: 1...2)
    @State private var fractions: [[Int]] = [
        [1, 2], [1, 3], [1, 4], [2, 3], [3, 4]
    ]
    @State private var simplifyFractions: [[String]] = [
        ["²/₄", "1/2"], ["³/₆", "1/2"], ["⁴/₈", "1/2"],
        ["²/₆", "1/3"], ["⁴/₆", "2/3"]
    ]
    @State private var randomFractionIndex: Int = Int.random(in: 0..<5)
    @State private var multiplier: Int = 12
    @State private var answerString: String = ""
    @State private var numeratorString: String = ""
    @State private var denominatorString: String = ""
    @State private var responseMessage: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var isSidebarOpen : Bool = false
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            
            VStack {
                Text(loadQuestion())
                    .accessibilityLabel(spokenQuestion())
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                    .padding()

                WorkingOutView(canvasView: $canvasView)
                
                if question == 2 {
                    TextField(answerBox: "Enter your answer", text: $answerString)
                        .scaledFont(size: 17)
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: 300)
                        .answerKeyboard(.numberPad)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }

                } else {
                    FractionAnswerBoxes(numerator: $numeratorString, denominator: $denominatorString) {
                        checkAnswer()
                        hideKeyboard()
                    }
                }
                
                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func loadQuestion() -> String {
        switch question {
        case 1:
            return "Simplify \(simplifyFractions[randomFractionIndex][0])"
        case 2:
            let fraction = fractions[randomFractionIndex]
            return "What is \(fraction[0])/\(fraction[1]) of \(multiplier)?"
        default:
            return ""
        }
    }

    /// "Simplify 2 quarters" rather than VoiceOver reading out the small digits of "²/₄".
    private func spokenQuestion() -> String {
        switch question {
        case 1:
            let written = simplifyFractions[randomFractionIndex][0]
            return "Simplify " + (SpokenMaths.fraction(written) ?? written)
        case 2:
            let fraction = fractions[randomFractionIndex]
            return "What is \(SpokenMaths.fraction(numerator: fraction[0], denominator: fraction[1])) of \(multiplier)?"
        default:
            return ""
        }
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        let isBlank = question == 1
            ? TypedAnswer.isBlank(numeratorString) && TypedAnswer.isBlank(denominatorString)
            : TypedAnswer.isBlank(answerString)
        guard !isBlank else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        let isCorrect: Bool
        if question == 1{
            let correctAnswer = simplifyFractions[randomFractionIndex][1]
            // " 1" and "01" are both 1.
            let numerator = TypedAnswer.wholeNumber(numeratorString).map(String.init) ?? numeratorString
            let denominator = TypedAnswer.wholeNumber(denominatorString).map(String.init) ?? denominatorString
            let userAnswer = numerator + "/" + denominator
            isCorrect = userAnswer == correctAnswer
        } else{
            let fraction = fractions[randomFractionIndex]
            let correctAnswer = fraction[0] * multiplier / fraction[1]
            isCorrect = TypedAnswer.wholeNumber(answerString) == correctAnswer
        }

        switch progress.recordSubmission(isCorrect: isCorrect) {
        case .ignored:
            return
        case .correct:
            responseMessage = correctResponse()
        case .incorrect:
            responseMessage = incorrectResponse()
        }
    }

    private func correctResponse() -> String {
        showFeedback()
        sfxPlayer.playSound(named: "right", volume:gameData.sfxvolume)
        gameData.points += 1
        gameData.totalQuestionsAnswered += 1
        gameData.saveData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            resetQuestion()
        }
        return "Correct!"
    }

    private func incorrectResponse() -> String {
        sfxPlayer.playSound(named: "wrong", volume:gameData.sfxvolume)
        showFeedback()
        return "Incorrect. Try Again!"
    }
    
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
    
    private func resetQuestion() {
        randomFractionIndex = Int.random(in: 0..<fractions.count)
        let denominator = fractions[randomFractionIndex][1]
        let factor = Int.random(in: 2...5)
        multiplier = denominator * factor
        question = Int.random(in: 1...2)
        answerString = ""
        numeratorString = ""
        denominatorString = ""
        responseMessage = ""
        canvasView.drawing = PKDrawing()
        progress.reset()
    }
}

/// One Year 3 Measurement question: converting a whole number of one Year 3 unit into a smaller
/// one, or measuring the red bar against the ruler. The first question is made the same way as
/// every later one.
struct Year3MeasurementQuestion: Equatable {
    /// The units Year 3 measures with, largest first: length (m/cm/mm), mass (kg/g) and
    /// volume/capacity (l/ml).
    static let unitGroups = [["m", "cm", "mm"], ["kg", "g"], ["l", "ml"]]
    /// Each unit above in the smallest unit of its group, so 1 m is 1000 mm.
    static let unitSizes = [[1000, 10, 1], [1000, 1], [1000, 1]]
    static let amounts = 1...10
    /// Whole centimetres, so the bar always fits the 15 cm ruler.
    static let objectLengths = 1...10

    enum Kind: Equatable {
        case convert, measure
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
        /// Asked again without counting as a wrong attempt, as before.
        case notANumber
        /// "1,000" could mean 1000 or 1.0, so it isn't marked either way.
        case ambiguousComma
    }

    var kind: Kind
    /// Index into `unitGroups`.
    var group: Int
    /// Indices into the group's units. `from` is always the larger unit.
    var from: Int
    var to: Int
    var amount: Int
    var objectLength: Int

    static func random() -> Year3MeasurementQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year3MeasurementQuestion {
        let type = Int.random(in: 1...2, using: &generator) // 1: Convert, 2: Measure
        let group = Int.random(in: 0..<unitGroups.count, using: &generator)
        let unitCount = unitGroups[group].count
        let from = Int.random(in: 0..<unitCount - 1, using: &generator)
        let to = Int.random(in: from + 1..<unitCount, using: &generator)
        return Year3MeasurementQuestion(kind: type == 1 ? .convert : .measure,
                                        group: group, from: from, to: to,
                                        amount: Int.random(in: amounts, using: &generator),
                                        objectLength: Int.random(in: objectLengths, using: &generator))
    }

    var units: [String] {
        Self.unitGroups[group]
    }

    var fromUnit: String {
        units[from]
    }

    var toUnit: String {
        units[to]
    }

    var text: String {
        "Convert \(amount) \(fromUnit) into \(toUnit)"
    }

    /// Always a whole number, because only larger units are converted into smaller ones.
    var convertedAmount: Int {
        amount * Self.unitSizes[group][from] / Self.unitSizes[group][to]
    }

    /// A conversion also needs the right unit picking. A measurement is in centimetres, and must
    /// be exact, so 4.9 is not 4.
    func evaluate(answer: String, unit: String) -> Outcome {
        let expected = kind == .convert ? convertedAmount : objectLength
        switch TypedAnswer.decimalEntry(answer) {
        case .blank:
            return .unanswered
        case .ambiguousComma:
            return .ambiguousComma
        case .notANumber:
            return .notANumber
        case let .number(numerator, denominator, _):
            guard TypedAnswer.fractionsAreEqual(numerator, denominator, expected, 1) else { return .incorrect }
            if kind == .convert && unit != toUnit {
                return .incorrect
            }
            return .correct
        }
    }
}

struct Year3MeasurementView: View {
    @State private var current = Year3MeasurementQuestion.random()
    @State var answerString: String = ""
    @State var responseMessage: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var showMessage = false
    @State private var isSidebarOpen : Bool = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var scale: CGFloat = UIScreen.main.bounds.width / 20
    @State private var offsetX: CGFloat = 0
    @State private var userUnit: String = ""
    @State private var progress = QuestionProgress()
    @State private var canvasView = PKCanvasView()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 10) {
                if current.kind == .convert {
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .foregroundStyle(.onBackground)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 20)
                } else {
                    VStack(spacing: 20) {
                        Text("Measure the object below:")
                            .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                            .foregroundStyle(.onBackground)
                            .multilineTextAlignment(.center)
                        
                        Text("Move the rectangle to the base of the ruler.")
                            .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                            .foregroundStyle(.onBackground)
                            .multilineTextAlignment(.center)
                        
                        DraggableRectangleView(
                            objectLength: current.objectLength,
                            scale: scale,
                            offsetX: $offsetX
                        )

                        ZStack {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: UIScreen.main.bounds.width * 0.9, height: UIScreen.main.bounds.width * 0.175)
                                .cornerRadius(5)
                                
                            RulerView()
                                .frame(width: UIScreen.main.bounds.width * 0.9, height: UIScreen.main.bounds.width * 0.1)
                        }
                    }
                }

                if current.kind == .convert {
                    WorkingOutView(canvasView: $canvasView)
                }
                
                VStack(spacing: 20) {
                    HStack {
                        TextField(answerBox: "Answer", text: $answerString)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }

                        if current.kind == .convert {
                            Picker("Pick a unit", selection: $userUnit) {
                                // Placeholder tagged "" so the wheel never shows a unit that isn't actually selected
                                Text("Unit")
                                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                    .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                    .tag("")
                                ForEach(current.units, id: \.self) { option in
                                    Text(option)
                                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                        .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                        .tag(option)
                                }
                            }
                            .pickerStyle(.wheel)
                            .colorSchemeForBackground()
                            .frame(width: UIScreen.main.bounds.width * 0.2,
                                   height: UIScreen.main.bounds.width * 0.3)
                        } else {
                            Text("cm")
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .foregroundStyle(.onBackground)
                        }
                    }
                    
                    if showMessage {
                        AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                    }

                    HStack{
                        Button {
                            hideKeyboard()
                            checkAnswer()
                        } label: {
                            Text("Enter ")
                                .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                        }
                        .disabled(showMessage)
                        .foregroundColor(.black)
                        .font(.system(size: UIScreen.main.bounds.width * 0.075))
                        .multilineTextAlignment(.center)
                        .fontWeight(.bold)
                        .padding()
                        
                        if progress.showSkipButton {
                            Button {
                                if let rootVC = UIApplication.shared.connectedScenes
                                    .compactMap({ $0 as? UIWindowScene })
                                    .first?.windows.first?.rootViewController {
                                    
                                    AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                        guard progress.recordSkip() else { return }
                                        gameData.skipQuestion(resetQuestion: resetQuestion)
                                    }
                                }
                            } label: {
                                Text("Skip Question")
                                    .scaledFont(size: 17, maximum: 28)
                                    .padding()
                                    .buttonBox(Color.buttonBlue, cornerRadius: 10)
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .questionSubmitRow()
                }
            }
            .padding(.horizontal, 16)
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answer: answerString, unit: userUnit) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .notANumber:
            responseMessage = "Please enter a valid number!"
            showFeedback()
        case .ambiguousComma:
            responseMessage = "Write it without a comma."
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        current = Year3MeasurementQuestion.random()
        canvasView.drawing = PKDrawing()
        answerString = ""
        userUnit = ""
        responseMessage = ""
        // The bar stays on screen when one measuring question follows another, so it's moved here
        // as well as when it first appears.
        offsetX = RulerPlacement(objectLength: current.objectLength, scale: scale).startOffset
        progress.reset()
    }
}

struct RulerView: View {
    let scale: CGFloat = UIScreen.main.bounds.width / 20

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                HStack(spacing: 0) {
                    ForEach(0...15, id: \.self) { index in
                        VStack {
                            Rectangle()
                                .frame(width: UIScreen.main.bounds.width * 0.005,
                                       height: UIScreen.main.bounds.height * 0.025)
                                .foregroundColor(.black)
                                .cornerRadius(5)

                            if index % 1 == 0 {
                                Text("\(index)")
                                    .font(.system(size:UIScreen.main.bounds.height * 0.015))
                                    .foregroundColor(.black)
                            }
                        }
                        .frame(width: scale)
                    }
                }
                .frame(width: UIScreen.main.bounds.width * 0.9)

                Text("cm")
                    .font(.system(size:UIScreen.main.bounds.height * 0.02))
                    .foregroundColor(.black)
                    .padding(.trailing, 5)
                    .padding(.bottom, 5)
                    .offset(x: -UIScreen.main.bounds.width / 111, y: UIScreen.main.bounds.height * 0.02)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ruler, marked from 0 to \(RulerPlacement.rulerLength) centimetres")
    }
}

/// Where the red bar sits over the ruler. Offsets are from the centre of the screen, which is also
/// the centre of the ruler's 0 to 15 cm marks, and the bar's left end is reported as a ruler
/// mark. The bar can't leave the ruler, and when let go it settles with both ends on whole
/// centimetres, whatever its length.
struct RulerPlacement: Equatable {
    /// RulerView's marks run from 0 to 15 cm.
    static let rulerLength = 15

    var objectLength: Int
    /// Points per centimetre.
    var scale: CGFloat

    /// The left end on 0.
    var minOffset: CGFloat {
        -CGFloat(Self.rulerLength) * scale / 2 + CGFloat(objectLength) * scale / 2
    }

    /// The right end on 15.
    var maxOffset: CGFloat {
        CGFloat(Self.rulerLength) * scale / 2 - CGFloat(objectLength) * scale / 2
    }

    func clamped(_ offset: CGFloat) -> CGFloat {
        min(max(offset, minOffset), maxOffset)
    }

    /// The ruler mark under the bar's left end.
    func leftEdgeMark(at offset: CGFloat) -> CGFloat {
        (clamped(offset) - minOffset) / scale
    }

    /// Moves the bar `centimetres` along the ruler, as far as the end, settling on whole centimetres.
    func offset(movingBy centimetres: Int, from offset: CGFloat) -> CGFloat {
        snapped(clamped(snapped(offset) + CGFloat(centimetres) * scale))
    }

    /// Where the bar's ends are, as VoiceOver reads it. Both ends are given, as a ruler shows them.
    func spokenPosition(at offset: CGFloat) -> String {
        let left = Int(leftEdgeMark(at: offset).rounded())
        return "Left end at \(left) centimetres, right end at \(left + objectLength) centimetres"
    }

    /// The nearest offset with both ends on whole centimetres.
    func snapped(_ offset: CGFloat) -> CGFloat {
        minOffset + leftEdgeMark(at: offset).rounded() * scale
    }

    /// The bar follows the finger by however far it has moved since the drag began, so it never
    /// jumps when picked up.
    func offset(afterDragging translation: CGFloat, from start: CGFloat) -> CGFloat {
        clamped(start + translation)
    }

    /// Near the middle of the ruler, on whole centimetres.
    var startOffset: CGFloat {
        snapped(0)
    }
}

struct DraggableRectangleView: View {
    var objectLength: Int
    var scale: CGFloat
    @Binding var offsetX: CGFloat

    /// Where the bar was when the current drag began.
    @State private var dragStartOffset: CGFloat?

    private var placement: RulerPlacement {
        RulerPlacement(objectLength: objectLength, scale: scale)
    }

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: CGFloat(objectLength) * scale, height: 20)
            .cornerRadius(5)
            // On a background too close to red to see the bar's ends, an outline just inside its edge, so it's still
            // exactly as long as the object.
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.redBarOutline, lineWidth: 2))
            .offset(x: offsetX)
            .gesture(
                // Global coordinates, so moving the bar doesn't change how the drag is measured.
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartOffset ?? offsetX
                        dragStartOffset = start
                        offsetX = placement.offset(afterDragging: value.translation.width, from: start)
                    }
                    .onEnded { _ in
                        dragStartOffset = nil
                        withAnimation(.easeOut(duration: 0.2)) {
                            offsetX = placement.snapped(offsetX)
                        }
                    }
            )
            .onAppear {
                offsetX = placement.startOffset
            }
            // VoiceOver can't drag, so swiping up or down moves the bar a centimetre instead.
            .accessibilityElement()
            .accessibilityLabel("Red bar to measure")
            .accessibilityValue(placement.spokenPosition(at: offsetX))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: offsetX = placement.offset(movingBy: 1, from: offsetX)
                case .decrement: offsetX = placement.offset(movingBy: -1, from: offsetX)
                @unknown default: break
                }
            }
    }
}

/// One Year 3 Time question. Generation and marking live outside the view so every kind of
/// question can be checked for an answer that is reachable and marked fairly.
struct Year3TimeQuestion: Equatable {
    enum Kind: Equatable {
        /// "Convert 2 hours and 15 minutes into minutes"
        case toMinutes(hours: Int, minutes: Int)
        /// "Convert 135 minutes into hours and minutes."
        case toHoursAndMinutes(minutes: Int)
        /// A start time in 24-hour time plus a duration, answered in 24-hour time.
        case timeAfter(hours: Int, minutes: Int, startHour: Int, startMinute: Int)
        /// `hour` is 0...23; the clock is labelled AM or PM and read in 12-hour time.
        case readClock(hour: Int, minute: Int)
        /// `hour` is 0...23; the analogue clock is matched modulo 12 hours.
        case setClock(hour: Int, minute: Int)
    }

    enum Outcome: Equatable {
        case unanswered, correct, incorrect
    }

    static let hoursToConvert = 1...6
    /// At least an hour, so "hours and minutes" always has some hours in it.
    static let minutesToConvert = 60...300
    static let durationHours = 0...6

    var kind: Kind

    static func random() -> Year3TimeQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    /// Keeps the old mix: a third of questions are "what is the time after", and a sixth are each of the others.
    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year3TimeQuestion {
        switch Int.random(in: 0..<6, using: &generator) {
        case 0:
            return Year3TimeQuestion(kind: .toMinutes(hours: Int.random(in: hoursToConvert, using: &generator),
                                                      minutes: Int.random(in: 0..<60, using: &generator)))
        case 1:
            return Year3TimeQuestion(kind: .toHoursAndMinutes(minutes: Int.random(in: minutesToConvert, using: &generator)))
        case 2, 3:
            var hours = 0
            var minutes = 0
            // "0 hours and 0 minutes after" isn't a question.
            while hours == 0 && minutes == 0 {
                hours = Int.random(in: durationHours, using: &generator)
                minutes = Int.random(in: 0..<60, using: &generator)
            }
            return Year3TimeQuestion(kind: .timeAfter(hours: hours, minutes: minutes,
                                                      startHour: Int.random(in: 0...23, using: &generator),
                                                      startMinute: Int.random(in: 0..<60, using: &generator)))
        case 4:
            return Year3TimeQuestion(kind: .readClock(hour: Int.random(in: 0...23, using: &generator),
                                                      minute: Int.random(in: 0..<60, using: &generator)))
        default:
            // The clock to set starts at 12:00, so 12:00 and 00:00 would already be right.
            var hour = 0
            var minute = 0
            while hour % 12 == 0 && minute == 0 {
                hour = Int.random(in: 0...23, using: &generator)
                minute = Int.random(in: 0..<60, using: &generator)
            }
            return Year3TimeQuestion(kind: .setClock(hour: hour, minute: minute))
        }
    }

    /// "1 hour and 5 minutes", "2 hours", "45 minutes".
    static func duration(hours: Int, minutes: Int) -> String {
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        let minuteText = "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        if hours == 0 { return minuteText }
        if minutes == 0 { return hourText }
        return hourText + " and " + minuteText
    }

    static func twentyFourHour(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    var text: String {
        switch kind {
        case let .toMinutes(hours, minutes):
            return "Convert \(Self.duration(hours: hours, minutes: minutes)) into minutes"
        case let .toHoursAndMinutes(minutes):
            return "Convert \(minutes) minutes into hours and minutes."
        case let .timeAfter(hours, minutes, startHour, startMinute):
            return "What is the time \(Self.duration(hours: hours, minutes: minutes)) after \(Self.twentyFourHour(startHour, startMinute))?"
        case .readClock:
            return "What time is shown on this clock?"
        case let .setClock(hour, minute):
            return "Show \(Self.twentyFourHour(hour, minute)) on this analogue clock."
        }
    }

    /// The line under the question saying how to answer, if there is one.
    var instructions: String? {
        switch kind {
        case .timeAfter: return "Answer using the 24-hour clock."
        case .readClock: return "Answer in 12-hour HH:MM format."
        default: return nil
        }
    }

    /// The answer as hours and minutes. For `toMinutes` it's all in `minutes`; for `readClock` the hour is 1...12.
    var answer: (hours: Int, minutes: Int) {
        switch kind {
        case let .toMinutes(hours, minutes):
            return (0, 60 * hours + minutes)
        case let .toHoursAndMinutes(minutes):
            return (minutes / 60, minutes % 60)
        case let .timeAfter(hours, minutes, startHour, startMinute):
            let end = ((startHour * 60 + startMinute) + (hours * 60 + minutes)) % (24 * 60)
            return (end / 60, end % 60)
        case let .readClock(hour, minute):
            return (ClockMaths.twelveHour(hour), minute)
        case let .setClock(hour, minute):
            return (hour, minute)
        }
    }

    /// `minutes` is the only box for `toMinutes`; the clock position is only used by `setClock`.
    func evaluate(hours: String, minutes: String, clockHour: Int = 0, clockMinute: Int = 0) -> Outcome {
        switch kind {
        case let .setClock(hour, minute):
            // The clock starts at 12:00, which is never the time asked for, so hands that still show 12:00 are no answer.
            if clockHour % 12 == 0 && clockMinute == 0 { return .unanswered }
            return ClockMaths.isCorrectlySet(clockHour: clockHour, clockMinute: clockMinute, hour24: hour, minute: minute)
                ? .correct : .incorrect
        case .toMinutes:
            if TypedAnswer.isBlank(minutes) { return .unanswered }
            return TypedAnswer.wholeNumber(minutes) == answer.minutes ? .correct : .incorrect
        case .toHoursAndMinutes:
            if TypedAnswer.isBlank(hours) && TypedAnswer.isBlank(minutes) { return .unanswered }
            // "2 hours and" with the minutes left empty means no minutes over.
            let typedHours = TypedAnswer.isBlank(hours) ? 0 : TypedAnswer.wholeNumber(hours)
            let typedMinutes = TypedAnswer.isBlank(minutes) ? 0 : TypedAnswer.wholeNumber(minutes)
            return typedHours == answer.hours && typedMinutes == answer.minutes ? .correct : .incorrect
        case .timeAfter:
            if TypedAnswer.isBlank(hours) && TypedAnswer.isBlank(minutes) { return .unanswered }
            // "07" and "7" are the same hour; "24" is not a 24-hour clock time.
            guard let typedHours = TypedAnswer.wholeNumber(hours), let typedMinutes = TypedAnswer.wholeNumber(minutes),
                  (0...23).contains(typedHours), (0...59).contains(typedMinutes) else {
                return .incorrect
            }
            return typedHours == answer.hours && typedMinutes == answer.minutes ? .correct : .incorrect
        case let .readClock(hour, minute):
            if TypedAnswer.isBlank(hours) && TypedAnswer.isBlank(minutes) { return .unanswered }
            return ClockMaths.isCorrectReading(hours: hours, minutes: minutes, hour24: hour, minute: minute)
                ? .correct : .incorrect
        }
    }
}

struct Year3TimeView: View {
    @State private var current = Year3TimeQuestion.random()
    @State var hoursanswer: String = ""
    @State var minutesanswer: String = ""
    @State var responseMessage: String = ""
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var progress = QuestionProgress()
    @State private var clockSize: CGFloat = 300
    /// Where the hands of the clock to set point. They belong to this screen, so each question and each visit
    /// starts with the clock at 12:00.
    @State private var clockHour = 0
    @State private var clockMinute = 0

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack {

                switch current.kind {
                case .toMinutes:
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .padding()
                    
                    WorkingOutView(canvasView: $canvasView)
                    
                    HStack {
                        TextField(answerBox: "Minutes", text: $minutesanswer)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }
                        
                        Text("Minutes")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                            .padding()
                    }
                case .toHoursAndMinutes:
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .padding()
                    
                    WorkingOutView(canvasView: $canvasView)
                    
                    HStack {
                        VStack{
                            TextField(answerBox: "Hours", text: $hoursanswer)
                                .answerBoxMargin()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(UIScreen.main.bounds.width * 0.02)
                                .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .multilineTextAlignment(.center)
                                .answerKeyboard(.numberPad)
                                .onSubmit {
                                    checkAnswer()
                                    hideKeyboard()
                                }
                            
                            Text("Hours")
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .fontWeight(.bold)
                                .foregroundStyle(.onBackground)
                                .padding()
                        }
                        
                        Text("and")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                            .padding()
                        
                        VStack{
                            TextField(answerBox: "Minutes", text: $minutesanswer)
                                .answerBoxMargin()
                                .background(Color.white)
                                .foregroundColor(.black)
                                .cornerRadius(UIScreen.main.bounds.width * 0.02)
                                .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .multilineTextAlignment(.center)
                                .answerKeyboard(.numberPad)
                                .onSubmit {
                                    checkAnswer()
                                    hideKeyboard()
                                }
                            
                            Text("Minutes")
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .fontWeight(.bold)
                                .foregroundStyle(.onBackground)
                                .padding()
                        }
                    }
                case .timeAfter:
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Text(current.instructions ?? "")
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .multilineTextAlignment(.center)
                        .padding()

                    WorkingOutView(canvasView: $canvasView)
                    
                    HStack {
                        TextField(answerBox: "Hours", text: $hoursanswer)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }
                        
                        Text(":")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                            .padding()
                            .accessibilityHidden(true)
                        
                        TextField(answerBox: "Minutes", text: $minutesanswer)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }
                    }
                case let .readClock(hour, minute):
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .padding()

                    Text(current.instructions ?? "")
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .multilineTextAlignment(.center)
                        .padding()

                    // AM or PM goes beside the clock, or under it when the reader's text is too big for both to fit
                    // across the screen. Beside it, the clock keeps the room it has at its usual size, so a clock
                    // drawn smaller to fit the screen's height doesn't change which way round they go.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            clockToRead(hour: hour, minute: minute)
                                .frame(minWidth: Self.usualClockSize)

                            meridiem(of: hour)
                        }

                        VStack(spacing: 0) {
                            clockToRead(hour: hour, minute: minute)

                            meridiem(of: hour)
                        }
                    }

                    HStack {
                        TextField(answerBox: "Hours", text: $hoursanswer)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }

                        Text(":")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                            .padding()
                            .accessibilityHidden(true)
                        
                        TextField(answerBox: "Minutes", text: $minutesanswer)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }
                    }
                case .setClock:
                    Text(current.text)
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .fontWeight(.bold)
                        .foregroundStyle(.onBackground)
                        .padding()

                    InteractiveClockView(
                        minute: $clockMinute,
                        hour: $clockHour
                    )
                    .frame(width: clockSize, height: clockSize)
                }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            // On the smallest iPhones, and with large text, a clock is too tall to fit above the answer boxes and
            // Enter, so it's drawn a little smaller there.
            .fitOnScreen(by: $clockSize, usual: Self.usualClockSize, minimum: 200,
                         paused: showMessage || !showsAClock)
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private static let usualClockSize: CGFloat = 300

    private var showsAClock: Bool {
        switch current.kind {
        case .readClock, .setClock: return true
        default: return false
        }
    }

    private func clockToRead(hour: Int, minute: Int) -> some View {
        StationaryClockView(
            minute: .constant(Double(minute)),
            hour: .constant(Double(hour)),
            rotationCount: .constant(0)
        )
        .frame(width: clockSize, height: clockSize)
    }

    private func meridiem(of hour: Int) -> some View {
        Text(ClockMaths.isPM(hour) ? "PM" : "AM")
            .scaledFont(size: UIScreen.main.bounds.width * 0.05)
            .fontWeight(.bold)
            .foregroundStyle(.onBackground)
            .padding()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(hours: hoursanswer, minutes: minutesanswer,
                                clockHour: clockHour, clockMinute: clockMinute) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        current = Year3TimeQuestion.random()
        hoursanswer = ""
        minutesanswer = ""
        responseMessage = ""
        clockHour = 0
        clockMinute = 0
        canvasView.drawing = PKDrawing()
        progress.reset()
    }
}

/// The white face both clocks are drawn on, with its hour and minute marks and its numbers. The hands go on top.
struct ClockFace: View {
    let radius: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = ClockFaceLayout(radius: radius,
                                     textSize: ScaledFont.pointSize(17, maximum: .greatestFiniteMagnitude, for: dynamicTypeSize))
        ZStack {
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black, lineWidth: 4))

            ForEach(0..<12) { tick in
                let angle = Double(tick) * 30
                let number = tick == 0 ? 12 : tick
                ZStack {
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: 3, height: ClockFaceLayout.hourMarkLength)
                        .offset(y: -(radius - ClockFaceLayout.hourMarkInset - ClockFaceLayout.hourMarkLength / 2))
                        .rotationEffect(.degrees(angle - 90))

                    Text("\(number)")
                        .font(.system(size: layout.numeralSize))
                        // Black, as on a real clock: the face is white in dark mode too.
                        .foregroundColor(.black)
                        .position(layout.centre(ofNumeral: number))
                }
            }

            ForEach(0..<60) { tick in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 1, height: 10)
                    .offset(y: -radius + 10)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }
        }
    }
}

/// How big a clock face's numbers are and where they go. They grow with the reader's text size as far as the face has
/// room, but always stay inside the hour marks: at the largest text sizes they used to be drawn over them.
struct ClockFaceLayout {
    /// The hour marks are 20 points long and end 10 points in from the rim.
    static let hourMarkLength: CGFloat = 20
    static let hourMarkInset: CGFloat = 10
    /// The clear space between the numbers and the inner ends of the hour marks.
    static let gap: CGFloat = 4
    /// Numbers bigger than a tenth of the face's width crowd each other and the hands.
    static let largestNumeralSize: CGFloat = 0.2

    let radius: CGFloat
    let numeralSize: CGFloat
    /// From the middle of the face to the middle of each number.
    let numeralDistance: CGFloat

    /// `textSize` is the size the reader's text settings would make the numbers: 17 points at the usual setting.
    init(radius: CGFloat, textSize: CGFloat) {
        self.radius = radius
        let size = min(textSize, radius * Self.largestNumeralSize)
        numeralSize = size
        // Every number fits in a circle as wide as the corners of the widest one, so that circle is kept inside the
        // hour marks, wherever round the face it is.
        let widest = (1...12).map { Self.numeralBox($0, size: size) }.max { $0.width < $1.width } ?? .zero
        let reach = (widest.width * widest.width + widest.height * widest.height).squareRoot() / 2
        numeralDistance = Self.hourMarksInnerEnd(radius: radius) - Self.gap - reach
    }

    /// How far the inner ends of the hour marks are from the middle of the face.
    static func hourMarksInnerEnd(radius: CGFloat) -> CGFloat {
        radius - hourMarkInset - hourMarkLength
    }

    /// The width of `number` and the height of its digits, which are centred where the number is placed.
    static func numeralBox(_ number: Int, size: CGFloat) -> CGSize {
        let font = UIFont.systemFont(ofSize: size)
        return CGSize(width: ("\(number)" as NSString).size(withAttributes: [.font: font]).width, height: font.capHeight)
    }

    /// Where the middle of `number` (1...12) goes, measured from the face's top left corner.
    func centre(ofNumeral number: Int) -> CGPoint {
        let angle = (Double(number) * 30 - 90) * .pi / 180
        return CGPoint(x: radius + numeralDistance * cos(angle), y: radius + numeralDistance * sin(angle))
    }
}

struct StationaryClockView: View {
    @Binding var minute: Double
    @Binding var hour: Double
    @Binding var rotationCount: Int
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            ZStack {
                ClockFace(radius: radius)

                Rectangle()
                    .fill(Color.black)
                    .frame(width: 6, height: radius / 2.5)
                    .cornerRadius(3)
                    .offset(y: (-radius / 4.5))
                    .rotationEffect(.degrees(ClockMaths.hourHandDegrees(hour: hour, minute: minute)))
                    .shadow(radius: 2)

                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3, height: radius / 1.5)
                    .cornerRadius(2)
                    .offset(y: -size / 6)
                    .rotationEffect(.degrees(ClockMaths.minuteHandDegrees(minute: minute)))

                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clock")
        .accessibilityValue(ClockMaths.handPositions(hour: Int(hour), minute: Int(minute)))
        .accessibilityAddTraits(.isImage)
    }
}

/// Clock arithmetic shared by the Year 3 Time clocks, kept free of view state so it can be unit tested.
/// Hours passed in as `hour24` are 0...23; the analogue clock itself only knows 0...11 (0 is 12 o'clock).
enum ClockMaths {
    /// 0 → 12 (12 AM), 1...12 unchanged, 13...23 → 1...11.
    static func twelveHour(_ hour24: Int) -> Int {
        let hour = ((hour24 % 12) + 12) % 12
        return hour == 0 ? 12 : hour
    }

    static func isPM(_ hour24: Int) -> Bool {
        ((hour24 % 24) + 24) % 24 >= 12
    }

    /// Reading a clock that is shown with an AM/PM label is answered in 12-hour time,
    /// so 3:30 PM is "3" and "30", and midnight/noon are both "12". Only digits count, so "+3" isn't 3.
    static func isCorrectReading(hours: String, minutes: String, hour24: Int, minute: Int) -> Bool {
        guard let userHour = TypedAnswer.wholeNumber(hours),
              let userMinute = TypedAnswer.wholeNumber(minutes),
              (1...12).contains(userHour), (0...59).contains(userMinute) else {
            return false
        }
        return userHour == twelveHour(hour24) && userMinute == minute
    }

    /// An analogue face cannot show AM/PM, so a 24-hour target is matched modulo 12 hours.
    static func isCorrectlySet(clockHour: Int, clockMinute: Int, hour24: Int, minute: Int) -> Bool {
        ((clockHour % 12) + 12) % 12 == ((hour24 % 12) + 12) % 12 && clockMinute == minute
    }

    /// Where the hands point, for VoiceOver, without saying the time: "The short hour hand is between the 3 and the 4.
    /// The long minute hand is 2 small marks past the 5." `hour` is 0...23 or 0...11.
    static func handPositions(hour: Int, minute: Int) -> String {
        let hourNumber = twelveHour(hour)
        let hourHand = minute == 0
            ? "The short hour hand points at the \(hourNumber)."
            : "The short hour hand is between the \(hourNumber) and the \(hourNumber % 12 + 1)."
        let number = minute / 5 == 0 ? 12 : minute / 5
        let marks = minute % 5
        let minuteHand = marks == 0
            ? "The long minute hand points at the \(number)."
            : "The long minute hand is \(marks) small \(marks == 1 ? "mark" : "marks") past the \(number)."
        return hourHand + " " + minuteHand
    }

    /// The clock moved on by `minutes`, which can be negative. Hours wrap within 0...11.
    static func turning(hour: Int, minute: Int, by minutes: Int) -> (hour: Int, minute: Int) {
        let total = (((hour * 60 + minute + minutes) % 720) + 720) % 720
        return (total / 60, total % 60)
    }

    /// Degrees clockwise from 12 o'clock.
    static func hourHandDegrees(hour: Double, minute: Double) -> Double {
        hour.truncatingRemainder(dividingBy: 12) * 30 + minute * 0.5
    }

    /// Degrees clockwise from 12 o'clock.
    static func minuteHandDegrees(minute: Double) -> Double {
        minute * 6
    }

    /// The minute (0...59) the minute hand would point at to reach `point`, measured clockwise from 12 o'clock
    /// in a y-down coordinate space. Returns nil inside `deadZone`, where the direction is meaningless.
    static func minute(at point: CGPoint, center: CGPoint, deadZone: CGFloat = 0) -> Int? {
        let dx = Double(point.x - center.x)
        let dy = Double(point.y - center.y)
        guard (dx * dx + dy * dy).squareRoot() > Double(deadZone) else { return nil }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return Int((degrees / 6).rounded()) % 60
    }

    /// Turns the minute hand to `target` along the shorter way round, carrying the hour hand with it as a
    /// geared clock does: passing 12 forwards adds an hour and backwards removes one. Hours wrap within 0...11.
    static func movingMinuteHand(hour: Int, minute: Int, to target: Int) -> (hour: Int, minute: Int) {
        var delta = (target - minute) % 60
        if delta > 30 {
            delta -= 60
        } else if delta <= -30 {
            delta += 60
        }
        let total = (((hour * 60 + minute + delta) % 720) + 720) % 720
        return (total / 60, total % 60)
    }
}

struct InteractiveClockView: View {
    /// 0...59
    @Binding var minute: Int
    /// 0...11, where 0 is 12 o'clock
    @Binding var hour: Int

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            ZStack {
                ClockFace(radius: radius)

                Rectangle()
                    .fill(Color.black)
                    .frame(width: 6, height: radius / 2.5)
                    .cornerRadius(3)
                    .offset(y: (-radius / 4.5))
                    .rotationEffect(.degrees(ClockMaths.hourHandDegrees(hour: Double(hour), minute: Double(minute))))
                    .shadow(radius: 2)
                
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3, height: size / 3)
                    .offset(y: -size / 6)
                    .rotationEffect(.degrees(ClockMaths.minuteHandDegrees(minute: Double(minute))))

                Circle()
                    .fill(Color.black)
                    .frame(width: 10, height: 10)
            }
            .frame(width: size, height: size)
            // The whole face is the drag target, so touches are measured in the face's own
            // coordinates and the centre of rotation is (radius, radius).
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        moveMinuteHand(toward: value.location, center: CGPoint(x: radius, y: radius), radius: radius)
                    }
            )
        }
        // VoiceOver can't drag the hands, so swiping up or down turns the minute hand a minute at a time, carrying the
        // hour hand as dragging does, and the actions turn it 5 minutes or an hour.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clock to set")
        .accessibilityValue(ClockMaths.handPositions(hour: hour, minute: minute))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: turn(by: 1)
            case .decrement: turn(by: -1)
            @unknown default: break
            }
        }
        // SwiftUI gives VoiceOver these actions last first, so they're declared in reverse to be offered as
        // Forward 5 minutes, Back 5 minutes, Forward 1 hour, Back 1 hour.
        .accessibilityAction(named: "Back 1 hour") { turn(by: -60) }
        .accessibilityAction(named: "Forward 1 hour") { turn(by: 60) }
        .accessibilityAction(named: "Back 5 minutes") { turn(by: -5) }
        .accessibilityAction(named: "Forward 5 minutes") { turn(by: 5) }
    }

    private func turn(by minutes: Int) {
        let turned = ClockMaths.turning(hour: hour, minute: minute, by: minutes)
        hour = turned.hour
        minute = turned.minute
    }

    private func moveMinuteHand(toward location: CGPoint, center: CGPoint, radius: CGFloat) {
        guard let target = ClockMaths.minute(at: location, center: center, deadZone: radius * 0.15) else { return }
        let moved = ClockMaths.movingMinuteHand(hour: hour, minute: minute, to: target)
        if moved.hour != hour { hour = moved.hour }
        if moved.minute != minute { minute = moved.minute }
    }
}

struct Year4View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 4")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.decimals)) {
                    Text("Decimals")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.geometry)) {
                    Text("Geometry")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.money)) {
                    Text("Money")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

/// One Year 4 Decimals question. Numbers are kept as whole tenths, so 4.7 is 47, and answers are
/// compared exactly, so 2.54 is no longer accepted for 2.5 and nothing depends on Double rounding.
struct Year4DecimalsQuestion: Equatable {
    /// 0.0 to 10.0 in tenths.
    static let tenths = 0...100
    static let multipliers = 1...10

    enum Kind: Equatable {
        case add, subtract, multiply
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
        /// "1,500" could mean 1500 or 1.5, so it isn't marked either way.
        case ambiguousComma
    }

    var kind: Kind
    /// In tenths. For subtraction the first number is never smaller than the second.
    var first: Int
    /// In tenths.
    var second: Int
    var multiplier: Int

    static func random() -> Year4DecimalsQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year4DecimalsQuestion {
        let type = Int.random(in: 1...3, using: &generator) // 1: Add, 2: Subtract, 3: Multiply
        let kind: Kind = type == 1 ? .add : type == 2 ? .subtract : .multiply
        var first = Int.random(in: tenths, using: &generator)
        var second = Int.random(in: tenths, using: &generator)
        if kind == .subtract && second > first {
            swap(&first, &second)
        }
        return Year4DecimalsQuestion(kind: kind, first: first, second: second,
                                     multiplier: Int.random(in: multipliers, using: &generator))
    }

    /// Always one decimal place, so 40 is "4.0".
    static func decimal(_ tenths: Int) -> String {
        "\(tenths / 10).\(tenths % 10)"
    }

    var text: String {
        switch kind {
        case .add:
            return "What is \(Self.decimal(first)) + \(Self.decimal(second))?"
        case .subtract:
            return "What is \(Self.decimal(first)) - \(Self.decimal(second))?"
        case .multiply:
            return "What is \(Self.decimal(first)) × \(multiplier)?"
        }
    }

    /// "times" and "minus", rather than leaving VoiceOver to name the "×" sign or skip the "-".
    var spokenText: String {
        switch kind {
        case .add:
            return "What is \(Self.decimal(first)) plus \(Self.decimal(second))?"
        case .subtract:
            return "What is \(Self.decimal(first)) minus \(Self.decimal(second))?"
        case .multiply:
            return "What is \(Self.decimal(first)) times \(multiplier)?"
        }
    }

    var answerInTenths: Int {
        switch kind {
        case .add:
            return first + second
        case .subtract:
            return first - second
        case .multiply:
            return first * multiplier
        }
    }

    /// 2.5, 2.50, 2,5 and .5 style answers are all read exactly. The question doesn't ask for
    /// rounding, so none is applied.
    func evaluate(_ text: String) -> Outcome {
        switch TypedAnswer.decimalEntry(text) {
        case .blank:
            return .unanswered
        case .ambiguousComma:
            return .ambiguousComma
        case .notANumber:
            return .incorrect
        case let .number(numerator, denominator, _):
            return TypedAnswer.fractionsAreEqual(numerator, denominator, answerInTenths, 10) ? .correct : .incorrect
        }
    }
}

struct Year4DecimalsView: View {
    @State private var current = Year4DecimalsQuestion.random()
    @State var answerString: String = ""
    @State var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    @State private var canvasView = PKCanvasView()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack{
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack (spacing: 20){
                Text(current.text)
                    .accessibilityLabel(current.spokenText)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                    .padding()

                WorkingOutView(canvasView: $canvasView)
                
                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.decimalPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }
                
                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .ambiguousComma:
            responseMessage = "Use a decimal point."
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        current = Year4DecimalsQuestion.random()
        answerString = ""
        responseMessage = ""
        canvasView.drawing = PKDrawing()
        progress.reset()
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

/// One Year 4 Geometry question. Generation and marking live outside the view so the
/// mathematical invariants (every shape can exist, every question has an answer) can be unit tested.
struct Year4GeometryQuestion: Equatable {
    static let units = ["mm", "cm", "m", "km"]
    static let sideLengths = 2...12
    /// Angles close to 90° can't be told apart from a right angle by eye, and tiny or nearly straight
    /// angles are hard to see, so the drawn angles keep clear of both.
    static let acuteAngles = 10...75
    static let obtuseAngles = 105...170
    static let angles = Array(acuteAngles) + [90] + Array(obtuseAngles)

    enum Outcome: Equatable {
        case correct, wrongUnit, incorrect, unanswered
    }

    /// 1: perimeter, 2: area, 3: angle type.
    var question: Int
    /// 3: triangle, 4: rectangle/square, 5: pentagon.
    var shapeType: Int
    /// Side lengths in drawing order. A rectangle is stored as [width, height, width, height].
    var sides: [Int]
    var angleMeasure: Int
    var unitType: String

    static func random() -> Year4GeometryQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year4GeometryQuestion {
        var question = Int.random(in: 1...3, using: &generator) // 1: Perimeter, 2: Area, 3: Angle
        let shapeType = Int.random(in: 3...5, using: &generator) // 3: Triangle, 4: Rectangle/Square, 5: Pentagon

        // Prevent area questions for non-quadrilaterals
        if question == 2 && shapeType != 4 {
            question = 1 // Force perimeter if shape isn't a quadrilateral
        }

        return Year4GeometryQuestion(
            question: question,
            shapeType: shapeType,
            sides: randomSides(shapeType: shapeType, using: &generator),
            angleMeasure: randomAngle(using: &generator),
            unitType: units.randomElement(using: &generator)!
        )
    }

    /// The type is chosen first so acute, right and obtuse angles come up equally often. Picking a whole
    /// number of degrees from 1 to 179 almost never gave a right angle.
    static func randomAngle<G: RandomNumberGenerator>(using generator: inout G) -> Int {
        switch Int.random(in: 0..<3, using: &generator) {
        case 0: return Int.random(in: acuteAngles, using: &generator)
        case 1: return 90
        default: return Int.random(in: obtuseAngles, using: &generator)
        }
    }

    /// Redraws until the sides can close up into a real shape, so impossible triangles such as
    /// 2, 3, 12 are never offered.
    static func randomSides<G: RandomNumberGenerator>(shapeType: Int, using generator: inout G) -> [Int] {
        if shapeType == 4 {
            let width = Int.random(in: sideLengths, using: &generator)
            let height = Int.random(in: sideLengths, using: &generator)
            return [width, height, width, height]
        }
        while true {
            let sides = (0..<shapeType).map { _ in Int.random(in: sideLengths, using: &generator) }
            if isConstructible(sides) {
                return sides
            }
        }
    }

    static func isConstructible(_ sides: [Int]) -> Bool {
        ShapeGeometry.isConstructible(sides.map(Double.init))
    }

    var perimeter: Int {
        sides.reduce(0, +)
    }

    /// Area is only asked about rectangles.
    var area: Int? {
        shapeType == 4 ? sides[0] * sides[1] : nil
    }

    var angleType: String {
        angleMeasure < 90 ? "acute" : angleMeasure == 90 ? "right" : "obtuse"
    }

    /// The unit a numeric answer must be given in, or nil for the angle question.
    var correctUnit: String? {
        switch question {
        case 1: return unitType
        case 2: return unitType + "²"
        default: return nil
        }
    }

    static let unitNames = ["mm": ("millimetre", "millimetres"), "cm": ("centimetre", "centimetres"),
                            "m": ("metre", "metres"), "km": ("kilometre", "kilometres")]

    /// What the picture shows, for VoiceOver: the shape and its labelled sides, or which way the angle's second arm
    /// points. A sighted player isn't told the angle in degrees, so neither is VoiceOver.
    var figureDescription: String {
        guard question == 1 || question == 2 else {
            let direction = angleMeasure < 90 ? "up and to the right" : angleMeasure == 90 ? "straight up" : "up and to the left"
            return "An angle. One arm points right, and the other points \(direction)."
        }
        let name: String
        switch shapeType {
        case 3: name = "A triangle"
        case 4: name = sides[0] == sides[1] ? "A square" : "A rectangle"
        case 5: name = "A pentagon"
        default: name = "A shape"
        }
        let lengths = sides.map { side -> String in
            guard let names = Self.unitNames[unitType] else { return "\(side) \(unitType)" }
            return "\(side) \(side == 1 ? names.0 : names.1)"
        }
        return "\(name) with sides of " + lengths.dropLast().joined(separator: ", ") + " and " + lengths.last! + "."
    }

    /// Reads "acute", "Acute angle", "right-angled" or "obtuse." as the angle type it names, or nil.
    static func angleTypeNamed(_ answer: String) -> String? {
        var words = answer.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!").union(.whitespacesAndNewlines))
            .split(separator: " ")
            .map(String.init)
        if words.count == 2, words[1] == "angle" || words[1] == "angled" {
            words.removeLast()
        }
        guard words.count == 1, ["acute", "right", "obtuse"].contains(words[0]) else { return nil }
        return words[0]
    }

    /// Nothing typed is unanswered. Numbers are digits only, as everywhere else, so "+12" isn't 12.
    func evaluate(answer: String, unit: String) -> Outcome {
        guard !TypedAnswer.isBlank(answer) else { return .unanswered }
        let trimmedInput = answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard question == 1 || question == 2 else {
            return Self.angleTypeNamed(trimmedInput) == angleType ? .correct : .incorrect
        }

        let expected = question == 1 ? perimeter : area
        guard let value = TypedAnswer.wholeNumber(answer), value == expected else {
            return .incorrect
        }
        return unit == correctUnit ? .correct : .wrongUnit
    }
}

struct Year4GeometryView: View {
    @State private var current = Year4GeometryQuestion.random()
    @State var answerString: String = ""
    @State var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData
    @State var possibleUnits: [String] = Year4GeometryQuestion.units
    @State var userUnit: String = ""
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                .environmentObject(gameData)
                .onAppear {
                    // A question that's already moving on gets its next question from the pending reset,
                    // so appearing again (for example after the Skip ad) can't move on a second time.
                    guard !progress.isAdvancing else { return }
                    resetQuestion()
                }

            VStack(spacing: 15) {
                Text(questionText())
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)

                if current.question == 3 {
                    AngleDrawingView(angle: current.angleMeasure)
                        .stroke(.linesOnBackground, lineWidth: 2)
                        .frame(width: UIScreen.main.bounds.width * 0.4, height: UIScreen.main.bounds.width * 0.4)
                        .accessibilityElement()
                        .accessibilityLabel(current.figureDescription)
                        .accessibilityAddTraits(.isImage)
                } else {
                    HStack {
                        Spacer()
                        ShapeView(sides: current.shapeType, labels: current.sides, unitType: current.unitType)
                            .frame(width: UIScreen.main.bounds.width * 0.4, height: UIScreen.main.bounds.width * 0.4)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(current.figureDescription)
                            .accessibilityAddTraits(.isImage)
                        Spacer()
                    }
                }

                if current.question == 3 {
                    Text("Is this angle: Acute, Right or Obtuse?")
                        .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                        .foregroundStyle(.onBackground)
                        .fontWeight(.bold)
                }

                HStack {
                    TextField(answerBox: "Answer", text: $answerString)
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .multilineTextAlignment(.center)
                        .answerKeyboard(current.question == 3 ? .default : .numberPad)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }

                    if current.question == 1 {
                        Picker("Pick a unit", selection: $userUnit) {
                            // Placeholder tagged "" so the wheel never shows a unit that isn't actually selected
                            Text("Unit")
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                .tag("")
                            ForEach(possibleUnits, id: \.self) { option in
                                Text(option)
                                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                    .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                    .tag(option)
                            }
                        }
                        .pickerStyle(.wheel)
                        .colorSchemeForBackground()
                        .frame(width: UIScreen.main.bounds.width * 0.2,
                               height: UIScreen.main.bounds.width * 0.3)
                    } else if current.question == 2 && current.shapeType == 4 {
                        Picker("Pick a unit", selection: $userUnit) {
                            Text("Unit")
                                .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                .tag("")
                            ForEach(possibleUnits, id: \.self) { option in
                                Text(option + "²")
                                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                                    .padding(.vertical, UIScreen.main.bounds.height * 0.02)
                                    .tag(option + "²")
                            }
                        }
                        .pickerStyle(.wheel)
                        .colorSchemeForBackground()
                        .frame(width: UIScreen.main.bounds.width * 0.2,
                               height: UIScreen.main.bounds.width * 0.3)
                    }
                }
                .padding(.vertical, 10)

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func questionText() -> String {
        switch current.question {
        case 1: return "Find the perimeter of the shape below"
        case 2: return "Calculate the area of the shape below"
        default: return "Identify this angle type."
        }
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answer: answerString, unit: userUnit) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { resetQuestion() }
        case .wrongUnit:
            responseMessage = "Correct number, but wrong unit!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func resetQuestion() {
        current = Year4GeometryQuestion.random()
        answerString = ""
        userUnit = ""
        responseMessage = ""
        showMessage = false
        progress.reset()
    }
    
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

struct ShapeView: View {
    let sides: Int
    let labels: [Int]
    let unitType: String

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 3
            let drawingArea = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size / 6, dy: size / 6)
            // Drawn to scale from the side lengths. The regular polygon is only a fallback for lengths
            // that can't form a shape, which Year4GeometryQuestion never generates.
            let points = ShapeGeometry.polygon(sides: labels.map(Double.init), fittingIn: drawingArea)
                ?? calculatePolygonPoints(center: center, radius: radius, sides: sides)
            let labelPositions = ShapeGeometry.labelPositions(for: points, offset: 20)

            Path { path in
                for (index, point) in points.enumerated() {
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.closeSubpath()
            }
            .stroke(.linesOnBackground, lineWidth: 2)
            .fill(.linesOnBackground)
            .overlay(
                ForEach(0..<sides, id: \.self) { i in
                    if i < labels.count && i < labelPositions.count {
                        Text("\(labels[i]) \(unitType)")
                            .foregroundStyle(.onBackground)
                            .font(.system(size: max(UIScreen.main.bounds.width * 0.02, 12)))
                            .bold()
                            .position(labelPositions[i])
                    }
                }
            )
        }
    }
}

/// Geometry for drawing Year 4 shapes to scale, kept free of view state so it can be unit tested.
enum ShapeGeometry {
    /// A polygon can only close up if its longest side is shorter than all the other sides combined.
    static func isConstructible(_ sides: [Double]) -> Bool {
        guard sides.count >= 3, sides.allSatisfy({ $0 > 0 }), let longest = sides.max() else { return false }
        return longest < sides.reduce(0, +) - longest
    }

    /// Vertices of the convex polygon with these side lengths, in order, inscribed in a circle centred on
    /// the origin; side i runs from vertex i to vertex i + 1. Requiring the polygon to be cyclic makes it
    /// unique, which matters for pentagons, whose side lengths alone don't fix their shape.
    static func cyclicPolygon(sides: [Double]) -> [CGPoint]? {
        guard isConstructible(sides), let longest = sides.max(),
              let longestIndex = sides.firstIndex(of: longest) else { return nil }

        func centralAngle(_ side: Double, _ radius: Double) -> Double {
            2 * asin(min(1, side / (2 * radius)))
        }
        func minorArcs(_ radius: Double) -> Double {
            sides.reduce(0) { $0 + centralAngle($1, radius) }
        }

        // If the sides' minor arcs can't go all the way round even the smallest possible circle, the
        // centre lies outside the polygon and the longest side spans the major arc instead.
        let smallestRadius = longest / 2
        let centreInside = minorArcs(smallestRadius) >= 2 * .pi

        // Positive while the radius is too small for the sides to close up, negative once it is too large.
        func excess(_ radius: Double) -> Double {
            centreInside
                ? minorArcs(radius) - 2 * .pi
                : 2 * centralAngle(longest, radius) - minorArcs(radius)
        }

        var low = smallestRadius
        var high = longest
        var doublings = 0
        while excess(high) > 0 {
            high *= 2
            doublings += 1
            if doublings > 60 { return nil }
        }
        for _ in 0..<200 {
            let mid = (low + high) / 2
            if excess(mid) > 0 { low = mid } else { high = mid }
        }
        let radius = (low + high) / 2

        var points: [CGPoint] = []
        var angle = 0.0
        for (index, side) in sides.enumerated() {
            points.append(CGPoint(x: radius * cos(angle), y: radius * sin(angle)))
            let step = centralAngle(side, radius)
            angle += (index == longestIndex && !centreInside) ? 2 * .pi - step : step
        }
        return points
    }

    /// The to-scale polygon turned so its longest side is a horizontal base with the shape above it,
    /// then scaled uniformly and centred in `rect`. Nil if the side lengths can't form a polygon.
    static func polygon(sides: [Double], fittingIn rect: CGRect) -> [CGPoint]? {
        guard var points = cyclicPolygon(sides: sides), let longest = sides.max(),
              let base = sides.firstIndex(of: longest) else { return nil }

        let start = points[base]
        let end = points[(base + 1) % points.count]
        let baseAngle = atan2(Double(end.y - start.y), Double(end.x - start.x))
        points = points.map { rotate($0, by: -baseAngle) }
        // Screen y grows downwards, so the base is at the bottom when the rest of the shape has smaller y.
        if centre(of: points).y > points[base].y {
            points = points.map { rotate($0, by: .pi) }
        }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX > minX, maxY > minY else { return nil }
        let scale = min(rect.width / (maxX - minX), rect.height / (maxY - minY))
        return points.map {
            CGPoint(x: rect.midX + ($0.x - (minX + maxX) / 2) * scale,
                    y: rect.midY + ($0.y - (minY + maxY) / 2) * scale)
        }
    }

    /// A point `offset` beyond the midpoint of each side, along that side's outward normal.
    /// Label i belongs to the side from vertex i to vertex i + 1. Assumes a convex polygon.
    static func labelPositions(for points: [CGPoint], offset: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let middle = centre(of: points)
        return points.indices.map { i in
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { return midpoint }
            var normal = CGPoint(x: (b.y - a.y) / length, y: -(b.x - a.x) / length)
            if normal.x * (midpoint.x - middle.x) + normal.y * (midpoint.y - middle.y) < 0 {
                normal = CGPoint(x: -normal.x, y: -normal.y)
            }
            return CGPoint(x: midpoint.x + normal.x * offset, y: midpoint.y + normal.y * offset)
        }
    }

    private static func rotate(_ point: CGPoint, by angle: Double) -> CGPoint {
        CGPoint(x: point.x * cos(angle) - point.y * sin(angle),
                y: point.x * sin(angle) + point.y * cos(angle))
    }

    private static func centre(of points: [CGPoint]) -> CGPoint {
        let count = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    }
}

func calculatePolygonPoints(center: CGPoint, radius: CGFloat, sides: Int) -> [CGPoint] {
    let angleStep = 2 * .pi / CGFloat(sides)
    var points: [CGPoint] = []

    let startAngle: CGFloat = sides.isMultiple(of: 2) ? -(.pi / 4) : -(.pi / 2)

    for i in 0..<sides {
        let angle = startAngle + angleStep * CGFloat(i)
        let point = CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
        points.append(point)
    }

    return points
}

struct AngleDrawingView: Shape {
    var angle: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 20

        path.move(to: center)
        
        let basePoint = CGPoint(x: center.x + radius, y: center.y)
        path.addLine(to: basePoint)

        let angleRad = CGFloat(angle) * .pi / 180
        let x = center.x + cos(angleRad) * radius
        let y = center.y - sin(angleRad) * radius
        path.move(to: center)
        path.addLine(to: CGPoint(x: x, y: y))

        return path
    }
}

/// One Year 4 Money question. Amounts are kept in whole pence so nothing depends on Double rounding,
/// and a right amount written the wrong way (such as £2.5) is told apart from a wrong amount.
struct Year4MoneyQuestion: Equatable {
    /// £0.00 to £10.00.
    static let pence = 0...1000
    /// 1p to £10.00. Converting 0p isn't a real question.
    static let penceToConvert = 1...1000

    enum Kind: Equatable {
        case add, subtract, convert
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
        /// The right amount, but not written as pounds and pence, such as 2.5 or 2.500 for £2.50.
        case needsTwoDecimalPlaces
        /// "1,500" could mean 1500 or 1.5, so it isn't marked either way.
        case ambiguousComma
        case notANumber
    }

    var kind: Kind
    /// In pence. For subtraction the first amount is never smaller than the second.
    var first: Int
    /// In pence.
    var second: Int
    /// The pennies to convert to pounds.
    var pennies: Int

    static func random() -> Year4MoneyQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year4MoneyQuestion {
        let type = Int.random(in: 1...3, using: &generator) // 1: Add, 2: Subtract, 3: Convert
        let kind: Kind = type == 1 ? .add : type == 2 ? .subtract : .convert
        var first = Int.random(in: pence, using: &generator)
        var second = Int.random(in: pence, using: &generator)
        if kind == .subtract && second > first {
            swap(&first, &second)
        }
        return Year4MoneyQuestion(kind: kind, first: first, second: second,
                                  pennies: Int.random(in: penceToConvert, using: &generator))
    }

    /// Pounds and pence without the £ sign, so 250 is "2.50".
    static func pounds(_ pence: Int) -> String {
        "\(pence / 100)." + (pence % 100 < 10 ? "0" : "") + "\(pence % 100)"
    }

    var text: String {
        switch kind {
        case .add:
            return "Add £\(Self.pounds(first)) and £\(Self.pounds(second))"
        case .subtract:
            return "Subtract £\(Self.pounds(second)) from £\(Self.pounds(first))"
        case .convert:
            // "7p", as on price labels, rather than "7 pennies", which also gave "1 pennies".
            return "Convert \(pennies)p to pounds"
        }
    }

    var answerInPence: Int {
        switch kind {
        case .add:
            return first + second
        case .subtract:
            return first - second
        case .convert:
            return pennies
        }
    }

    /// Pounds and pence are written with two decimal places (£2.50), or with none for whole pounds
    /// (£5). A £ sign typed into the box is ignored.
    func evaluate(_ text: String) -> Outcome {
        var typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.hasPrefix("£") {
            typed.removeFirst()
        }

        switch TypedAnswer.decimalEntry(typed) {
        case .blank:
            return .unanswered
        case .ambiguousComma:
            return .ambiguousComma
        case .notANumber:
            return .notANumber
        case let .number(numerator, denominator, decimalPlaces):
            guard TypedAnswer.fractionsAreEqual(numerator, denominator, answerInPence, 100) else {
                return .incorrect
            }
            if decimalPlaces == 2 || (decimalPlaces == 0 && answerInPence % 100 == 0) {
                return .correct
            }
            return .needsTwoDecimalPlaces
        }
    }
}

struct Year4MoneyView: View {
    @State private var current = Year4MoneyQuestion.random()
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var isSidebarOpen : Bool = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 20) {
                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
                
                WorkingOutView(canvasView: $canvasView)
                
                HStack{
                    Text("£")
                        .font(.system(size: UIScreen.main.bounds.width * 0.075))
                        .foregroundStyle(.onBackground)
                        .padding()
                        .fontWeight(.bold)
                        .accessibilityHidden(true)
                    
                    TextField(answerBox: "Answer", text: $answerString)
                        .accessibilityLabel("Answer in pounds")
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .multilineTextAlignment(.center)
                        .answerKeyboard(.decimalPad)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }
                }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func resetQuestion() {
        current = Year4MoneyQuestion.random()
        answerString = ""
        responseMessage = ""
        showMessage = false
        canvasView.drawing = PKDrawing()
        progress.reset()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .notANumber:
            responseMessage = "Please enter a number!"
            showFeedback()
        case .needsTwoDecimalPlaces:
            responseMessage = "Make sure to write your answer with 2 decimal places. E.g. £1.23"
            showFeedback()
        case .ambiguousComma:
            responseMessage = "Use a decimal point."
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

struct Year5View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 5")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.percentages)) {
                    Text("Percentages")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.statistics)) {
                    Text("Statistics")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.volume)) {
                    Text("Volume")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

struct Year5PercentagesView: View {
    @State private var percentagenumber = Int.random(in: 1...20) * 5
    @State private var randomnumber: Int = 0
    @State private var answerString: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var isSidebarOpen : Bool = false
    @State private var questionText: String
    @State private var progress = QuestionProgress()

    init() {
        let (question, percentage, number) = Year5PercentagesView.generateValidQuestion()
        _questionText = State(initialValue: question)
        _percentagenumber = State(initialValue: percentage)
        _randomnumber = State(initialValue: number)
    }

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            // Tighter than the other activities' 20: this is the tallest question screen, and at 20 it didn't fit
            // an iPhone SE without scrolling.
            VStack(spacing: 12) {
                Text(questionText)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                Text("What is the amount?")
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .padding()
                    .fontWeight(.bold)
                
                WorkingOutView(canvasView: $canvasView)
                
                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(.numberPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {
                                
                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private static func generateValidQuestion() -> (String, Int, Int) {
        let percentagenumber = Int.random(in: 1...20) * 5
        let gcdValue = gcd(100, percentagenumber)
        let step = 100 / gcdValue

        var possibleNumbers: [Int] = []
        for num in stride(from: step, through: 200, by: step) {
            possibleNumbers.append(num)
        }

        let randomnumber = possibleNumbers.randomElement() ?? step
        let question = "Find \(percentagenumber)% of \(randomnumber)"

        return (question, percentagenumber, randomnumber)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            let temp = y
            y = x % y
            x = temp
        }
        return x
    }

    private func resetQuestion() {
        let (question, percentage, number) = Year5PercentagesView.generateValidQuestion()
        questionText = question
        percentagenumber = percentage
        randomnumber = number
        responseMessage = ""
        answerString = ""
        canvasView.drawing = PKDrawing()
        progress.reset()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        guard !TypedAnswer.isBlank(answerString) else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        if let answerInt = TypedAnswer.wholeNumber(answerString), answerInt == percentagenumber * randomnumber / 100 {
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                resetQuestion()
            }
        } else {
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }
    
    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

/// Strict parsing and exact comparison for typed answers. Anything that isn't a plain number is
/// rejected rather than guessed at, so stray text can never be marked correct, and decimals are
/// compared as exact fractions, so 7, 7.0 and 7,00 are all the same answer.
enum TypedAnswer {
    /// Digits only, ignoring spaces around them. Signs, decimal points, spaces between digits and
    /// numbers too large for Int are all rejected.
    static func wholeNumber(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(isDigit) else { return nil }
        return Int(trimmed)
    }

    /// A non-negative decimal as a fraction in lowest terms, so "7.50" is 15/2. The separator can be
    /// "." or "," (the decimal key types "," in some regions). Signs, exponents and any other text
    /// are rejected.
    static func exactDecimal(_ text: String) -> (numerator: Int, denominator: Int)? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2,
              parts.contains(where: { !$0.isEmpty }),
              parts.allSatisfy({ $0.allSatisfy(isDigit) }) else {
            return nil
        }

        let whole = String(parts[0].drop { $0 == "0" })
        var fraction = parts.count == 2 ? String(parts[1]) : ""
        while fraction.hasSuffix("0") {
            fraction.removeLast()
        }
        let digits = whole + fraction
        // 10^18 is the largest power of ten an Int can hold.
        guard fraction.count <= 18, let value = digits.isEmpty ? 0 : Int(digits) else { return nil }

        var scale = 1
        for _ in 0..<fraction.count {
            scale *= 10
        }
        return reduced(value, scale)
    }

    /// True if the text is a number exactly equal to numerator / denominator.
    static func isNumber(_ text: String, equalTo numerator: Int, over denominator: Int = 1) -> Bool {
        guard let typed = exactDecimal(text) else { return false }
        return fractionsAreEqual(typed.numerator, typed.denominator, numerator, denominator)
    }

    /// Compares a/b with c/d by reducing both, so nothing is multiplied and nothing can overflow.
    /// Numerators must be zero or more and denominators more than zero.
    static func fractionsAreEqual(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool {
        guard a >= 0, b > 0, c >= 0, d > 0 else { return false }
        return reduced(a, b) == reduced(c, d)
    }

    /// Never traps, even for Int.min.
    static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (x, y) = (a.magnitude, b.magnitude)
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return Int(clamping: x)
    }

    private static func reduced(_ numerator: Int, _ denominator: Int) -> (numerator: Int, denominator: Int) {
        let divisor = greatestCommonDivisor(numerator, denominator)
        return (numerator / divisor, denominator / divisor)
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

extension TypedAnswer {
    static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What a typed decimal turned out to be, so a wrong number, a badly formatted right number and
    /// text that isn't a number can each get their own feedback.
    enum DecimalEntry: Equatable {
        case blank
        /// The exact value as a fraction in lowest terms, and how many digits came after the
        /// decimal point as typed, so "2.50" has 2 and "2.5" has 1.
        case number(numerator: Int, denominator: Int, decimalPlaces: Int)
        /// Something like "1,500", which is 1500 with a thousands separator but 1.5 with a decimal
        /// comma, so it's neither marked right nor wrong.
        case ambiguousComma
        case notANumber
    }

    static func decimalEntry(_ text: String) -> DecimalEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .blank }

        let commaParts = trimmed.split(separator: ",", omittingEmptySubsequences: false)
        if commaParts.count == 2, !trimmed.contains("."),
           (1...3).contains(commaParts[0].count), commaParts[0].first != "0",
           commaParts[1].count == 3,
           commaParts.allSatisfy({ $0.allSatisfy(isDigit) }) {
            return .ambiguousComma
        }

        guard let value = exactDecimal(trimmed) else { return .notANumber }
        let separated = trimmed.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
        let decimalPlaces = separated.count == 2 ? separated[1].count : 0
        return .number(numerator: value.numerator, denominator: value.denominator, decimalPlaces: decimalPlaces)
    }
}

/// One Year 5 Statistics question. Generation and marking live outside the view so the numbers on
/// screen, the answer they lead to and the marking can be unit tested together.
struct Year5StatisticsQuestion: Equatable {
    static let datasetSize = 10
    static let categories = ["A", "B", "C", "D"]

    enum Kind: CaseIterable, Equatable {
        case mean, mode, highestBar
    }

    var kind: Kind
    /// The numbers listed in a mean or mode question. Empty for the bar chart question.
    var numbers: [Int]
    /// The bar chart's values by category. Empty for the other questions.
    var bars: [String: Int]

    static func random() -> Year5StatisticsQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year5StatisticsQuestion {
        switch Kind.allCases.randomElement(using: &generator)! {
        case .mean:
            return Year5StatisticsQuestion(kind: .mean, numbers: datasetForMean(using: &generator), bars: [:])
        case .mode:
            return Year5StatisticsQuestion(kind: .mode, numbers: datasetForMode(using: &generator), bars: [:])
        case .highestBar:
            return Year5StatisticsQuestion(kind: .highestBar, numbers: [], bars: barData(using: &generator))
        }
    }

    static func datasetForMean<G: RandomNumberGenerator>(using generator: inout G) -> [Int] {
        (0..<datasetSize).map { _ in Int.random(in: 1...20, using: &generator) }
    }

    /// One number appears 3 to 5 times and every other number appears fewer times, so the mode is
    /// never tied.
    static func datasetForMode<G: RandomNumberGenerator>(using generator: inout G) -> [Int] {
        let mode = Int.random(in: 1...10, using: &generator)
        let modeCount = Int.random(in: 3...(datasetSize / 2), using: &generator)
        var dataset = Array(repeating: mode, count: modeCount)
        var counts = [Int: Int]()

        while dataset.count < datasetSize {
            let allowed = (1...10).filter { $0 != mode && counts[$0, default: 0] < modeCount - 1 }
            let number = allowed.randomElement(using: &generator)!
            counts[number, default: 0] += 1
            dataset.append(number)
        }

        dataset.shuffle(using: &generator)
        return dataset
    }

    /// Four different values, so exactly one category is highest.
    static func barData<G: RandomNumberGenerator>(using generator: inout G) -> [String: Int] {
        var values = [Int]()
        while values.count < categories.count {
            let value = Int.random(in: 1...15, using: &generator)
            if !values.contains(value) {
                values.append(value)
            }
        }
        return Dictionary(uniqueKeysWithValues: zip(categories, values))
    }

    var text: String {
        let list = numbers.map { String($0) }.joined(separator: ", ")
        switch kind {
        case .mean:
            return "Find the mean (average) of: \(list)"
        case .mode:
            return "Find the mode (most frequent number) in: \(list)"
        case .highestBar:
            return "Which category has the highest value?"
        }
    }

    /// The mean as an exact fraction rather than a rounded decimal.
    var mean: (numerator: Int, denominator: Int)? {
        numbers.isEmpty ? nil : (numbers.reduce(0, +), numbers.count)
    }

    /// The most frequent number, or nil if no single number is most frequent.
    var mode: Int? {
        let counts = Dictionary(grouping: numbers, by: { $0 }).mapValues { $0.count }
        guard let highest = counts.values.max() else { return nil }
        let modes = counts.filter { $0.value == highest }
        return modes.count == 1 ? modes.first?.key : nil
    }

    /// The category with the tallest bar, or nil if the tallest bars are tied.
    var highestCategory: String? {
        guard let highest = bars.values.max() else { return nil }
        let leaders = bars.filter { $0.value == highest }
        return leaders.count == 1 ? leaders.first?.key : nil
    }

    func isCorrect(answer: String) -> Bool {
        switch kind {
        case .mean:
            guard let mean else { return false }
            return TypedAnswer.isNumber(answer, equalTo: mean.numerator, over: mean.denominator)
        case .mode:
            guard let mode else { return false }
            return TypedAnswer.isNumber(answer, equalTo: mode)
        case .highestBar:
            guard let highestCategory else { return false }
            return answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == highestCategory
        }
    }
}

struct Year5StatisticsView: View {
    @State private var current = Year5StatisticsQuestion.random()
    @State private var answerString: String = ""
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @EnvironmentObject var gameData: GameData
    @State private var isSidebarOpen : Bool = false
    @State private var canvasView = PKCanvasView()
    @State private var progress = QuestionProgress()
    @State private var tallestBar = BarGraphView.usualTallestBar

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 20) {
                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()

                if current.kind == .highestBar {
                    // As tall as its bars and labels, which the fixed 200 points it had wasn't at large text sizes.
                    BarGraphView(data: current.bars, tallestBar: tallestBar)
                        .padding()
                } else {
                    WorkingOutView(canvasView: $canvasView)
                }

                TextField(answerBox: "Answer", text: $answerString)
                    .answerBoxMargin()
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(UIScreen.main.bounds.width * 0.02)
                    .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                    .font(.system(size: UIScreen.main.bounds.width * 0.05))
                    .multilineTextAlignment(.center)
                    .answerKeyboard(current.kind == .highestBar ? .default : .decimalPad)
                    .onSubmit {
                        checkAnswer()
                        hideKeyboard()
                    }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()

                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {

                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            // With large text the bar chart, the answer box and Enter don't all fit on an iPhone, so the bars are
            // drawn shorter there.
            .fitOnScreen(by: $tallestBar, usual: BarGraphView.usualTallestBar,
                         minimum: BarGraphView.usualTallestBar / 2, paused: showMessage || current.kind != .highestBar)
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        guard !TypedAnswer.isBlank(answerString) else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        switch progress.recordSubmission(isCorrect: current.isCorrect(answer: answerString)) {
        case .ignored:
            return
        case .correct:
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
        }
    }

    private func resetQuestion() {
        current = Year5StatisticsQuestion.random()
        answerString = ""
        responseMessage = ""
        canvasView.drawing = PKDrawing()
        progress.reset()
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

struct BarGraphView: View {
    /// The height of a bar with the largest value, 15.
    static let usualTallestBar: CGFloat = 150

    var data: [String: Int]
    /// Shorter than usual when the question doesn't otherwise fit on the screen. Each bar has its value written above
    /// it, so shorter bars are still easy to compare.
    var tallestBar: CGFloat = BarGraphView.usualTallestBar

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { category, value in
                VStack {
                    // The usual text size limit: at the largest sizes the numbers and letters were taller than the
                    // space the chart had, and ran into the answer box.
                    Text("\(value)")
                        .scaledFont(size: 17)
                        .foregroundStyle(.onBackground)
                    Rectangle()
                        .fill(.onBackground)
                        .frame(width: 30, height: CGFloat(value) * tallestBar / 15)
                    Text(category)
                        .scaledFont(size: 17)
                        .foregroundStyle(.onBackground)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Category \(category)")
                .accessibilityValue("\(value)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bar chart")
    }
}

/// One Year 5 Volume question. Generation and marking live outside the view so the cubic volumes,
/// the millilitre to litre conversion and the A or B marking can be unit tested.
struct Year5VolumeQuestion: Equatable {
    static let edgeLengths = 2...10

    enum Kind: CaseIterable, Equatable {
        case cube, cuboid, comparison
    }

    var kind: Kind
    /// Edges in cm. A cube's are all equal. Zero for the comparison question.
    var length: Int
    var width: Int
    var height: Int
    /// Glass A is shown in millilitres and glass B in litres, but both are stored in whole
    /// millilitres so the comparison is exact. Zero for the cube and cuboid questions.
    var glassAMillilitres: Int
    var glassBMillilitres: Int

    static func random() -> Year5VolumeQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year5VolumeQuestion {
        switch Kind.allCases.randomElement(using: &generator)! {
        case .cube:
            let side = Int.random(in: edgeLengths, using: &generator)
            return Year5VolumeQuestion(kind: .cube, length: side, width: side, height: side,
                                       glassAMillilitres: 0, glassBMillilitres: 0)
        case .cuboid:
            return Year5VolumeQuestion(kind: .cuboid,
                                       length: Int.random(in: edgeLengths, using: &generator),
                                       width: Int.random(in: edgeLengths, using: &generator),
                                       height: Int.random(in: edgeLengths, using: &generator),
                                       glassAMillilitres: 0, glassBMillilitres: 0)
        case .comparison:
            // 0.5 L to 5 L, with one glass holding 0.1 L to 0.49 L more. Both are whole multiples of
            // 10 mL, so glass B never needs more than two decimal places in litres, and the glasses
            // are never equal. Either glass can be the fuller one.
            let base = Int.random(in: 50...500, using: &generator) * 10
            let difference = Int.random(in: 10...49, using: &generator) * 10
            let glassAHasMore = Bool.random(using: &generator)
            return Year5VolumeQuestion(kind: .comparison, length: 0, width: 0, height: 0,
                                       glassAMillilitres: glassAHasMore ? base + difference : base,
                                       glassBMillilitres: glassAHasMore ? base : base + difference)
        }
    }

    /// Writes millilitres as litres exactly, without trailing zeros: 2000 is "2" and 2350 is "2.35".
    static func litres(fromMillilitres millilitres: Int) -> String {
        let whole = millilitres / 1000
        let remainder = millilitres % 1000
        guard remainder != 0 else { return "\(whole)" }

        var decimals = String(remainder)
        decimals = String(repeating: "0", count: 3 - decimals.count) + decimals
        while decimals.hasSuffix("0") {
            decimals.removeLast()
        }
        return "\(whole).\(decimals)"
    }

    /// In cm³.
    var volume: Int {
        length * width * height
    }

    /// "A" or "B", or nil if both glasses hold the same amount (which the generator never produces).
    var glassWithMore: String? {
        if glassAMillilitres == glassBMillilitres { return nil }
        return glassAMillilitres > glassBMillilitres ? "A" : "B"
    }

    var text: String {
        switch kind {
        case .cube:
            return "What is the volume of this cube?"
        case .cuboid:
            return "What is the volume of this cuboid?"
        case .comparison:
            return "Glass A has \(glassAMillilitres) mL. Glass B has \(Self.litres(fromMillilitres: glassBMillilitres)) L. Which has more liquid? \n A or B?"
        }
    }

    /// What the picture shows, for VoiceOver: the three edges it labels.
    var figureDescription: String {
        "A \(kind == .cube ? "cube" : "cuboid"). Width \(width) centimetres, length \(length) centimetres, height \(height) centimetres."
    }

    func isCorrect(answer: String) -> Bool {
        switch kind {
        case .cube, .cuboid:
            return TypedAnswer.isNumber(answer, equalTo: volume)
        case .comparison:
            guard let glassWithMore else { return false }
            return answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == glassWithMore
        }
    }
}

struct Year5VolumeView: View {
    @State private var current = Year5VolumeQuestion.random()
    @State private var answerString: String = ""
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @EnvironmentObject var gameData: GameData
    @State private var canvasView = PKCanvasView()
    @State private var padHeight = WorkingOutView.usualPadHeight
    @State private var isSidebarOpen : Bool = false
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity).ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            // 12 between the parts rather than 20, so a cube or cuboid fits on more screens.
            VStack(spacing: 12) {
                if current.kind != .comparison {
                    VolumeShapeView(
                        side: current.length,
                        length: current.length,
                        width: current.width,
                        height: current.height
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(current.figureDescription)
                    .accessibilityAddTraits(.isImage)
                }

                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                WorkingOutView(canvasView: $canvasView, padHeight: padHeight)

                if current.kind != .comparison {
                    HStack {
                        TextField(answerBox: "Answer", text: $answerString)
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.decimalPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }

                        Text("cm³")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .foregroundStyle(.onBackground)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                } else {

                    TextField(answerBox: "Answer", text: $answerString)
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .multilineTextAlignment(.center)
                        .keyboardType(.default)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }
                }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()

                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {

                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            // On most iPhones a cube or cuboid is too tall to fit above the answer box and Enter, so the drawing
            // pad gives up as much height as that takes.
            .fitOnScreen(by: $padHeight, usual: WorkingOutView.usualPadHeight,
                         minimum: WorkingOutView.usualPadHeight / 2, paused: showMessage)
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        // A blank answer is asked for, not marked: it scores nothing and doesn't count towards Skip.
        guard !TypedAnswer.isBlank(answerString) else {
            responseMessage = "Please enter an answer!"
            showFeedback()
            return
        }

        switch progress.recordSubmission(isCorrect: current.isCorrect(answer: answerString)) {
        case .ignored:
            return
        case .correct:
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }

    private func resetQuestion() {
        canvasView.drawing = PKDrawing()
        current = Year5VolumeQuestion.random()
        answerString = ""
        responseMessage = ""
        showMessage = false
        progress.reset()
    }
}

struct VolumeShapeView: View {
    var side: Int
    var length: Int
    var width: Int
    var height: Int

    @Environment(\.chosenBackground) private var chosenBackground
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The drawing, then its width, length and height: the order VolumeShapeArrangement places them in.
        VolumeShapeArrangement {
            ZStack {
                face(VolumeShapeLayout.topFace, opacity: 0.3)
                face(VolumeShapeLayout.frontFace, opacity: 0.4)
                face(VolumeShapeLayout.rightFace, opacity: 0.5)
                face(VolumeShapeLayout.bottomFace, opacity: 0.6)

                Path { path in
                    path.addLines(VolumeShapeLayout.leftEdge)
                }
                .stroke(.onBackground, lineWidth: VolumeShapeLayout.lineWidth)

                Path { path in
                    path.addLines(VolumeShapeLayout.heightEdge)
                }
                .stroke(.onBackground, style: StrokeStyle(lineWidth: 1, dash: [5]))
            }
            .frame(width: VolumeShapeLayout.drawingSize.width, height: VolumeShapeLayout.drawingSize.height)

            label("\(width) cm")
            label("\(length) cm")
            label("\(height) cm")
        }
    }

    /// One face of the cuboid: see-through grey, with its edges drawn round it.
    private func face(_ corners: [CGPoint], opacity: Double) -> some View {
        let outline = Path { path in
            path.addLines(corners)
            path.closeSubpath()
        }
        return outline
            .fill(Color.gray.opacity(opacity))
            .overlay(outline.stroke(.onBackground, lineWidth: VolumeShapeLayout.lineWidth))
    }

    /// A side's length, in black or white, whichever reads better on the background and the grey faces. It grows with
    /// the reader's text size; VolumeShapeLayout keeps it off the lines however big it is.
    private func label(_ words: String) -> some View {
        let colours = Self.labelColours(on: chosenBackground.rgb(in: colorScheme))
        return ZStack {
            if let outline = colours.outline {
                ForEach([-1, 0, 1], id: \.self) { xOffset in
                    ForEach([-1, 0, 1], id: \.self) { yOffset in
                        Text(words)
                            .foregroundColor(Color(outline))
                            .offset(x: CGFloat(xOffset), y: CGFloat(yOffset))
                    }
                }
                .accessibilityHidden(true)
            }
            Text(words)
                .foregroundColor(Color(colours.text))
        }
        .scaledFont(size: 14)
        .fixedSize()
    }

    /// The labels' colour: black or white, whichever reads better on everything behind them. Where even that isn't
    /// 4.5:1 on all of it, the words get a thin outline of the other colour too.
    static func labelColours(on background: Contrast.RGB) -> (text: Contrast.RGB, outline: Contrast.RGB?) {
        let surfaces = labelSurfaces(on: background)
        let text = Contrast.blackOrWhiteReadingBetter(on: surfaces)
        guard Contrast.lowestRatio(text, on: surfaces) < 4.55 else { return (text, nil) }
        return (text, text == Contrast.white ? Contrast.black : Contrast.white)
    }

    /// What the labels' colour has to read on: the background they're drawn on, and the grey faces drawn over it
    /// beside them.
    static func labelSurfaces(on background: Contrast.RGB) -> [Contrast.RGB] {
        let grey = Contrast.systemGrey
        let top = Contrast.composite(grey, opacity: 0.3, over: background)
        return [
            background,
            top,
            Contrast.composite(grey, opacity: 0.5, over: top),
            Contrast.composite(grey, opacity: 0.5, over: background),
            Contrast.composite(grey, opacity: 0.6, over: background),
        ]
    }
}

/// Where a cuboid's drawing and its three measurements go. Each measurement is outside the drawing, beside the edge
/// it measures, and clear of every line however big the reader's text makes it: they used to be drawn across the
/// edges, and the right-hand one across the dashed line.
struct VolumeShapeLayout {
    /// The drawing is 150 points square: a 100-point square face at the top left, and the same face 50 points right
    /// and 50 down, joined to it.
    static let drawingSize = CGSize(width: 150, height: 150)
    static let lineWidth: CGFloat = 2
    /// The clear space between a measurement and the edge of the nearest line. A measurement's outline, when it has
    /// one, takes a point of this.
    static let gap: CGFloat = 4

    static let topFace = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 150, y: 50), CGPoint(x: 50, y: 50)]
    static let frontFace = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 0)]
    static let rightFace = [CGPoint(x: 100, y: 0), CGPoint(x: 150, y: 50), CGPoint(x: 150, y: 150), CGPoint(x: 100, y: 100)]
    static let bottomFace = [CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 150), CGPoint(x: 150, y: 150), CGPoint(x: 100, y: 100)]
    static let leftEdge = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100)]
    /// Dashed, over the right-hand edge.
    static let heightEdge = [CGPoint(x: 150, y: 50), CGPoint(x: 150, y: 150)]

    /// Every line drawn, as pairs of ends.
    static var lines: [(CGPoint, CGPoint)] {
        [topFace, frontFace, rightFace, bottomFace].flatMap { corners in
            corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
        } + [(leftEdge[0], leftEdge[1]), (heightEdge[0], heightEdge[1])]
    }

    /// Where each part goes, with the top left of everything at 0, 0.
    let drawing: CGRect
    let widthLabel: CGRect
    let lengthLabel: CGRect
    let heightLabel: CGRect
    let size: CGSize

    /// The arguments are the sizes the three measurements are drawn at.
    init(width: CGSize, length: CGSize, height: CGSize) {
        let clearance = Self.lineWidth / 2 + Self.gap
        let drawing = CGRect(origin: .zero, size: Self.drawingSize)
        // The width goes under the bottom edge, in the middle of it.
        let widthLabel = CGRect(origin: CGPoint(x: 100 - width.width / 2, y: 150 + clearance), size: width)
        // The height goes to the right of the right-hand edge, halfway up it.
        let heightLabel = CGRect(origin: CGPoint(x: 150 + clearance, y: 100 - height.height / 2), size: height)
        // The length goes beside the sloping edge at the top right, straight out from its middle, just far enough for
        // its nearest corner to be clear of it.
        let out = clearance / 2.squareRoot() + (length.width + length.height) / 4
        let lengthLabel = CGRect(origin: CGPoint(x: 125 + out - length.width / 2, y: 25 - out - length.height / 2),
                                 size: length)

        let everything = [widthLabel, lengthLabel, heightLabel].reduce(drawing) { $0.union($1) }
        let shift = CGAffineTransform(translationX: -everything.minX, y: -everything.minY)
        self.drawing = drawing.applying(shift)
        self.widthLabel = widthLabel.applying(shift)
        self.lengthLabel = lengthLabel.applying(shift)
        self.heightLabel = heightLabel.applying(shift)
        size = everything.size
    }
}

/// Places a cuboid's drawing and then its width, length and height where VolumeShapeLayout says, at the size the
/// reader's text makes the measurements.
struct VolumeShapeArrangement: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(of: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = layout(of: subviews)
        let frames = [layout.drawing, layout.widthLabel, layout.lengthLabel, layout.heightLabel]
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func layout(of subviews: Subviews) -> VolumeShapeLayout {
        VolumeShapeLayout(width: subviews[1].sizeThatFits(.unspecified),
                          length: subviews[2].sizeThatFits(.unspecified),
                          height: subviews[3].sizeThatFits(.unspecified))
    }
}

struct Year6View: View {
    @State private var isSidebarOpen : Bool = false
    @EnvironmentObject var gameData: GameData

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                
            VStack(){
                NavigationBar(Back : true, Points : true, isSidebarOpen : $isSidebarOpen)
                    .frame(maxWidth: .infinity)
                    .edgesIgnoringSafeArea(.top)
                    .padding(.top, UIScreen.main.bounds.height * 0.002)
                Spacer()
            }
            VStack(spacing: 50) {
                Text("Year 6")
                    .font(.system(size: UIScreen.main.bounds.width * 0.2))
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .underline()
                    .accessibilityAddTraits(.isHeader)
                ScreenButton(to: .activity(.algebra)) {
                    Text("Algebra")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.probability)) {
                    Text("Probability")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                }
                ScreenButton(to: .activity(.ratios)) {
                    Text("Ratios")
                        .padding()
                        .font(.system(size: UIScreen.main.bounds.width * 0.1))
                        .foregroundColor(Color.black)
                        .fontWeight(.bold)
                        .background(Color.white)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .adBreakPoint()
    }
}

/// A simplified expression ax + b read from what was typed. Terms can come in either order, and
/// spaces and a capital X don't matter, so "15x + 6", "6+15x" and "6 + 15X" are all 15x + 6.
/// A coefficient of 1 can be written as x or 1x.
struct LinearExpression: Equatable {
    var coefficient: Int
    var constant: Int

    init(coefficient: Int, constant: Int) {
        self.coefficient = coefficient
        self.constant = constant
    }

    /// Nil unless the text is at most one x term and at most one number, joined by + or -, with no
    /// zero terms. So unsimplified answers such as "7x + 12x" or "15x + 6 + 0" are rejected, as
    /// are brackets, multiplication signs, decimals and other letters.
    init?(simplified text: String) {
        // Some keyboards type a minus sign or an en dash instead of a hyphen.
        let characters = Array(text.lowercased().filter { !$0.isWhitespace }.map { $0 == "−" || $0 == "–" ? "-" : $0 })
        guard !characters.isEmpty else { return nil }

        var coefficient: Int?
        var constant: Int?
        var index = 0
        while index < characters.count {
            var sign = 1
            if characters[index] == "+" || characters[index] == "-" {
                sign = characters[index] == "-" ? -1 : 1
                index += 1
            } else if index > 0 {
                // Every term after the first needs a + or - in front of it.
                return nil
            }

            let digitsStart = index
            while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                index += 1
            }
            let digits = String(characters[digitsStart..<index])
            let hasX = index < characters.count && characters[index] == "x"
            if hasX {
                index += 1
            }

            guard !digits.isEmpty || hasX,
                  let size = digits.isEmpty ? 1 : Int(digits),
                  size != 0 else {
                return nil
            }
            if hasX {
                guard coefficient == nil else { return nil }
                coefficient = sign * size
            } else {
                guard constant == nil else { return nil }
                constant = sign * size
            }
        }
        self.init(coefficient: coefficient ?? 0, constant: constant ?? 0)
    }
}

/// One Year 6 Algebra question. Answers are read as algebra rather than compared as text, so terms
/// can be written in either order, but the signs, coefficient and constant must be right and the
/// answer fully simplified.
struct Year6AlgebraQuestion: Equatable {
    static let numbers = 1..<20
    /// Expanding a bracket multiplied by 1 would mean showing 1(…), which isn't how algebra is written.
    static let multipliers = 2...4

    enum Kind: Equatable {
        /// "x + 7 = 19", an equation, answered 12.
        case solve
        /// "7x + 12x", an expression, answered 19x.
        case simplify
        /// "3(5x + 2)", an expression, answered 15x + 6.
        case expand
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var kind: Kind
    var first: Int
    var second: Int
    var multiplier: Int

    static func random() -> Year6AlgebraQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year6AlgebraQuestion {
        let type = Int.random(in: 1...3, using: &generator) // 1: Solve, 2: Simplify, 3: Expand
        let kind: Kind = type == 1 ? .solve : type == 2 ? .simplify : .expand
        return Year6AlgebraQuestion(kind: kind,
                                    first: Int.random(in: numbers, using: &generator),
                                    second: Int.random(in: numbers, using: &generator),
                                    multiplier: Int.random(in: multipliers, using: &generator))
    }

    /// An x term as it's written in algebra, so a coefficient of 1 is just "x".
    static func term(_ coefficient: Int) -> String {
        coefficient == 1 ? "x" : "\(coefficient)x"
    }

    var expression: String {
        switch kind {
        case .solve:
            return "x + \(first) = \(first + second)"
        case .simplify:
            return "\(Self.term(first)) + \(Self.term(second))"
        case .expand:
            return "\(multiplier)(\(Self.term(first)) + \(second))"
        }
    }

    /// VoiceOver doesn't read brackets, so "3(5x + 2)" would sound like "3 5x plus 2".
    var spokenExpression: String {
        switch kind {
        case .solve, .simplify:
            return expression
        case .expand:
            return "\(multiplier) times open bracket \(Self.term(first)) plus \(second) close bracket"
        }
    }

    var instruction: String {
        switch kind {
        case .solve:
            return "Solve for x in this equation"
        case .simplify:
            return "Simplify this expression"
        case .expand:
            return "Expand this expression"
        }
    }

    /// The simplified expression the answer must equal. For the equation it's the value of x.
    var answer: LinearExpression {
        switch kind {
        case .solve:
            return LinearExpression(coefficient: 0, constant: second)
        case .simplify:
            return LinearExpression(coefficient: first + second, constant: 0)
        case .expand:
            return LinearExpression(coefficient: multiplier * first, constant: multiplier * second)
        }
    }

    func evaluate(_ text: String) -> Outcome {
        guard !TypedAnswer.isBlank(text) else { return .unanswered }

        switch kind {
        case .solve:
            // The box follows "x =", but "x = 12" typed in full is also accepted.
            var typed = text.lowercased().filter { !$0.isWhitespace }
            if typed.hasPrefix("x=") {
                typed.removeFirst(2)
            }
            return TypedAnswer.wholeNumber(typed) == second ? .correct : .incorrect
        case .simplify, .expand:
            return LinearExpression(simplified: text) == answer ? .correct : .incorrect
        }
    }
}

struct Year6AlgebraView: View {
    @State private var current = Year6AlgebraQuestion.random()
    @State private var stringAnswer: String = ""
    @EnvironmentObject var gameData: GameData
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var isSidebarOpen: Bool = false
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity).ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }
                .gesture(DragGesture(minimumDistance: 0))

            VStack(spacing: 20) {
                Text(current.expression)
                    .accessibilityLabel(current.spokenExpression)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)
                Text(current.instruction)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .fontWeight(.bold)
                    .foregroundStyle(.onBackground)

                WorkingOutView(canvasView: $canvasView)
                HStack {
                    if current.kind == .solve {
                        Text("x =")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                    }

                    TextField(answerBox: "Answer", text: $stringAnswer)
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .multilineTextAlignment(.center)
                        .keyboardType(.numbersAndPunctuation)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }
                }
                
                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()
                    
                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {

                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(stringAnswer) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            showFeedback()
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func resetQuestion() {
        current = Year6AlgebraQuestion.random()
        stringAnswer = ""
        responseMessage = ""
        showMessage = false
        canvasView.drawing = PKDrawing()
        progress.reset()
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

/// Wrong attempts, Skip visibility and the pause before the next question. A question can be
/// scored or skipped only once, and everything starts again with the next question.
struct QuestionProgress: Equatable {
    static let wrongAttemptsBeforeSkip = 2

    private(set) var wrongAttempts = 0
    /// True from a correct answer or a rewarded Skip until the next question appears.
    private(set) var isAdvancing = false

    var showSkipButton: Bool {
        !isAdvancing && wrongAttempts >= Self.wrongAttemptsBeforeSkip
    }

    mutating func recordWrongAttempt() {
        guard !isAdvancing else { return }
        wrongAttempts += 1
    }

    /// Returns false if this question has already been answered or skipped, so it can't score twice.
    mutating func recordCorrectAnswer() -> Bool {
        guard !isAdvancing else { return false }
        isAdvancing = true
        return true
    }

    /// Returns false unless Skip is showing, so a question can't be skipped twice or after it has
    /// been answered.
    mutating func recordSkip() -> Bool {
        guard showSkipButton else { return false }
        isAdvancing = true
        return true
    }

    enum Submission: Equatable {
        /// The question has already been answered or skipped, so nothing should happen.
        case ignored
        case correct
        case incorrect
    }

    /// One press of Enter or Return. Once the question has been answered or skipped every further
    /// press is ignored, so a correct answer scores once and can't be followed by "Incorrect".
    mutating func recordSubmission(isCorrect: Bool) -> Submission {
        guard !isAdvancing else { return .ignored }
        if isCorrect {
            return recordCorrectAnswer() ? .correct : .ignored
        }
        recordWrongAttempt()
        return .incorrect
    }

    /// Call when the next question appears.
    mutating func reset() {
        self = QuestionProgress()
    }
}

/// One Year 6 Probability question. Each kind of question carries its own answer, so a fraction
/// that answers a different kind of question (such as 1/6 when a spinner is shown) isn't accepted.
enum Year6ProbabilityQuestion: Equatable {
    case die(faces: Int, target: Int)
    case spinner(sections: Int, blue: Int)
    case coin(flips: Int)
    case marbles(total: Int, red: Int)
    case cards(total: Int, aces: Int)

    enum Outcome: Equatable {
        case correct, incorrect, invalidInput, unanswered
    }

    static func random() -> Year6ProbabilityQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year6ProbabilityQuestion {
        let total = Int.random(in: 5...20, using: &generator)
        let selected = Int.random(in: 1..<total, using: &generator)

        switch Int.random(in: 0..<5, using: &generator) {
        case 0:
            let faces = Int.random(in: 4...10, using: &generator)
            return .die(faces: faces, target: Int.random(in: 1...faces, using: &generator))
        case 1:
            return .spinner(sections: total, blue: selected)
        case 2:
            return .coin(flips: Int.random(in: 1...3, using: &generator))
        case 3:
            return .marbles(total: total, red: selected)
        default:
            return .cards(total: total, aces: selected)
        }
    }

    var text: String {
        switch self {
        case let .die(faces, target):
            // The numbering is stated because real dice differ: a ten-sided die is often numbered 0 to 9. Equal chances
            // are stated too, rather than left to "fair", because a die with 5, 7 or 9 faces is unusual.
            return "A fair die has \(faces) faces, numbered 1 to \(faces). Each number is equally likely to be rolled. "
                + "What is the probability of rolling a \(target)?"
        case let .spinner(sections, blue):
            return "A spinner has \(sections) equal sections. \(Self.howMany(blue)) blue. What is the probability of landing on blue?"
        case let .coin(flips):
            return "A fair coin is flipped \(Self.timesFlipped(flips)). What is the probability of getting heads every time?"
        case let .marbles(total, red):
            return "A bag contains \(total) marbles. \(Self.howMany(red)) red. What is the probability of drawing a red marble?"
        case let .cards(total, aces):
            return "A stack of \(total) cards has \(aces) \(aces == 1 ? "ace" : "aces"). What is the probability of drawing an ace?"
        }
    }

    /// "1 is" or "3 are".
    static func howMany(_ count: Int) -> String {
        "\(count) \(count == 1 ? "is" : "are")"
    }

    /// "once", "twice" or "3 times".
    static func timesFlipped(_ flips: Int) -> String {
        switch flips {
        case 1: return "once"
        case 2: return "twice"
        default: return "\(flips) times"
        }
    }

    /// Favourable outcomes over equally likely outcomes, before simplifying.
    var probability: (numerator: Int, denominator: Int) {
        switch self {
        case let .die(faces, _):
            return (1, faces)
        case let .spinner(sections, blue):
            return (blue, sections)
        case let .coin(flips):
            return (1, 1 << flips)
        case let .marbles(total, red):
            return (red, total)
        case let .cards(total, aces):
            return (aces, total)
        }
    }

    /// Any fraction equal to the probability is correct, so 2/8 is accepted for 1/4. Both boxes empty is
    /// unanswered; one box empty, or anything that isn't a whole number, is invalid.
    func evaluate(numerator: String, denominator: String) -> Outcome {
        if TypedAnswer.isBlank(numerator) && TypedAnswer.isBlank(denominator) { return .unanswered }
        guard let top = TypedAnswer.wholeNumber(numerator),
              let bottom = TypedAnswer.wholeNumber(denominator),
              bottom > 0 else {
            return .invalidInput
        }
        let expected = probability
        return TypedAnswer.fractionsAreEqual(top, bottom, expected.numerator, expected.denominator)
            ? .correct : .incorrect
    }
}

struct Year6ProbabilityView: View {
    @EnvironmentObject var gameData: GameData
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var current = Year6ProbabilityQuestion.random()
    @State private var numerator: String = ""
    @State private var denominator: String = ""
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var isSidebarOpen: Bool = false
    @State private var progress = QuestionProgress()
    @State private var padHeight = WorkingOutView.usualPadHeight

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack {
                Text(current.text)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()

                WorkingOutView(canvasView: $canvasView, padHeight: padHeight)

                FractionAnswerBoxes(numerator: $numerator, denominator: $denominator) {
                    checkAnswer()
                    hideKeyboard()
                }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack {
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .fontWeight(.bold)
                    .padding()

                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {

                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            // With large text on an iPhone, the question, the drawing pad, the fraction and Enter don't all fit, so
            // the drawing pad gives up as much height as that takes.
            .fitOnScreen(by: $padHeight, usual: WorkingOutView.usualPadHeight,
                         minimum: WorkingOutView.usualPadHeight / 2, paused: showMessage)
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func resetQuestion() {
        current = Year6ProbabilityQuestion.random()
        numerator = ""
        denominator = ""
        canvasView.drawing = PKDrawing()
        responseMessage = ""
        progress.reset()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(numerator: numerator, denominator: denominator) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .invalidInput:
            responseMessage = "Please enter valid numbers."
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showMessage = false
            }
        }
    }
}


/// One Year 6 Ratios question. Generation and marking live outside the view so every question can
/// be checked to have exactly one correct answer, with its parts in the order the question asks for.
struct Year6RatioQuestion: Equatable {
    static let ratioTerms = 1...10
    static let multipliers = 2...5

    enum Kind: Equatable {
        /// "Simplify the ratio 6 : 12", answered 1 : 2.
        case simplify
        /// "Divide 18 in the ratio 1 : 2", answered 6 : 12.
        case share
        /// "Find the missing number. ___ : 12 = 1 : 2", answered 6.
        case missingFirst
        /// "Find the missing number. 6 : ___ = 1 : 2", answered 12.
        case missingSecond
    }

    enum Outcome: Equatable {
        case correct, incorrect, unanswered
    }

    var kind: Kind
    /// The ratio first : second, which the question scales up by `multiplier`.
    var first: Int
    var second: Int
    var multiplier: Int

    static func random() -> Year6RatioQuestion {
        var generator = SystemRandomNumberGenerator()
        return random(using: &generator)
    }

    static func random<G: RandomNumberGenerator>(using generator: inout G) -> Year6RatioQuestion {
        let type = Int.random(in: 1...3, using: &generator) // 1: Simplify, 2: Share, 3: Missing value
        let first = Int.random(in: ratioTerms, using: &generator)
        let second = Int.random(in: ratioTerms, using: &generator)
        let multiplier = Int.random(in: multipliers, using: &generator)

        let kind: Kind
        switch type {
        case 1: kind = .simplify
        case 2: kind = .share
        default: kind = Bool.random(using: &generator) ? .missingFirst : .missingSecond
        }
        return Year6RatioQuestion(kind: kind, first: first, second: second, multiplier: multiplier)
    }

    /// True when the answer is a ratio typed into two boxes, false when it's one missing value.
    var asksForRatio: Bool {
        kind == .simplify || kind == .share
    }

    var text: String {
        switch kind {
        case .simplify:
            return "Simplify the ratio \(first * multiplier) : \(second * multiplier)"
        case .share:
            return "Divide \((first + second) * multiplier) in the ratio \(first) : \(second)"
        case .missingFirst:
            return "Find the missing number.\n___ : \(second * multiplier) = \(first) : \(second)"
        case .missingSecond:
            return "Find the missing number.\n\(first * multiplier) : ___ = \(first) : \(second)"
        }
    }

    /// "to" for the ":", which VoiceOver can read as a time, and "missing number" for the gap, which it skips.
    var spokenText: String {
        switch kind {
        case .simplify:
            return "Simplify the ratio " + SpokenMaths.ratio("\(first * multiplier)", "\(second * multiplier)")
        case .share:
            return "Divide \((first + second) * multiplier) in the ratio " + SpokenMaths.ratio("\(first)", "\(second)")
        case .missingFirst:
            return "Find the missing number. " + SpokenMaths.ratio(SpokenMaths.missingNumber, "\(second * multiplier)")
                + " equals " + SpokenMaths.ratio("\(first)", "\(second)")
        case .missingSecond:
            return "Find the missing number. " + SpokenMaths.ratio("\(first * multiplier)", SpokenMaths.missingNumber)
                + " equals " + SpokenMaths.ratio("\(first)", "\(second)")
        }
    }

    /// The two parts of a ratio answer, in order. Simplifying divides by the highest common
    /// factor, so 6:12 is 1:2 even when it was made by scaling up 2:4.
    var correctRatio: (first: Int, second: Int)? {
        switch kind {
        case .simplify:
            let factor = TypedAnswer.greatestCommonDivisor(first, second)
            return (first / factor, second / factor)
        case .share:
            return (first * multiplier, second * multiplier)
        case .missingFirst, .missingSecond:
            return nil
        }
    }

    var correctMissingValue: Int? {
        switch kind {
        case .missingFirst:
            return first * multiplier
        case .missingSecond:
            return second * multiplier
        case .simplify, .share:
            return nil
        }
    }

    /// Reads only the boxes the question shows: `first` and `second` for a ratio, `missing` for a
    /// missing value.
    func evaluate(first firstText: String, second secondText: String, missing missingText: String) -> Outcome {
        if let expected = correctRatio {
            if Self.isBlank(firstText) && Self.isBlank(secondText) {
                return .unanswered
            }
            guard let firstPart = TypedAnswer.wholeNumber(firstText),
                  let secondPart = TypedAnswer.wholeNumber(secondText) else {
                return .incorrect
            }
            return firstPart == expected.first && secondPart == expected.second ? .correct : .incorrect
        }

        guard let expected = correctMissingValue else { return .incorrect }
        if Self.isBlank(missingText) {
            return .unanswered
        }
        return TypedAnswer.wholeNumber(missingText) == expected ? .correct : .incorrect
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct Year6RatiosView: View {
    @EnvironmentObject var gameData: GameData
    @State private var sfxPlayer = SFXPlayer()
    @State private var canvasView = PKCanvasView()
    @State private var current = Year6RatioQuestion.random()
    @State private var answerString: String = ""
    @State private var answerRatio1: String = ""
    @State private var answerRatio2: String = ""
    @State private var responseMessage: String = ""
    @State private var showMessage = false
    @State private var isSidebarOpen: Bool = false
    @State private var progress = QuestionProgress()

    var body: some View {
        ZStack {
            Color(hex: gameData.backgroundColourHex).opacity(gameData.backgroundOpacity)
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }

            VStack {
                Text(current.text)
                    .accessibilityLabel(current.spokenText)
                    .scaledFont(size: UIScreen.main.bounds.width * 0.05)
                    .foregroundStyle(.onBackground)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding()

                WorkingOutView(canvasView: $canvasView)
                    .padding(.bottom, 20)

                if current.asksForRatio {
                    HStack(spacing: 5) {
                        TextField(answerBox: "Answer", text: $answerRatio1)
                            .accessibilityLabel("First part of the ratio")
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }

                        Text(":")
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .fontWeight(.bold)
                            .foregroundStyle(.onBackground)
                            .accessibilityHidden(true)

                        TextField(answerBox: "Answer", text: $answerRatio2)
                            .accessibilityLabel("Second part of the ratio")
                            .answerBoxMargin()
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(UIScreen.main.bounds.width * 0.02)
                            .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                            .font(.system(size: UIScreen.main.bounds.width * 0.05))
                            .multilineTextAlignment(.center)
                            .answerKeyboard(.numberPad)
                            .onSubmit {
                                checkAnswer()
                                hideKeyboard()
                            }
                    }
                } else {
                    TextField(answerBox: "Answer", text: $answerString)
                        .answerBoxMargin()
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(UIScreen.main.bounds.width * 0.02)
                        .frame(width: UIScreen.main.bounds.width / 3, height: UIScreen.main.bounds.width * 0.15)
                        .font(.system(size: UIScreen.main.bounds.width * 0.05))
                        .multilineTextAlignment(.center)
                        .answerKeyboard(.numberPad)
                        .onSubmit {
                            checkAnswer()
                            hideKeyboard()
                        }
                }

                if showMessage {
                    AnswerFeedbackText(message: responseMessage)
                        .padding()
                        .transition(.answerFeedback)
                }

                HStack{
                    Button {
                        hideKeyboard()
                        checkAnswer()
                    } label: {
                        Text("Enter ")
                            .buttonBox(Color.white, cornerRadius: UIScreen.main.bounds.width * 0.015, tapMargin: 6)
                    }
                    .disabled(showMessage)
                    .foregroundColor(.black)
                    .font(.system(size: UIScreen.main.bounds.width * 0.075))
                    .multilineTextAlignment(.center)
                    .fontWeight(.bold)
                    .padding()

                    if progress.showSkipButton {
                        Button {
                            if let rootVC = UIApplication.shared.connectedScenes
                                .compactMap({ $0 as? UIWindowScene })
                                .first?.windows.first?.rootViewController {

                                AdManager.shared.showRewardedInterstitialAd(from: rootVC) {
                                    guard progress.recordSkip() else { return }
                                    gameData.skipQuestion(resetQuestion: resetQuestion)
                                }
                            }
                        } label: {
                            Text("Skip Question")
                                .scaledFont(size: 17, maximum: 28)
                                .padding()
                                .buttonBox(Color.buttonBlue, cornerRadius: 10)
                        }
                        .foregroundColor(.white)
                    }
                }
                .questionSubmitRow()
            }
            .questionLayout(isSidebarOpen: $isSidebarOpen)
        }
        .navigationBarBackButtonHidden(true)
        .questionScreen()
    }

    private func resetQuestion() {
        current = Year6RatioQuestion.random()
        answerString = ""
        answerRatio1 = ""
        answerRatio2 = ""
        responseMessage = ""
        canvasView.drawing = PKDrawing()
        progress.reset()
    }

    private func checkAnswer() {
        // Enter and Return are ignored once the question has been answered or skipped.
        guard !progress.isAdvancing else { return }

        switch current.evaluate(first: answerRatio1, second: answerRatio2, missing: answerString) {
        case .unanswered:
            responseMessage = "Please enter an answer!"
            showFeedback()
        case .correct:
            guard progress.recordCorrectAnswer() else { return }
            responseMessage = "Correct!"
            gameData.points += 1
            gameData.totalQuestionsAnswered += 1
            gameData.saveData()
            sfxPlayer.playSound(named: "right", volume: gameData.sfxvolume)
            showFeedback()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                resetQuestion()
            }
        case .incorrect:
            responseMessage = "Incorrect. Try Again!"
            sfxPlayer.playSound(named: "wrong", volume: gameData.sfxvolume)
            showFeedback()
            progress.recordWrongAttempt()
        }
    }

    private func showFeedback() {
        // Not animated, so that the question can scroll Enter back into view. See `QuestionLayout`.
        showMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showMessage = false
            }
        }
    }
}

struct ContentView: View {
    // The app's single GameData, passed in by Maths_ManiaApp. ContentView must not make its own.
    @EnvironmentObject private var gameData: GameData
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @ObservedObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var navigator = AppNavigator()
    @State private var isLoading = true

    private var canUseApp: Bool {
        networkMonitor.isConnected || purchaseManager.adsRemoved
    }

    var body: some View {
        NavigationStack(path: $navigator.path) {
            Group {
                if isLoading {
                    LoadingView(isLoading: $isLoading)
                } else if canUseApp {
                    MainMenuView()
                        .environmentObject(gameData)
                        .environmentObject(purchaseManager)
                        .environmentObject(navigator)
                        .onAppear {
                            AdManager.shared.loadInterstitialAd()
                        }
                } else {
                    NoInternetView()
                }
            }
            // Every screen gets the app's one GameData, so points are the same wherever they're shown.
            .navigationDestination(for: Screen.self) { screen in
                destination(for: screen)
                    .environment(\.currentScreen, screen)
                    .environment(\.chosenBackground, chosenBackground)
                    .environmentObject(gameData)
                    .environmentObject(purchaseManager)
                    .environmentObject(navigator)
            }
            // Losing the connection shows No Internet in place of every screen, not just under them.
            .onChange(of: canUseApp) { _, canUse in
                if !canUse {
                    navigator.goHome()
                }
            }
            .onAppear {
                if !networkMonitor.isConnected && !purchaseManager.adsRemoved {
                    showAlert()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isLoading = false
                }
            }
        }
        // Words and drawings on the background work out their colours from it. See `ReadableOnBackground`.
        .environment(\.chosenBackground, chosenBackground)
    }

    private var chosenBackground: ChosenBackground {
        ChosenBackground(hex: gameData.backgroundColourHex, opacity: gameData.backgroundOpacity)
    }

    @ViewBuilder
    private func destination(for screen: Screen) -> some View {
        switch screen {
        case .shop: ShopView()
        case .feedback: FeedbackView()
        case .information: InformationView()
        case .removeAds: RemoveAdsView()
        case .settings: SettingsView()
        case .year(1): Year1View()
        case .year(2): Year2View()
        case .year(3): Year3View()
        case .year(4): Year4View()
        case .year(5): Year5View()
        case .year(_): Year6View()
        case .activity(let activity): activityView(activity)
        }
    }

    @ViewBuilder
    private func activityView(_ activity: Activity) -> some View {
        switch activity {
        case .counting: Year1CountingView()
        case .addition: Year1AdditionView()
        case .subtraction: Year1SubtractionView()
        case .multiplication: Year2MultiplicationView()
        case .division: Year2DivisionView()
        case .shapes: Year2ShapesView()
        case .fractions: Year3FractionsView()
        case .measurement: Year3MeasurementView()
        case .time: Year3TimeView()
        case .decimals: Year4DecimalsView()
        case .geometry: Year4GeometryView()
        case .money: Year4MoneyView()
        case .percentages: Year5PercentagesView()
        case .statistics: Year5StatisticsView()
        case .volume: Year5VolumeView()
        case .algebra: Year6AlgebraView()
        case .probability: Year6ProbabilityView()
        case .ratios: Year6RatiosView()
        }
    }

    private func showAlert() {
        let alert = UIAlertController(
            title: "No Internet",
            message: "An internet connection is required to use this app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default, handler: { _ in
            if !NetworkMonitor.shared.isConnected && !PurchaseManager.shared.adsRemoved {
                showAlert()
            }
        }))
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(alert, animated: true)
        }
    }
}

#Preview{
    ContentView()
        .environmentObject(GameData())
}
