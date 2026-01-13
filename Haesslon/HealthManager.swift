import Foundation
import HealthKit
import Observation
import WidgetKit
import WatchConnectivity
import SwiftUI

@Observable
class HealthManager: NSObject, WCSessionDelegate {
    private let healthStore = HKHealthStore()
    
    // Encapsulated Properties (Read-only externally)
    private(set) var bmr: Double?
    private(set) var activeEnergyYesterday: Double = 0
    private(set) var activeEnergyToday: Double = 0
    private(set) var activeEnergyTrend: Double = 0 // EWMA
    
    private(set) var dietaryEnergyToday: Double = 0
    private(set) var dietaryProteinToday: Double = 0
    private(set) var dietaryFiberToday: Double = 0
    private(set) var dietaryFatTotalToday: Double = 0
    private(set) var dietaryFatSaturatedToday: Double = 0
    private(set) var dietarySugarToday: Double = 0
    private(set) var dietarySodiumToday: Double = 0
    
    private(set) var currentWeight: Double? // EWMA
    private(set) var weightTrend: Double? // Delta vs 7 days ago
    private(set) var bmiTrend: Double?
    
    private(set) var bodyFat: Double? // EWMA
    private(set) var bodyFatTrend: Double? // Delta
    
    private(set) var vo2Max: Double? // EWMA
    private(set) var vo2MaxTrend: Double? // Delta
    
    private(set) var height: Double?
    private(set) var age: Int?
    private(set) var biologicalSex: HKBiologicalSex = .notSet
    
    private(set) var weightHistory: [Date: Double] = [:]
    private(set) var weightMissingToday: Bool = true
    private(set) var isAuthorized: Bool = false
    private(set) var errorMessage: String?
    
    // Units
    private(set) var energyUnit: HKUnit = .kilocalorie()
    private(set) var energyUnitString: String = "kcal"
    
    // Internal
    private var refreshDebounceTask: Task<Void, Never>?
    
    // Derived Metric: Physical Activity Level (PAL)
    // Uses EWMA of Active Energy divided by BMR
    var physicalActivityLevel: Double? {
        guard let bmr = bmr, bmr > 0, activeEnergyTrend > 0 else { return nil }
        return (bmr + activeEnergyTrend) / bmr
    }
    
    // Trend for PAL (Delta)
    // Calculated derived from Active Energy Trend Delta
    private(set) var activeEnergyTrendDelta: Double?
    
    var physicalActivityLevelTrend: Double? {
        guard let bmr = bmr, bmr > 0, let activeDelta = activeEnergyTrendDelta else { return nil }
        return activeDelta / bmr
    }
    
    override init() {
        super.init()
        
        // Restore authorization state
        self.isAuthorized = UserDefaults.standard.bool(forKey: AppConstants.Keys.hasRequestedHealthAuth)
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = String(localized: "Health data not available on this device.")
            return
        }
        
        if isAuthorized {
            startObserving()
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
    
    // MARK: - Authorization
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
            
            UserDefaults.standard.set(true, forKey: AppConstants.Keys.hasRequestedHealthAuth)
            
            await MainActor.run {
                self.isAuthorized = true
                self.startObserving()
                self.fetchData()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Health Access not granted: \(error.localizedDescription)"
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
    
    // MARK: - Data Fetching
    func fetchData() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if !Task.isCancelled {
                await refreshData()
            }
        }
    }
    
    private func refreshData() async {
        // Dependencies
        await fetchHistoryData() // Fetches Weight, BodyFat, VO2Max history & calcs EWMA
        await fetchActiveEnergy() // Fetches Activity history & calcs EWMA
        await fetchNutrientsToday()
        await checkWeightToday()
        
        await MainActor.run {
            updateWidgetData()
        }
    }
    
    // MARK: - Widget Updates
    @MainActor
    func updateWidgetData() {
        let defaults = UserDefaults.standard
        let deficit = defaults.double(forKey: AppConstants.Keys.caloricDeficit)
        let safeDeficit = (deficit == 0 && defaults.object(forKey: AppConstants.Keys.caloricDeficit) == nil) ? 500.0 : deficit
        
        let autoDeficitEnabled = defaults.bool(forKey: AppConstants.Keys.autoDeficitEnabled)
        let isInDeficitMode = defaults.bool(forKey: AppConstants.Keys.isCurrentlyInDeficitMode)
        
        // Ensure we have a weight for calculation (fallback to 70 if completely missing)
        let weightForCalc = self.currentWeight ?? 70.0
        
        let budget = DietLogic.calculateBudget(
            bmr: self.bmr,
            activeEnergyYesterday: self.activeEnergyYesterday,
            dietaryEnergyToday: self.dietaryEnergyToday,
            baseDeficit: safeDeficit,
            autoDeficitEnabled: autoDeficitEnabled,
            isCurrentlyInDeficitMode: isInDeficitMode
        )
        
        let proteinTarget = weightForCalc * 0.8
        let proteinProgress = min(self.dietaryProteinToday / proteinTarget, 1.0)
        let fiberTarget = 30.0
        let fiberProgress = min(self.dietaryFiberToday / fiberTarget, 1.0)
        let kcalProgress = min(self.dietaryEnergyToday / (budget.dailyGoal > 0 ? budget.dailyGoal : 1), 1.0)
        
        let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId)
        sharedDefaults?.set(budget.remaining, forKey: AppConstants.Keys.remainingCalories)
        sharedDefaults?.set(budget.dailyGoal, forKey: AppConstants.Keys.dailyGoal)
        sharedDefaults?.set(kcalProgress, forKey: AppConstants.Keys.kcalProgress)
        sharedDefaults?.set(proteinProgress, forKey: AppConstants.Keys.proteinProgress)
        sharedDefaults?.set(fiberProgress, forKey: AppConstants.Keys.fiberProgress)
        sharedDefaults?.set(!self.weightMissingToday, forKey: AppConstants.Keys.weighedInToday)
        
