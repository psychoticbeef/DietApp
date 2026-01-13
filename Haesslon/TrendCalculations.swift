import Foundation

// MARK: - Data Models

struct DailyTrendData: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let rawWeight: Double? // Nil if interpolated or missing
    let trendWeight: Double
    let caloricImbalance: Double? // Calculated based on weekly trend delta
    let isProjected: Bool // True if this is a future projection
    
    var isInterpolated: Bool { rawWeight == nil && !isProjected }
}

struct TrendStats: Sendable {
    let currentTrend: Double
    let weeklyChange: Double // Delta over 7 days
    let dailyCaloricImbalance: Double // kcal surplus/deficit
}

// MARK: - Engine

// This enum performs pure calculations and functions as a namespace.
// Marked as Sendable (implicitly true for enums) to be safe.
enum TrendEngine: Sendable {
    
    /// Processes raw HealthKit weight samples into a continuous trend line.
    /// - Parameter weightHistory: Dictionary of Date -> Weight (in kg)
    /// - Returns: Sorted array of DailyTrendData
    nonisolated static func calculateTrend(from weightHistory: [Date: Double]) -> [DailyTrendData] {
        // Defined locally to avoid MainActor isolation inference on global constants
        let smoothingFactorK: Double = 0.1
        let constantKgKcal: Double = 7700.0 // 1 kg = 7700 kcal
        
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
            if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                d = next
            } else {
                break
            }
        }
        
        // Pre-fill weights with interpolation
        let filledWeights = fillGaps(in: weightHistory, for: allDays)
        
        // 3. EWMA Calculation
        var previousTrend: Double? = nil
        
        for day in allDays {
            guard let dailyWeight = filledWeights[day] else { continue }
            let rawWeightDisplay = weightHistory[day]
            
            let trend: Double
            if let prev = previousTrend {
                trend = prev + smoothingFactorK * (dailyWeight - prev)
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
                if let next = calendar.date(byAdding: .day, value: 1, to: projectionDate) {
                    projectionDate = next
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
        }
        
        return result
    }
    
    nonisolated static func getStats(from data: [DailyTrendData]) -> TrendStats? {
        let constantKgKcal: Double = 7700.0 // 1 kg = 7700 kcal
        
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
    
    // MARK: - Generic Metric Calculation
    
    /// Calculates the current EWMA value and the delta compared to 7 days ago.
    /// - Parameters:
    ///   - history: Dictionary of Date -> Value
    ///   - ignoreToday: If true, the calculation stops at yesterday (useful for Active Energy/PAL).
    /// - Returns: (currentEWMA, changeOver7Days)
    nonisolated static func calculateMetricTrend(from history: [Date: Double], ignoreToday: Bool) -> (current: Double?, change: Double?) {
        guard !history.isEmpty else { return (nil, nil) }
        
        let smoothingFactorK: Double = 0.1
        let calendar = Calendar.current
        
        // 1. Sort and Filter Dates
        var sortedDates = history.keys.sorted()
        
        // If ignoring today, remove it from consideration for the "Latest" value
        if ignoreToday {
            let today = calendar.startOfDay(for: Date())
            sortedDates = sortedDates.filter { $0 < today }
        }
        
        guard let startDate = sortedDates.first, let endDate = sortedDates.last else { return (nil, nil) }
        
        // 2. Generate Date Range
        var allDays: [Date] = []
        var d = startDate
        while d <= endDate {
            allDays.append(d)
            if let next = calendar.date(byAdding: .day, value: 1, to: d) {
                d = next
            } else {
                break
            }
        }
        
        // 3. Fill Gaps
        let filledValues = fillGaps(in: history, for: allDays)
        
        // 4. Calculate EWMA Series
        var trends: [Double] = []
        var previousTrend: Double? = nil
        
        for day in allDays {
            guard let val = filledValues[day] else {
                trends.append(previousTrend ?? 0) // Should not happen due to fillGaps
                continue
            }
            
            let trend: Double
            if let prev = previousTrend {
                trend = prev + smoothingFactorK * (val - prev)
            } else {
                trend = val
            }
            
            trends.append(trend)
            previousTrend = trend
        }
        
        guard let current = trends.last else { return (nil, nil) }
        
        // 5. Calculate Change (vs 7 days ago)
        var change: Double? = nil
        if trends.count > 7 {
            let old = trends[trends.count - 1 - 7]
            change = current - old
        }
        
        return (current, change)
    }
    
    // Helper to fill gaps with interpolation or carry-forward
    // Explicitly nonisolated to prevent MainActor inference
    nonisolated private static func fillGaps(in history: [Date: Double], for allDays: [Date]) -> [Date: Double] {
        var filled: [Date: Double] = [:]
        
        var i = 0
        while i < allDays.count {
            let day = allDays[i]
            
            if let val = history[day] {
                filled[day] = val
                i += 1
            } else {
                // Find next known
                var j = i + 1
                var nextKnownIndex: Int? = nil
                while j < allDays.count {
                    if history[allDays[j]] != nil {
                        nextKnownIndex = j
                        break
                    }
                    j += 1
                }
                
                if let nextIndex = nextKnownIndex,
                   i > 0,
                   let startVal = filled[allDays[i-1]],
                   let endVal = history[allDays[nextIndex]] {
                    
                    // Interpolate
                    let totalSteps = Double(nextIndex - (i - 1))
                    let diff = endVal - startVal
                    let stepSize = diff / totalSteps
                    
                    for k in 0..<(nextIndex - i) {
                        let offset = Double(k + 1)
                        let interpDate = allDays[i + k]
                        let interpVal = startVal + (stepSize * offset)
                        filled[interpDate] = interpVal
                    }
                    i = nextIndex
                } else {
                    // Carry forward if no future data
                    if i > 0, let lastVal = filled[allDays[i-1]] {
                        filled[day] = lastVal
                    }
                    i += 1
                }
            }
        }
        return filled
    }
}
