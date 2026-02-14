//
//  CinecamApp.swift
//  Cinecam
//
//  Created by David Mišmaš on 14. 2. 26.
//

import SwiftUI
import UIKit

@main
struct CinecamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
