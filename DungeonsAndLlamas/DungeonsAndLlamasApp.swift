//
//  DungeonsAndLlamasApp.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import SwiftData
import CoreAI

@main
struct DungeonsAndLlamasApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appDelegate.generationService)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let generationService = GenerationService()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        generationService.db.setup()
        generationService.checkStatusIfNeeded()
        generationService.loadHistory()
        generationService.synchronizeComfyUIHistoryOnStartup()
        generationService.logStartupSummary()
        generationService.getModels()
        generationService.getComfyUIModels()
        print(AIModel.deviceArchitectureName)
        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        generationService.checkStatusIfNeeded()
    }
}