        if let cw = self.currentWeight { sharedDefaults?.set(cw, forKey: AppConstants.Keys.currentWeight) }
        if let wt = self.weightTrend { sharedDefaults?.set(wt, forKey: AppConstants.Keys.weightTrend) }
        
        sharedDefaults?.set(Date(), forKey: AppConstants.Keys.lastUpdatedDate)
        WidgetCenter.shared.reloadAllTimelines()
        
        // Update Watch
        if WCSession.default.isReachable {
             var context: [String: Any] = [
                AppConstants.Keys.remainingCalories: budget.remaining,
                AppConstants.Keys.kcalProgress: kcalProgress,
                AppConstants.Keys.weighedInToday: !self.weightMissingToday,
                "timestamp": Date().timeIntervalSince1970
            ]
            if let cw = self.currentWeight { context[AppConstants.Keys.currentWeight] = cw }
            if let wt = self.weightTrend { context[AppConstants.Keys.weightTrend] = wt }
            try? WCSession.default.updateApplicationContext(context)
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
            await MainActor.run { self.fetchData() }
        } catch {
            print("Error saving breakfast: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Fetch Implementations (Unified History & EWMA)
    
    private func fetchHistoryData() async {
        do {
            // 1. Basic Bio Data (Height, Age, Sex)
            let birthDateComponents = try healthStore.dateOfBirthComponents()
            let biologicalSexObj = try healthStore.biologicalSex()
            let biologicalSex = biologicalSexObj.biologicalSex
            
            guard let birthDate = birthDateComponents.date else { return }
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            let age = ageComponents.year ?? 0
            
            let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
            let heightSamples = try await fetchSamples(for: heightType, limit: 1)
            let heightCm = (heightSamples.first?.quantity.doubleValue(for: .meter()) ?? 0) * 100
            
            // 2. Fetch History for Trend Calculation
            // UPDATED: Fetch from Year 2000 to ensure Trend View has full history.
            // EWMA calculation will simply converge over this longer period, which is fine/better.
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            
            // Fetch raw samples
            async let sWeight = fetchSamples(for: .quantityType(forIdentifier: .bodyMass)!, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            async let sBF = fetchSamples(for: .quantityType(forIdentifier: .bodyFatPercentage)!, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            async let sVO2 = fetchSamples(for: .quantityType(forIdentifier: .vo2Max)!, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            
            let (weightSamples, bfSamples, vo2Samples) = try await (sWeight, sBF, sVO2)
            
            // Process on background thread
            let result = await Task.detached {
                let calendar = Calendar.current
                
                // Helper to map samples to [Date: Double] (Day -> Value)
                func processSamples(_ samples: [HKQuantitySample], unit: HKUnit) -> [Date: Double] {
                    var map: [Date: [Double]] = [:]
                    for s in samples {
                        let day = calendar.startOfDay(for: s.startDate)
                        let val = s.quantity.doubleValue(for: unit)
                        map[day, default: []].append(val)
                    }
                    return map.mapValues { $0.reduce(0, +) / Double($0.count) }
                }
                
                // Process Weight
                let weightMap = processSamples(weightSamples, unit: .gramUnit(with: .kilo))
                let (wEWMA, wTrend) = TrendEngine.calculateMetricTrend(from: weightMap, ignoreToday: false)
                
                // Calculate BMI Trend
                var bmiDelta: Double? = nil
                if let wt = wTrend, heightCm > 0 {
                    let hM = heightCm / 100.0
                    bmiDelta = wt / (hM * hM)
                }
                
                // Process Body Fat
                let bfMap = processSamples(bfSamples, unit: .percent())
                let (bfEWMA, bfTrend) = TrendEngine.calculateMetricTrend(from: bfMap, ignoreToday: false)
                
                // Process VO2 Max
                let ml = HKUnit.literUnit(with: .milli)
                let kg = HKUnit.gramUnit(with: .kilo)
                let min = HKUnit.minute()
                let vo2Unit = ml.unitDivided(by: kg.unitMultiplied(by: min))
                let vo2Map = processSamples(vo2Samples, unit: vo2Unit)
                let (vo2EWMA, vo2Trend) = TrendEngine.calculateMetricTrend(from: vo2Map, ignoreToday: false)
                
                return (weightMap, wEWMA, wTrend, bmiDelta, bfEWMA, bfTrend, vo2EWMA, vo2Trend)
            }.value
            
            // BMR Calculation (Mifflin-St Jeor)
            // Uses EWMA Weight for stability
            let weightForBMR = result.1 ?? 70.0 // fallback
            
            let s = (10 * weightForBMR) + (6.25 * heightCm) - (5 * Double(age))
            let finalBMR: Double = {
                switch biologicalSex {
                case .male: return s + 5
                case .female: return s - 161
                default: return s
                }
            }()
            
            await MainActor.run {
                self.weightHistory = result.0
                self.currentWeight = result.1
                self.weightTrend = result.2
                self.bmiTrend = result.3
                self.bodyFat = result.4
                self.bodyFatTrend = result.5
                self.vo2Max = result.6
                self.vo2MaxTrend = result.7
                
                self.height = heightCm
                self.age = age
                self.biologicalSex = biologicalSex
                self.bmr = finalBMR
            }
        } catch {
            print("Error fetching history data: \(error)")
        }
    }
    
    private func fetchActiveEnergy() async {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let calendar = Calendar.current
        
        // Fetch last 60 days to warm up EWMA (Keep limited to preserve performance)
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -60, to: endDate)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        do {
            let samples = try await fetchSamples(for: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortAscending: true)
            
            let result = await Task.detached {
                let calendar = Calendar.current
                
                // 1. Sum by Day
                var dailySum: [Date: Double] = [:]
                for s in samples {
                    let day = calendar.startOfDay(for: s.startDate)
                    let val = s.quantity.doubleValue(for: .kilocalorie())
                    dailySum[day, default: 0] += val
                }
                
                // 2. Extract Specific Days for Dashboard (Raw values)
                let startToday = calendar.startOfDay(for: Date())
                let startYesterday = calendar.date(byAdding: .day, value: -1, to: startToday)!
                
                let todayVal = dailySum[startToday] ?? 0
                let yesterdayVal = dailySum[startYesterday] ?? 0
                
                // 3. Calculate EWMA Trend
                // IMPORTANT: ignoreToday = true, because today's activity is incomplete and would drag the trend down artificially.
                let (ewma, delta) = TrendEngine.calculateMetricTrend(from: dailySum, ignoreToday: true)
                
                return (todayVal, yesterdayVal, ewma, delta)
            }.value
            
            await MainActor.run {
                self.activeEnergyToday = result.0
                self.activeEnergyYesterday = result.1
                self.activeEnergyTrend = result.2 ?? 0
                self.activeEnergyTrendDelta = result.3
            }
        } catch {
            print("Error fetching active energy: \(error)")
        }
    }
    
    private func fetchNutrientsToday() async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        
        async let sEnergy = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)!, predicate: predicate)) ?? []
        async let sProtein = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryProtein)!, predicate: predicate)) ?? []
        async let sFiber = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFiber)!, predicate: predicate)) ?? []
        async let sFat = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal)!, predicate: predicate)) ?? []
        async let sSatFat = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietaryFatSaturated)!, predicate: predicate)) ?? []
        async let sSugar = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietarySugar)!, predicate: predicate)) ?? []
        async let sSodium = (try? await fetchSamples(for: HKQuantityType.quantityType(forIdentifier: .dietarySodium)!, predicate: predicate)) ?? []
        
        let (energy, protein, fiber, fat, satFat, sugar, sodium) = await (sEnergy, sProtein, sFiber, sFat, sSatFat, sSugar, sSodium)
        
        let result = await Task.detached {
            let e = energy.reduce(0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            let p = protein.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let fi = fiber.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let f = fat.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let sf = satFat.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let su = sugar.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
            let so = sodium.reduce(0) { $0 + $1.quantity.doubleValue(for: .gram()) }
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
            
            // Auto Deficit Check
            if defaults.bool(forKey: AppConstants.Keys.autoDeficitEnabled), let weight = todaysWeight {
                let upper = defaults.double(forKey: AppConstants.Keys.autoDeficitUpperBound)
                let lower = defaults.double(forKey: AppConstants.Keys.autoDeficitLowerBound)
                
                if upper > lower && lower > 0 {
                    if weight >= upper {
                        defaults.set(true, forKey: AppConstants.Keys.isCurrentlyInDeficitMode)
                    } else if weight <= lower {
                        defaults.set(false, forKey: AppConstants.Keys.isCurrentlyInDeficitMode)
                    }
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
