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
import SwiftUI

@Observable
class HealthManager: NSObject, WCSessionDelegate {
    var healthStore = HKHealthStore()
    
    var bmr: Double?
    var activeEnergyYesterday: Double = 0
    var activeEnergyToday: Double = 0
    var activeEnergy7DayAvg: Double = 0
    var dietaryEnergyToday: Double = 0
    
    // Nutrients
    var dietaryProteinToday: Double = 0
    var dietaryFiberToday: Double = 0
    var dietaryFatTotalToday: Double = 0
    var dietaryFatSaturatedToday: Double = 0
    var dietarySugarToday: Double = 0
    var dietarySodiumToday: Double = 0
    
    var currentWeight: Double? // 7-Day Average
    var weightTrend: Double?
    
    // Advanced Metrics (7-Day Averages)
    var bodyFat: Double?
    var vo2Max: Double?
    
    // User Stats for Calculations
    var height: Double? // cm
    var age: Int?
    var biologicalSex: HKBiologicalSex = .notSet
    
    // Derived Metric: Physical Activity Level (PAL)
    // Formula: TDEE / BMR = (BMR + ActiveEnergy) / BMR
    var physicalActivityLevel: Double? {
        guard let bmr = bmr, bmr > 0, activeEnergy7DayAvg > 0 else { return nil }
        return (bmr + activeEnergy7DayAvg) / bmr
    }
    
    // Full Weight History for Trend Tab
    var weightHistory: [Date: Double] = [:]
    
    var weightMissingToday: Bool = true
    var isAuthorized: Bool = false
    
    // Preferred Units
    var energyUnit: HKUnit = .kilocalorie()
    var energyUnitString: String = "kcal"
    
    var errorMessage: String?
    
