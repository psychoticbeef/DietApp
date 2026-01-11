import Foundation

struct AppConstants {
    // Shared App Group ID
    static let appGroupId = "group.com.haesslon.shared"
    
    struct Keys {
        // Widget Data
        static let remainingCalories = "remainingCalories"
        static let kcalProgress = "kcalProgress"
        static let proteinProgress = "proteinProgress"
        static let fiberProgress = "fiberProgress"
        static let weighedInToday = "weighedInToday"
        static let currentWeight = "currentWeight"
        static let weightTrend = "weightTrend"
        static let lastUpdatedDate = "lastUpdatedDate"
        
        // Settings / AppStorage
        static let caloricDeficit = "caloricDeficit"
        static let autoDeficitEnabled = "autoDeficitEnabled"
        
        // These were missing or named differently causing the errors
        static let autoDeficitUpperBound = "autoDeficitUpperBound"
        static let autoDeficitLowerBound = "autoDeficitLowerBound"
        static let isCurrentlyInDeficitMode = "isCurrentlyInDeficitMode"
        
        static let hasRequestedHealthAuth = "hasRequestedHealthAuthorization"
    }
}
