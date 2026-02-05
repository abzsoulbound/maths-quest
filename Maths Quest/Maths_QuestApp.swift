import SwiftUI
import FirebaseCore
import FirebaseFirestore
import StoreKit

@main
struct Maths_ManiaApp: App {
    @StateObject private var gameData = GameData()
    @StateObject private var purchaseManager = PurchaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State var adsRemoved: Bool
    @State private var isLoading = true

    init() {
        adsRemoved = UserDefaults.standard.bool(forKey: "adsRemoved")
    }
    
    var body: some Scene {
        WindowGroup {
            if isLoading {
                LoadingView(isLoading: $isLoading)
            } else {
                ContentView()
                    .environmentObject(gameData)
                    .environmentObject(purchaseManager)
                    .task {
                        await purchaseManager.fetchProducts()
                        await purchaseManager.observeTransactions()
                    }
            }
        }
    }
}

