import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct MobileMusicStreamingApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    
    init() {
        FirebaseApp.configure()
        let clientID = AppEnvironment.googleClientID
        GoogleDriveService.shared.configure(clientID: clientID)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
