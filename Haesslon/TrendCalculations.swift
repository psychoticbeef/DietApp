import Foundation

// MARK: - Data Models
struct DailyTrendData: Identifiable {
    let id = UUID()
    let date: Date
    let rawWeight: Double? // Nil if interpolated or missing
    let trendWeight: Double
    let caloricImbalance: Double? // Calculated based on weekly trend delta
    let isProjected: Bool // True if this is a future projection
    
    var isInterpolated: Bool { rawWeight == nil && !isProjected }
}

struct TrendStats {
    let currentTrend: Double
    let weeklyChange: Double // Delta over 7 days
    let dailyCaloricImbalance: Double // kcal surplus/deficit
}

// MARK: - Engine
struct TrendEngine {
    private let k: Double = 0.1
    private let constantKgKcal: Double = 7700.0 // 1 kg = 7700 kcal
    
    /// Processes raw HealthKit weight samples into a continuous trend line.
    /// - Parameter weightHistory: Dictionary of Date -> Weight (in kg)
    /// - Returns: Sorted array of DailyTrendData
    func calculateTrend(from weightHistory: [Date: Double]) -> [DailyTrendData] {
        guard !weightHistory.isEmpty else { return [] }
        
        // 1. Sort dates
        let sortedDates = weightHistory.keys.sorted()
        guard let startDate = sortedDates.first, let endDate = sortedDates.last else { return [] }
        
        // 2. Generate full date range (fill gaps)
        var result: [DailyTrendData] = []
        let calendar = Calendar.current
        
        // Iterate day by day from start to end (or today)
        let targetEndDate = max(endDate, calendar.startOfDay(for: Date()))
        
        var allDays: [Date] = []
        var d = startDate
        while d <= targetEndDate {
            allDays.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        
        // Pre-fill weights with interpolation
        var filledWeights: [Date: Double] = [:]
        
        var i = 0
        while i < allDays.count {
            let day = allDays[i]
            
            if let w = weightHistory[day] {
                filledWeights[day] = w
                i += 1
            } else {
                // Gap detected. Find next known weight.
                var j = i + 1
                var nextKnownIndex: Int? = nil
                while j < allDays.count {
                    if weightHistory[allDays[j]] != nil {
                        nextKnownIndex = j
                        break
                    }
                    j += 1
                }
                
                if let nextIndex = nextKnownIndex, 
                   let startWeight = filledWeights[allDays[i-1]], 
                   let endWeight = weightHistory[allDays[nextIndex]] {
                    
                    // Interpolate between (i-1) and nextIndex
                    let totalSteps = Double(nextIndex - (i - 1))
                    let weightDiff = endWeight - startWeight
                    let stepSize = weightDiff / totalSteps
                    
                    for k in 0..<(nextIndex - i) {
                        let offset = Double(k + 1)
                        let interpolatedDate = allDays[i + k]
                        let interpolatedWeight = startWeight + (stepSize * offset)
                        filledWeights[interpolatedDate] = interpolatedWeight
                    }
                    i = nextIndex // Jump to the known weight
                } else {
                    // No future data (trailing gap up to today).
                    // Carry forward the last weight to maintain the line
                    if i > 0, let lastW = filledWeights[allDays[i-1]] {
                        filledWeights[day] = lastW
                    }
                    i += 1
                }
            }
        }
        
        // 3. EWMA Calculation
        var previousTrend: Double? = nil
        
        for day in allDays {
            guard let dailyWeight = filledWeights[day] else { continue }
            let rawWeightDisplay = weightHistory[day]
            
            let trend: Double
            if let prev = previousTrend {
                trend = prev + k * (dailyWeight - prev)
            } else {
                trend = dailyWeight
            }
            
            // 4. Rate of Change (Weekly Delta)
            var imbalance: Double? = nil
            if result.count >= 7 {
                let trend7DaysAgo = result[result.count - 7].trendWeight
                let deltaWeekly = trend - trend7DaysAgo
                imbalance = (deltaWeekly * constantKgKcal) / 7.0
            }
            
            let entry = DailyTrendData(
                date: day,
                rawWeight: rawWeightDisplay,
                trendWeight: trend,
                caloricImbalance: imbalance,
                isProjected: false
            )
            result.append(entry)
            previousTrend = trend
        }
        
        // 5. Future Projection (14 Days)
        if let lastEntry = result.last {
            // Calculate daily rate of change based on last 7 days (or less if not available)
            // Use the last calculated imbalance to derive rate
            let dailyRateKg: Double
            if let imbalance = lastEntry.caloricImbalance {
                // Imbalance = (DeltaWeekly * C) / 7  -> DailyDelta = Imbalance / C
                dailyRateKg = imbalance / constantKgKcal
            } else {
                dailyRateKg = 0
            }
            
            var projectionDate = lastEntry.date
            var projectionTrend = lastEntry.trendWeight
            
            for _ in 1...14 {
                projectionDate = calendar.date(byAdding: .day, value: 1, to: projectionDate)!
                projectionTrend += dailyRateKg
                
                let entry = DailyTrendData(
                    date: projectionDate,
                    rawWeight: nil,
                    trendWeight: projectionTrend,
                    caloricImbalance: lastEntry.caloricImbalance, // Assume constant rate
                    isProjected: true
                )
                result.append(entry)
            }
        }
        
        return result
    }
    
    func getStats(from data: [DailyTrendData]) -> TrendStats? {
        // Find last REAL data point (not projected)
        guard let lastReal = data.last(where: { !$0.isProjected }) else { return nil }
        
        let imbalance = lastReal.caloricImbalance ?? 0
        let delta = (imbalance * 7.0) / constantKgKcal
        
        return TrendStats(
            currentTrend: lastReal.trendWeight,
            weeklyChange: delta,
            dailyCaloricImbalance: imbalance
        )
    }
}
