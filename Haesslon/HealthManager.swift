//
//  HealthManager.swift
//  Haesslon
//
//  Created by Daniel Arndt on 09.01.26.
//

import Foundation
import HealthKit
import Observation
import WidgetKit
import WatchConnectivity
import SwiftUI // Needed for AppStorage/UserDefaults access convenience if used directly, but we use UserDefaults standard

@Observable
class HealthManager: NSObject, WCSessionDelegate {
    var healthStore = HKHealthStore()
    
    var bmr: Double?
    var activeEnergyYesterday: Double = 0
    var activeEnergyToday: Double = 0
    var dietaryEnergyToday: Double = 0
    
    // Nutrients
    var dietaryProteinToday: Double = 0
    var dietaryFiberToday: Double = 0
    var dietaryFatTotalToday: Double = 0
    var dietaryFatSaturatedToday: Double = 0
    var dietarySugarToday: Double = 0
    var dietarySodiumToday: Double = 0
    
    var currentWeight: Double?
    var weightTrend: Double?
    
    // Full Weight History for Trend Tab
    var weightHistory: [Date: Double] = [:]
    
    var weightMissingToday: Bool = true
    var isAuthorized: Bool = false
    
    // Preferred Units
    var energyUnit: HKUnit = .kilocalorie()
    var energyUnitString: String = "kcal"
    
    var errorMessage: String?
    
    private let authKey = "hasRequestedHealthAuthorization"
    
    override init() {
        super.init()
        
        // Restore authorization state from persistence to allow background startup
        self.isAuthorized = UserDefaults.standard.bool(forKey: authKey)
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = String(localized: "Health data not available on this device.")
            return
        }
        
        // Automatically start observing if we are authorized.
        // This is critical for background launches.
        if isAuthorized {
            startObserving()
            // We also fetch data immediately to ensure the app state is fresh
            fetchData()
        }
        
