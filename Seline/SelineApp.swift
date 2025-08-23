//
//  SelineApp.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

@main
struct SelineApp: App {
    @StateObject private var authService = AuthenticationService.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
                .onAppear {
                    // TODO: Configure Google Sign-In when packages are added
                    configureGoogleSignIn()
                }
        }
    }
    
    private func configureGoogleSignIn() {
        // TODO: Replace with actual Google Sign-In configuration
        /*
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("No GoogleService-Info.plist file found or missing CLIENT_ID")
            return
        }
        
        GoogleSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        */
        
        print("Google Sign-In configuration placeholder - add actual configuration when packages are installed")
    }
}