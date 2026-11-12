import SwiftUI
import FirebaseCore
import FirebaseFirestore
import StoreKit

@main
struct Maths_ManiaApp: App {
    @StateObject private var gameData = GameData()
    // Deliberately not observed here, so purchase updates don't rebuild ContentView.
    // Creating it at launch starts the app's single StoreKit transaction listener.
    private let purchaseManager = PurchaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isLoading = true

    var body: some Scene {
        WindowGroup {
            if isLoading {
                // `GameData` reads the save as it's made, before this is first drawn, so the first loading screen is
                // on the child's chosen background from its first frame, as ContentView's is.
                LoadingView(isLoading: $isLoading)
                    .environment(\.chosenBackground, gameData.chosenBackground)
            } else {
                ContentView()
                    .environmentObject(gameData)
                    .environmentObject(purchaseManager)
            }
        }
    }
}

