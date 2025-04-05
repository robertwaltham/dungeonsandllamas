//
//  DungeonsAndLlamasApp.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import SwiftData

@main
struct DungeonsAndLlamasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView(generationService: appDelegate.generationService)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let generationService = GenerationService()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        generationService.db.setup()
        generationService.checkStatusIfNeeded()
        generationService.loadHistory()
        generationService.getModels()
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        generationService.checkStatusIfNeeded()
    }
}
