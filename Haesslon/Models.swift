import Foundation
import SwiftData

@Model
class StandardBreakfast {
    var name: String = "Breakfast"
    var totalKcal: Double = 0
    var totalFat: Double = 0
    var totalSatFat: Double = 0
    var totalCarbs: Double = 0
    var totalSugar: Double = 0
    var totalProtein: Double = 0
    var totalFiber: Double = 0
    var totalSodium: Double = 0
    
    var isValid: Bool { totalKcal > 0 }
    
    init(name: String = "Breakfast") {
        self.name = name
    }
}

@Model
class FillerFood {
    var name: String = ""
    var kcalPer100g: Double = 0
    var fatPer100g: Double = 0
    var satFatPer100g: Double = 0
    var carbsPer100g: Double = 0
    var sugarPer100g: Double = 0
    var proteinPer100g: Double = 0
    var fiberPer100g: Double = 0
    var sodiumPer100g: Double = 0
    
    init(name: String = "") {
        self.name = name
    }
}

struct MacroSnapshot {
    var kcal: Double = 0
    var protein: Double = 0
    var fiber: Double = 0
    var fat: Double = 0
    var satFat: Double = 0
    var sugar: Double = 0
    var sodium: Double = 0
    static var zero = MacroSnapshot()
}
