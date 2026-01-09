//
//  WatchConnectivityManager.swift
//  HaesslonWatch Watch App
//
//  Created by Daniel Arndt on 09.01.26.
//

import Foundation
import WatchConnectivity
import WidgetKit

class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        // Handle activation
    }
    
    // Receive data from iOS App
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            self.saveData(applicationContext)
        }
    }
    
    private func saveData(_ context: [String: Any]) {
        // Use the same App Group ID as in HaesslonWatchWidget.swift
        let sharedDefaults = UserDefaults(suiteName: "group.com.haesslon.shared")
        
        if let remaining = context["remainingCalories"] as? Double {
            sharedDefaults?.set(remaining, forKey: "remainingCalories")
        }
        
        if let weighedIn = context["weighedInToday"] as? Bool {
            sharedDefaults?.set(weighedIn, forKey: "weighedInToday")
        }
        
        // Tell the Widget to update
        WidgetCenter.shared.reloadAllTimelines()
    }
}