    private let authKey = "hasRequestedHealthAuthorization"
    private var refreshDebounceTask: Task<Void, Never>?
    
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
        if isAuthorized {
            startObserving()
            // Fire fetch immediately but don't await it in init
            fetchData()
        }
        
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
            HKObjectType.quantityType(forIdentifier: .dietarySodium)!,
            // New Metrics
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .vo2Max)!
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
            await updatePreferredUnits()
            
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
    
    func fetchData() {
        // Debounce to prevent UI freezing on rapid updates
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if !Task.isCancelled {
                await refreshData()
            }
        }
    }
    
    func refreshData() async {
        // We use detached tasks inside these methods where appropriate to keep the Main Thread free
        // The methods below will internally switch to MainActor only when assigning data.
        await fetchBMRData()
        await fetchActiveEnergy()
        await fetchNutrientsToday()
        await checkWeightToday()
        await fetchWeightHistory()
        
        await MainActor.run {
            updateWidgetData()
        }
    }
    
    // MARK: - Writing Data
    func logBreakfast(totalKcal: Double, fat: Double, satFat: Double, carbs: Double, sugar: Double, protein: Double, fiber: Double, sodium: Double, date: Date = Date()) async {
        guard isAuthorized else { return }
        
        func createSample(type: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) -> HKQuantitySample {
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            let type = HKQuantityType.quantityType(forIdentifier: type)!
            return HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        }
        
        var samples: [HKObject] = []
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
            // Trigger an immediate UI update
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
        let autoDeficitEnabled = defaults.bool(forKey: "autoDeficitEnabled")
        let isInDeficitMode = defaults.bool(forKey: "isCurrentlyInDeficitMode")
        
        let effectiveDeficit = autoDeficitEnabled ? (isInDeficitMode ? deficit : 0) : deficit
        
        guard let bmr = self.bmr else { return }
        
        // Always use yesterday's active energy for calculation
        let activeEnergy = self.activeEnergyYesterday
        let tdee = bmr + activeEnergy
        let dailyGoal = tdee - effectiveDeficit
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
        
        if let currentWeight = self.currentWeight {
            sharedDefaults?.set(currentWeight, forKey: "currentWeight")
        }
        if let weightTrend = self.weightTrend {
            sharedDefaults?.set(weightTrend, forKey: "weightTrend")
        }
        
        sharedDefaults?.set(Date(), forKey: "lastUpdatedDate")
        WidgetCenter.shared.reloadAllTimelines()
        
        if WCSession.default.isReachable {
             var context: [String: Any] = [
                "remainingCalories": remaining,
                "kcalProgress": kcalProgress,
                "weighedInToday": !self.weightMissingToday,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let cw = self.currentWeight { context["currentWeight"] = cw }
            if let wt = self.weightTrend { context["weightTrend"] = wt }
            try? WCSession.default.updateApplicationContext(context)
        }
    }

    // MARK: - HealthKit Fetching
    private func fetchBMRData() async {
        do {
            let birthDateComponents = try healthStore.dateOfBirthComponents()
            let biologicalSexObj = try healthStore.biologicalSex()
            let biologicalSex = biologicalSexObj.biologicalSex
            
            guard let birthDate = birthDateComponents.date else { return }
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            let age = ageComponents.year ?? 0
            
            let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
            let heightSamples = try await fetchSamples(for: heightType, limit: 1)
            let heightCm = (heightSamples.first?.quantity.doubleValue(for: .meter()) ?? 0) * 100
            
            // --- WEIGHT (7-Day Average) ---
            let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: Date())
            
            // Last 7 days: Day 0 (Today) to Day -6
            let startOfRecent = calendar.date(byAdding: .day, value: -6, to: startOfToday)!
            // Previous 7 days: Day -7 to Day -13
            let startOfPrevious = calendar.date(byAdding: .day, value: -13, to: startOfToday)!
            
            let predicate = HKQuery.predicateForSamples(withStart: startOfPrevious, end: Date(), options: .strictStartDate)
            let recentWeights = try await fetchSamples(for: weightType, predicate: predicate)
            
            // --- Body Fat (7 Day Avg) ---
            let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
            let bfPredicate = HKQuery.predicateForSamples(withStart: startOfRecent, end: Date(), options: .strictStartDate)
            let bfSamples = try await fetchSamples(for: bodyFatType, predicate: bfPredicate)

            // --- VO2 Max (7 Day Avg) ---
            let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max)!
            let vo2Predicate = HKQuery.predicateForSamples(withStart: startOfRecent, end: Date(), options: .strictStartDate)
            let vo2Samples = try await fetchSamples(for: vo2Type, predicate: vo2Predicate)
            
            // ⚠️ CRITICAL: Move Math to background thread (Detached Task)
            // This prevents UI stuttering while iterating over samples
            let result = await Task.detached { () -> (Double?, Double?, Double?, Double?, Double?) in
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
                
                if recentCount > 0 {
                    let avg = recentSum / Double(recentCount)
                    displayWeight = avg
                    weightForBMR = avg
                }
                
                if recentCount > 0 && previousCount > 0 {
                    let currentAvg = recentSum / Double(recentCount)
                    let previousAvg = previousSum / Double(previousCount)
                    trend = currentAvg - previousAvg
                }
                
                // Fallback for BMR calculation if no recent data
                if weightForBMR == 0 {
                    if previousCount > 0 {
                        weightForBMR = previousSum / Double(previousCount)
                    } 
                }
                
                let avgBodyFat: Double? = bfSamples.isEmpty ? nil : (bfSamples.reduce(0) { $0 + $1.quantity.doubleValue(for: .percent()) } / Double(bfSamples.count))

                // ⚠️ FIX: Construct Unit Programmatically to avoid Crash
                let ml = HKUnit.literUnit(with: .milli)
                let kg = HKUnit.gramUnit(with: .kilo)
                let min = HKUnit.minute()
                let vo2Unit = ml.unitDivided(by: kg.unitMultiplied(by: min))
                
                let avgVo2: Double? = vo2Samples.isEmpty ? nil : (vo2Samples.reduce(0) { $0 + $1.quantity.doubleValue(for: vo2Unit) } / Double(vo2Samples.count))
                
                return (displayWeight, trend, weightForBMR, avgBodyFat, avgVo2)
            }.value
            
            let displayWeight = result.0
            let trend = result.1
            var weightForBMR = result.2 ?? 0
            let avgBodyFat = result.3
            let avgVo2 = result.4
            
            // Last ditch fallback for BMR if we still have 0 weight (no data in last 14 days)
            if weightForBMR == 0 {
                let allWeights = try await fetchSamples(for: weightType, limit: 1, sortAscending: false)
                if let newest = allWeights.first {
                    weightForBMR = newest.quantity.doubleValue(for: .gramUnit(with: .kilo))
                }
            }
            
            guard weightForBMR > 0 && heightCm > 0 else { return }
            
            // Mifflin-St Jeor Equation
            let s = (10 * weightForBMR) + (6.25 * heightCm) - (5 * Double(age))
            let finalBMR: Double = {
                switch biologicalSex {
                case .male: return s + 5
                case .female: return s - 161
                default: return s
                }
            }()
            
            // Capture for Actor
            let finalAge = age
            let finalHeight = heightCm
            
            await MainActor.run {
                self.bmr = finalBMR
                self.currentWeight = displayWeight
                self.weightTrend = trend
                
                self.height = finalHeight
                self.age = finalAge
                self.biologicalSex = biologicalSex
                self.bodyFat = avgBodyFat
                self.vo2Max = avgVo2
            }
        } catch {
            print("Error fetching BMR data: \(error)")
        }
    }
    
    private func fetchWeightHistory() async {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        // SAFETY: Limit history to year 2000+
        let limitDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
        let predicate = HKQuery.predicateForSamples(withStart: limitDate, end: Date(), options: .strictStartDate)
        
        do {
            // Fetch is async
            let samples = try await fetchSamples(for: weightType, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            
            // Process on Background Thread
            let history = await Task.detached {
                var dict: [Date: Double] = [:]
                let calendar = Calendar.current
                for sample in samples {
                    let date = calendar.startOfDay(for: sample.startDate)
                    let weight = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    dict[date] = weight
                }
                return dict
            }.value
            
            await MainActor.run {
                self.weightHistory = history
            }
        } catch {
            print("Error fetching weight history: \(error)")
        }
    }
    
    private func fetchActiveEnergy() async {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        // Ranges
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        // 7-day Average: Uses the last 7 COMPLETE days (Yesterday through Yesterday-6)
        // startOf7Days = Today - 7
        // endOf7Days = Today (exclusive) -> so it includes [Today-7...Today-1]
        let startOf7Days = calendar.date(byAdding: .day, value: -7, to: startOfDay)!
        let endOf7Days = startOfDay // This ensures TODAY is excluded from the average
        
        let predicateYesterday = HKQuery.predicateForSamples(withStart: startOfYesterday, end: startOfDay, options: .strictStartDate)
        let predicateToday = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let predicate7Days = HKQuery.predicateForSamples(withStart: startOf7Days, end: endOf7Days, options: .strictStartDate)
        
        // Parallel Fetch
        async let samplesYesterday = (try? await fetchSamples(for: type, predicate: predicateYesterday)) ?? []
        async let samplesToday = (try? await fetchSamples(for: type, predicate: predicateToday)) ?? []
        async let samples7Days = (try? await fetchSamples(for: type, predicate: predicate7Days)) ?? []
        
        let (sY, sT, s7) = await (samplesYesterday, samplesToday, samples7Days)
        
        // Calculate on background
        let result = await Task.detached {
            let y = sY.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            let t = sT.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            // 7-day average: Sum / 7
            let avg = s7.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) } / 7.0
            return (y, t, avg)
        }.value
        
        await MainActor.run {
            self.activeEnergyYesterday = result.0
            self.activeEnergyToday = result.1
            self.activeEnergy7DayAvg = result.2
        }
    }
    
    private func fetchNutrientsToday() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        // Parallel Fetching
        async let samplesEnergy = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, predicate: predicate)) ?? []
        async let samplesProtein = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!, predicate: predicate)) ?? []
        async let samplesFiber = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!, predicate: predicate)) ?? []
        async let samplesFat = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!, predicate: predicate)) ?? []
        async let samplesSatFat = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated)!, predicate: predicate)) ?? []
        async let samplesSugar = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietarySugar)!, predicate: predicate)) ?? []
        async let samplesSodium = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietarySodium)!, predicate: predicate)) ?? []
        
        let (sEnergy, sProtein, sFiber, sFat, sSatFat, sSugar, sSodium) = await (samplesEnergy, samplesProtein, samplesFiber, samplesFat, samplesSatFat, samplesSugar, samplesSodium)
        
        // Background Calculation
        let result = await Task.detached {
            let e = sEnergy.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            let p = sProtein.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let fi = sFiber.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let f = sFat.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let sf = sSatFat.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let su = sSugar.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let so = sSodium.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            return (e, p, fi, f, sf, su, so)
        }.value
        
        await MainActor.run {
            self.dietaryEnergyToday = result.0
            self.dietaryProteinToday = result.1
            self.dietaryFiberToday = result.2
            self.dietaryFatTotalToday = result.3
            self.dietaryFatSaturatedToday = result.4
            self.dietarySugarToday = result.5
            self.dietarySodiumToday = result.6
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
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "autoDeficitEnabled"), let weight = todaysWeight {
                let upper = defaults.double(forKey: "autoDeficitUpperBound")
                let lower = defaults.double(forKey: "autoDeficitLowerBound")
                if upper > lower && lower > 0 {
                    if weight >= upper { defaults.set(true, forKey: "isCurrentlyInDeficitMode") }
                    else if weight <= lower { defaults.set(false, forKey: "isCurrentlyInDeficitMode") }
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
            let query = HKObserverQuery(sampleType: type as! HKSampleType, predicate: nil) { [weak self] query, completionHandler, error in
                guard let self = self, error == nil else {
                    completionHandler()
                    return
                }
                self.fetchData()
                completionHandler()
            }
            healthStore.execute(query)
            healthStore.enableBackgroundDelivery(for: type as! HKSampleType, frequency: .immediate) { _, _ in }
        }
    }
}
