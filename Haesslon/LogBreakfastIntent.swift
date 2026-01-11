import AppIntents
import SwiftData
import HealthKit

struct LogBreakfastIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Breakfast"
    static var description = IntentDescription("Logs your standard breakfast to HealthKit.")

    init() {}

    func perform() async throws -> some IntentResult {
        // Initialize HealthManager on MainActor
        let healthManager = await MainActor.run {
            HealthManager()
        }
        
        // Setup SwiftData container manually for the extension context
        guard let modelContainer = try? ModelContainer(for: StandardBreakfast.self, FillerFood.self) else {
            return .result()
        }
        
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<StandardBreakfast>()
        
        // Fetch Breakfast
        guard let breakfast = try? context.fetch(descriptor).first, breakfast.isValid else {
            return .result()
        }
        
        // Log to HealthKit
        await healthManager.logBreakfast(
            totalKcal: breakfast.totalKcal,
            fat: breakfast.totalFat,
            satFat: breakfast.totalSatFat,
            carbs: breakfast.totalCarbs,
            sugar: breakfast.totalSugar,
            protein: breakfast.totalProtein,
            fiber: breakfast.totalFiber,
            sodium: breakfast.totalSodium
        )
        
        // Update widgets is handled internally by logBreakfast in HealthManager
        return .result()
    }
}