        // Listen for the day changing while the app is running
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dayChanged),
            name: .NSCalendarDayChanged,
            object: nil
        )
    }
    
    @objc func dayChanged() {
        fetchData()
    }
    
    // MARK: - WCSessionDelegate
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    
    func requestAuthorization() async {
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
            HKObjectType.quantityType(forIdentifier: .dietarySodium)!
        ]
        
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatSaturated)!,
            HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
            HKObjectType.quantityType(forIdentifier: .dietarySugar)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            HKObjectType.quantityType(forIdentifier: .dietarySodium)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            await updatePreferredUnits() // Fetch units after auth
            
            // Persist that we have requested auth so we can start observing on next launch
            UserDefaults.standard.set(true, forKey: authKey)
            
            await MainActor.run {
                self.isAuthorized = true
                self.startObserving()
                self.fetchData()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = String(localized: "Health Access not granted: \(error.localizedDescription)")
            }
        }
    }
    
    func updatePreferredUnits() async {
        let energyType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
        let units = try? await healthStore.preferredUnits(for: [energyType])
        if let unit = units?[energyType] {
            await MainActor.run {
                self.energyUnit = unit
                self.energyUnitString = unit == .kilocalorie() ? "kcal" : "kJ"
            }
        }
    }
    
    // Fire-and-forget fetch for UI
    func fetchData() {
        Task {
            await refreshData()
        }
    }
    
    // Awaitable fetch for background tasks
    func refreshData() async {
        await fetchBMRData()
        await fetchActiveEnergy()
        await fetchNutrientsToday()
        await checkWeightToday()
        await fetchWeightHistory()
        
        await MainActor.run {
            updateWidgetData()
        }
    }
    
    // MARK: - Writing Data (Inputs are assumed kcal for calculation, then converted)
    func logBreakfast(
        totalKcal: Double,
        fat: Double,
        satFat: Double,
        carbs: Double,
        sugar: Double,
        protein: Double,
        fiber: Double,
        sodium: Double,
        date: Date = Date()
    ) async {
        guard isAuthorized else { return }
        
        func createSample(type: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) -> HKQuantitySample {
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            let type = HKQuantityType.quantityType(forIdentifier: type)!
            return HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        }
        
        var samples: [HKObject] = []
        
        // We use the preferred unit here so HK doesn't double convert if not needed,
        // BUT our input 'totalKcal' from UI is likely still kcal if we haven't updated the input fields yet.
        // For now, let's assume the input function passes kcal, and we save as kcal.
        // HealthKit handles unit conversion internally when reading back.
        samples.append(createSample(type: .dietaryEnergyConsumed, value: totalKcal, unit: .kilocalorie()))
        
        if fat > 0 { samples.append(createSample(type: .dietaryFatTotal, value: fat, unit: .gram())) }
        if satFat > 0 { samples.append(createSample(type: .dietaryFatSaturated, value: satFat, unit: .gram())) }
        if carbs > 0 { samples.append(createSample(type: .dietaryCarbohydrates, value: carbs, unit: .gram())) }
        if sugar > 0 { samples.append(createSample(type: .dietarySugar, value: sugar, unit: .gram())) }
        if protein > 0 { samples.append(createSample(type: .dietaryProtein, value: protein, unit: .gram())) }
        if fiber > 0 { samples.append(createSample(type: .dietaryFiber, value: fiber, unit: .gram())) }
        if sodium > 0 { samples.append(createSample(type: .dietarySodium, value: sodium / 1000.0, unit: .gram())) }
        
        do {
            try await healthStore.save(samples)
            await MainActor.run { self.fetchData() }
        } catch {
            print("Error saving breakfast: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Widget Logic
    @MainActor
    func updateWidgetData() {
        let defaults = UserDefaults.standard
        let deficit = defaults.object(forKey: "caloricDeficit") as? Double ?? 500.0
        let useActiveEnergyToday = defaults.bool(forKey: "useActiveEnergyToday")
        
        // Auto Deficit Logic Check
        let autoDeficitEnabled = defaults.bool(forKey: "autoDeficitEnabled")
        let isInDeficitMode = defaults.bool(forKey: "isCurrentlyInDeficitMode")
        
        let effectiveDeficit: Double
        if autoDeficitEnabled {
            effectiveDeficit = isInDeficitMode ? deficit : 0
        } else {
            effectiveDeficit = deficit
        }
        
        guard let bmr = self.bmr else { return }
        
        // Internal calculations still in kcal for consistency
        let activeEnergy = useActiveEnergyToday ? self.activeEnergyToday : self.activeEnergyYesterday
        let tdee = bmr + activeEnergy
        let dailyGoal = tdee - effectiveDeficit
        
        // Convert to preferred unit for display if needed, but Widget usually expects kcal
        // For simplicity, we keep the Widget in kcal as it is "Calorie Budget"
        let remaining = dailyGoal - self.dietaryEnergyToday
        
        let kcalProgress = min(self.dietaryEnergyToday / (dailyGoal > 0 ? dailyGoal : 1), 1.0)
        let weight = self.currentWeight ?? 70
        let proteinTarget = weight * 0.8
        let proteinProgress = min(self.dietaryProteinToday / proteinTarget, 1.0)
        let fiberTarget = 30.0
        let fiberProgress = min(self.dietaryFiberToday / fiberTarget, 1.0)
        
        let sharedDefaults = UserDefaults(suiteName: "group.com.haesslon.shared")
        sharedDefaults?.set(remaining, forKey: "remainingCalories")
        sharedDefaults?.set(kcalProgress, forKey: "kcalProgress")
        sharedDefaults?.set(proteinProgress, forKey: "proteinProgress")
        sharedDefaults?.set(fiberProgress, forKey: "fiberProgress")
        sharedDefaults?.set(!self.weightMissingToday, forKey: "weighedInToday")
        
        // Save weight and trend for display in Widget
        if let currentWeight = self.currentWeight {
            sharedDefaults?.set(currentWeight, forKey: "currentWeight")
        } else {
            sharedDefaults?.removeObject(forKey: "currentWeight")
        }
        
        if let weightTrend = self.weightTrend {
            sharedDefaults?.set(weightTrend, forKey: "weightTrend")
        } else {
            sharedDefaults?.removeObject(forKey: "weightTrend")
        }
        
        // Save date to allow widget to invalidate old data
        sharedDefaults?.set(Date(), forKey: "lastUpdatedDate")
        
        WidgetCenter.shared.reloadAllTimelines()
        
        if WCSession.default.isReachable {
             var context: [String: Any] = [
                "remainingCalories": remaining,
                "kcalProgress": kcalProgress,
                "weighedInToday": !self.weightMissingToday,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            if let currentWeight = self.currentWeight {
                context["currentWeight"] = currentWeight
            }
            if let weightTrend = self.weightTrend {
                context["weightTrend"] = weightTrend
            }
            
            try? WCSession.default.updateApplicationContext(context)
        }
    }

    // MARK: - HealthKit Fetching
    private func fetchBMRData() async {
        do {
            let birthDateComponents = try healthStore.dateOfBirthComponents()
            let biologicalSex = try healthStore.biologicalSex()
            
            guard let birthDate = birthDateComponents.date else { return }
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            let age = Double(ageComponents.year ?? 0)
            
            let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
            let heightSamples = try await fetchSamples(for: heightType, limit: 1)
            guard let heightSample = heightSamples.first else { return }
            let heightCm = heightSample.quantity.doubleValue(for: .meter()) * 100
            
            let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            
            // Range calculations
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            
            // Last 14 days: Day 0 (Today) to Day -13
            let startOfRecent = calendar.date(byAdding: .day, value: -13, to: startOfToday)!
            // Previous 14 days: Day -14 to Day -27
            let startOfPrevious = calendar.date(byAdding: .day, value: -27, to: startOfToday)!
            
            // Fetch all potentially relevant samples (last 28 days)
            let predicate = HKQuery.predicateForSamples(withStart: startOfPrevious, end: Date(), options: .strictStartDate)
            let recentWeights = try await fetchSamples(for: weightType, predicate: predicate)
            
            var recentSum: Double = 0
            var recentCount: Int = 0
            var previousSum: Double = 0
            var previousCount: Int = 0
            
            for sample in recentWeights {
                let weightVal = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                if sample.startDate >= startOfRecent {
                    recentSum += weightVal
                    recentCount += 1
                } else {
                    previousSum += weightVal
                    previousCount += 1
                }
            }
            
            var displayWeight: Double?
            var trend: Double?
            var weightForBMR: Double = 0
            
            // Calculate Current (Recent) Average
            if recentCount > 0 {
                let avg = recentSum / Double(recentCount)
                displayWeight = avg
                weightForBMR = avg
            }
            
            // Calculate Trend
            if recentCount > 0 && previousCount > 0 {
                let currentAvg = recentSum / Double(recentCount)
                let previousAvg = previousSum / Double(previousCount)
                trend = currentAvg - previousAvg
            }
            
            // Fallback for BMR if no recent data (displayWeight will remain nil)
            if weightForBMR == 0 {
                // If we have previous period data but not recent, use previous for BMR
                if previousCount > 0 {
                    weightForBMR = previousSum / Double(previousCount)
                } else {
                    // Fallback to oldest known weight if no data in last 28 days
                    let allWeights = try await fetchSamples(for: weightType, limit: 1, sortAscending: true)
                    if let oldest = allWeights.first {
                        weightForBMR = oldest.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    }
                }
            }
            
            // Ensure we have a valid weight for BMR calculation before proceeding
            guard weightForBMR > 0 else { return }
            
            // Mifflin-St Jeor Equation (returns kcal/day)
            let s = (10 * weightForBMR) + (6.25 * heightCm) - (5 * age)
            
            // Calculate final value as a 'let' to avoid Swift 6 concurrency capture errors
            let finalBMR: Double = {
                switch biologicalSex.biologicalSex {
                case .male: return s + 5
                case .female: return s - 161
                default: return s
                }
            }()
            
            // Capture these immutable values for the MainActor closure to satisfy Swift 6
            let finalDisplayWeight = displayWeight
            let finalTrend = trend
            
            await MainActor.run {
                self.bmr = finalBMR
                self.currentWeight = finalDisplayWeight
                self.weightTrend = finalTrend
            }
        } catch {
            print("Error fetching BMR data: \(error)")
        }
    }
    
    // Fetch full history for the trend graph
    private func fetchWeightHistory() async {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        // Fetch all data (no start date limit)
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictStartDate)
        
        do {
            let samples = try await fetchSamples(for: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            
            var history: [Date: Double] = [:]
            let calendar = Calendar.current
            
            for sample in samples {
                let date = calendar.startOfDay(for: sample.startDate)
                let weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                // Duplicate handling: latest wins (iteration order is ascending start date)
                history[date] = weight
            }
            
            let finalHistory = history
            await MainActor.run {
                self.weightHistory = finalHistory
            }
        } catch {
            print("Error fetching weight history: \(error)")
        }
    }
    
    private func fetchActiveEnergy() async {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let startOfYesterday = calendar.startOfDay(for: yesterday)
        let endOfYesterday = startOfDay
        
        let predicateYesterday = HKQuery.predicateForSamples(withStart: startOfYesterday, end: endOfYesterday, options: .strictStartDate)
        let samplesYesterday = try? await fetchSamples(for: type, predicate: predicateYesterday)
        // Store internally as kcal for math consistency
        let totalYesterday = samplesYesterday?.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) } ?? 0
        
        let predicateToday = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let samplesToday = try? await fetchSamples(for: type, predicate: predicateToday)
        let totalToday = samplesToday?.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) } ?? 0
        
        await MainActor.run {
            self.activeEnergyYesterday = totalYesterday
            self.activeEnergyToday = totalToday
        }
    }
    
    private func fetchNutrientsToday() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        func sum(identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
            guard let samples = try? await fetchSamples(for: type, predicate: predicate) else { return 0 }
            return samples.reduce(0) { $0 + $1.quantity.doubleValue(for: unit) }
        }
        
        // Fetch energy in KCAL always for internal consistency
        let energy = await sum(identifier: .dietaryEnergyConsumed, unit: .kilocalorie())
        let protein = await sum(identifier: .dietaryProtein, unit: .gram())
        let fiber = await sum(identifier: .dietaryFiber, unit: .gram())
        let fatTotal = await sum(identifier: .dietaryFatTotal, unit: .gram())
        let fatSat = await sum(identifier: .dietaryFatSaturated, unit: .gram())
        let sugar = await sum(identifier: .dietarySugar, unit: .gram())
        let sodium = await sum(identifier: .dietarySodium, unit: .gram())
        
        await MainActor.run {
            self.dietaryEnergyToday = energy
            self.dietaryProteinToday = protein
            self.dietaryFiberToday = fiber
            self.dietaryFatTotalToday = fatTotal
            self.dietaryFatSaturatedToday = fatSat
            self.dietarySugarToday = sugar
            self.dietarySodiumToday = sodium
        }
    }
    
    private func checkWeightToday() async {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        let samples = try? await fetchSamples(for: type, predicate: predicate, sortAscending: false)
        let todaysWeight = samples?.first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        
        await MainActor.run {
            self.weightMissingToday = samples?.isEmpty ?? true
            
            // Update Auto Deficit logic if user has enabled it
            // Logic:
            // - If weight >= UpperBound -> Deficit ON
            // - If weight <= LowerBound -> Deficit OFF
            // - Else -> Maintain current state
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "autoDeficitEnabled"), let weight = todaysWeight {
                let upper = defaults.double(forKey: "autoDeficitUpperBound")
                let lower = defaults.double(forKey: "autoDeficitLowerBound")
                
                // Only act if bounds are valid
                if upper > lower && lower > 0 {
                    if weight >= upper {
                        defaults.set(true, forKey: "isCurrentlyInDeficitMode")
                    } else if weight <= lower {
                        defaults.set(false, forKey: "isCurrentlyInDeficitMode")
                    }
                    // If in between, do nothing (hysteresis)
                }
            }
        }
    }
    
    private func fetchSamples(for type: HKSampleType, predicate: NSPredicate? = nil, limit: Int = HKObjectQueryNoLimit, sortAscending: Bool = false) async throws -> [HKQuantitySample] {
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: sortAscending)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let quantitySamples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                continuation.resume(returning: quantitySamples)
            }
            healthStore.execute(query)
        }
    }
    
    func startObserving() {
        guard isAuthorized else { return }
        
        let types: [HKObjectType] = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .dietaryProtein)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFiber)!,
            HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]
        
        for type in types {
            // Using HKObserverQuery with completion handler is required for background delivery
            let query = HKObserverQuery(sampleType: type as! HKSampleType, predicate: nil) { [weak self] query, completionHandler, error in
                guard let self = self, error == nil else {
                    // Even if error or self is nil, we should call completion if possible,
                    // but if self is nil we can't do much.
                    // If error exists, we still need to signal we are done handling this event.
                    completionHandler()
                    return
                }
                
                // Perform the update
                Task {
                    await self.refreshData()
                    // Signal HealthKit that we are done
                    completionHandler()
                }
            }
            
            healthStore.execute(query)
            
            // Enable background delivery
            healthStore.enableBackgroundDelivery(for: type as! HKSampleType, frequency: .immediate) { success, error in
                if let error = error {
                    print("Failed to enable background delivery for \(type.identifier): \(error.localizedDescription)")
                }
            }
        }
    }
}
