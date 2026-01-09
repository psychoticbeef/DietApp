import AppIntents
import SwiftData
import HealthKit

struct LogBreakfastIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Breakfast"
    static var description = IntentDescription("Logs your standard breakfast to HealthKit.")

    init() {}

    func perform() async throws -> some IntentResult {
        // 1. Initialize HealthManager
        // Since HealthManager's init is isolated to the MainActor, we must instantiate it there.
        let healthManager = await MainActor.run {
            HealthManager()
        }
        
        // 2. Setup SwiftData container manually for the extension
        //    (Since the Widget Extension doesn't inherit the main app's container)
        guard let modelContainer = try? ModelContainer(for: StandardBreakfast.self, FillerFood.self) else {
            return .result()
        }
        
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<StandardBreakfast>()
        
        // 3. Fetch Breakfast
        guard let breakfast = try? context.fetch(descriptor).first, breakfast.isValid else {
            return .result()
        }
        
        // 4. Log to HealthKit
        //    Note: This relies on the app having already been authorized by the user.
        //    We await the async call, which handles the actor hop if necessary.
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
        
        // 5. Force a widget reload to reflect the new calories immediately
        //    Because updateWidgetData is isolated to the MainActor, we must await it.
        await healthManager.updateWidgetData()
        
        return .result()
    }
}
