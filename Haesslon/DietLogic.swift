//
//  DietLogic.swift
//  Haesslon
//
//  Created by Daniel Arndt on 11.01.26.
//

import Foundation

/// Pure business logic for diet calculations.
/// Adheres to SRP: Only responsible for the math, not state or UI.
struct DietLogic {
    
    struct BudgetResult {
        let tdee: Double
        let dailyGoal: Double
        let remaining: Double
        let effectiveDeficit: Double
        let isDeficitActive: Bool
    }
    
    static func calculateBudget(
        bmr: Double?,
        activeEnergyYesterday: Double,
        dietaryEnergyToday: Double,
        baseDeficit: Double,
        autoDeficitEnabled: Bool,
        isCurrentlyInDeficitMode: Bool
    ) -> BudgetResult {
        
        let bmrValue = bmr ?? 0
        let tdee = bmrValue + activeEnergyYesterday
        
        let isDeficitActive = autoDeficitEnabled ? isCurrentlyInDeficitMode : true
        // If auto is OFF, we assume the user always wants the deficit (standard behavior),
        // or strictly following the "Maintenance Mode" logic implies deficit is 0 if manually off?
        // Based on original code: "effectiveDeficit = auto ? (mode ? def : 0) : def"
        
        let effectiveDeficit = autoDeficitEnabled
            ? (isCurrentlyInDeficitMode ? baseDeficit : 0)
            : baseDeficit
            
        let dailyGoal = max(tdee - effectiveDeficit, 0)
        let remaining = dailyGoal - dietaryEnergyToday
        
        return BudgetResult(
            tdee: tdee,
            dailyGoal: dailyGoal,
            remaining: remaining,
            effectiveDeficit: effectiveDeficit,
            isDeficitActive: isDeficitActive
        )
    }
}
