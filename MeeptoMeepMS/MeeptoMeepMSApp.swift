//
//  MeeptoMeepMSApp.swift
//  MeeptoMeepMS
//
//  Created by Panagiotis on 2024-11-06.
//

import SwiftUI

@main
struct MeeptoMeepMSApp: App {
    @StateObject private var connectionService = ConnectionService()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectionService)
        }
    }
}
