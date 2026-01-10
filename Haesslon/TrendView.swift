import SwiftUI
import Charts
import HealthKit

struct TrendView: View {
    @Environment(HealthManager.self) private var healthManager
    
    @State private var trendData: [DailyTrendData] = []
    @State private var stats: TrendStats?
    
    // Zoom/Scroll State
    @State private var visibleDays: Double = 90.0 // Default to 3 months
    @State private var scrollPosition = Date() // ChartScrollPosition represents LEADING edge
    @State private var initialVisibleDays: Double? = nil // For gesture calculation
    @State private var initialScrollDate: Date? = nil // For gesture anchoring
    @State private var hasPerformedInitialScroll: Bool = false
    
    // Y-Axis State
    @State private var yAxisDomain: ClosedRange<Double> = 0...100
    @State private var isInteracting: Bool = false
    @State private var scrollDebounceTask: Task<Void, Never>? = nil
    
    // Calculation Task
    @State private var calculationTask: Task<Void, Never>? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Header Stats
                if let stats = stats {
                    HStack(spacing: 20) {
                        statView(
                            label: "Trend",
                            value: String(format: "%.1f", stats.currentTrend),
                            unit: "kg",
                            color: .primary
                        )
                        
                        statView(
                            label: "Weekly Change",
                            value: String(format: "%+.2f", stats.weeklyChange),
                            unit: "kg",
                            color: stats.weeklyChange > 0 ? .red : .green
                        )
                        
                        statView(
                            label: "Est. Imbalance",
                            value: String(format: "%+.0f", stats.dailyCaloricImbalance),
                            unit: "kcal",
                            color: stats.dailyCaloricImbalance > 0 ? .red : .green
                        )
                    }
                    .padding(.horizontal)
                }
                
                // Chart Area
                VStack(alignment: .leading) {
                    Chart {
                        // 1. History Line
                        ForEach(visibleHistoryData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Trend", point.trendWeight),
                                series: .value("Type", "History")
                            )
                            .foregroundStyle(Color.blue)
                            .interpolationMethod(.catmullRom)
                        }
                        
                        // 2. Projection Line
                        ForEach(visibleProjectionData) { point in
                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Trend", point.trendWeight),
                                series: .value("Type", "Projection")
                            )
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                            .interpolationMethod(.monotone)
                        }
                        
                        // 3. Raw Weight Dots
                        ForEach(visibleRawData) { point in
                            if let weight = point.rawWeight {
                                PointMark(
                                    x: .value("Date", point.date),
                                    y: .value("Weight", weight)
                                )
                                .foregroundStyle(Color.gray.opacity(0.5))
                                .symbolSize(20)
                            }
                        }
                    }
                    .chartYScale(domain: yAxisDomain)
                    .chartXScale(domain: xAxisDomain)
                    .chartScrollableAxes(isInteracting ? [] : .horizontal) // Disable native scrolling while interacting
                    .chartXVisibleDomain(length: visibleDays * 86400)
                    .chartScrollPosition(x: $scrollPosition)
                    .frame(height: 350)
                    // Use simultaneousGesture to allow Chart scrolling AND custom pinch
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { val in
                                isInteracting = true
                                if initialVisibleDays == nil {
                                    initialVisibleDays = visibleDays
                                    initialScrollDate = scrollPosition
                                }
                                
                                if let baseDays = initialVisibleDays, let baseDate = initialScrollDate {
                                    // Calculate the fixed point (Right Edge)
                                    // We anchor to the right side to keep "Today" visible when zooming in/out
                                    // if the user was looking at today.
                                    let rightEdge = baseDate.addingTimeInterval(baseDays * 86400)
                                    
                                    // Calculate new duration
                                    let newDays = baseDays / val
                                    
                                    // Clamp
                                    let clampedDays = max(7, min(newDays, 365 * 50))
                                    visibleDays = clampedDays
                                    
                                    // Adjust scroll position to keep right edge constant
                                    let newStart = rightEdge.addingTimeInterval(-(clampedDays * 86400))
                                    scrollPosition = newStart
                                }
                            }
                            .onEnded { _ in
                                isInteracting = false
                                initialVisibleDays = nil
                                initialScrollDate = nil
                                snapToNearestLevel()
                                updateYDomain()
                            }
                    )
                }
                .padding()
                
                // Dynamic Label
                Text(currentViewLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                Spacer()
            }
            .navigationTitle("Trend")
            .onChange(of: healthManager.weightHistory) {
                calculate()
            }
            .onChange(of: scrollPosition) {
                // Debounce the update to prevent constant rescaling during scroll
                if !isInteracting {
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                        if !Task.isCancelled {
                            await MainActor.run {
                                updateYDomain()
                            }
                        }
                    }
                }
            }
            .onAppear {
                calculate()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentViewLabel: String {
        let days = Int(visibleDays)
        let totalHistory = trendData.count
        
        // Define tolerance for "close enough" to standard levels
        func isClose(to target: Int, tolerance: Int = 5) -> Bool {
            abs(days - target) <= tolerance
        }
        
        if isClose(to: 90) { return "3 Months" }
        if isClose(to: 365) { return "1 Year" }
        if isClose(to: 1825) { return "5 Years" }
        // If we are showing roughly the full history (and history is significantly long)
        if days >= totalHistory - 5 && totalHistory > 10 { return "All Time" }
        
        return "\(days) days"
    }
    
    // MARK: - Optimization: Viewport Filtering
    
    private var visibleRange: ClosedRange<Date> {
        // Calculate the current visible window
        let start = scrollPosition
        let end = scrollPosition.addingTimeInterval(visibleDays * 86400)
        
        // Add a buffer (50% on each side) to prevent lines popping in/out during scroll
        let buffer = (visibleDays * 86400) * 0.5
        let bufferedStart = start.addingTimeInterval(-buffer)
        let bufferedEnd = end.addingTimeInterval(buffer)
        
        return bufferedStart...bufferedEnd
    }
    
    private var visibleHistoryData: [DailyTrendData] {
        let range = visibleRange
        return trendData.filter { !$0.isProjected && $0.date >= range.lowerBound && $0.date <= range.upperBound }
    }
    
    private var visibleProjectionData: [DailyTrendData] {
        let range = visibleRange
        let projected = trendData.filter { $0.isProjected && $0.date >= range.lowerBound && $0.date <= range.upperBound }
        
        if !projected.isEmpty, let lastHistory = trendData.last(where: { !$0.isProjected }) {
            let bridgePoint = DailyTrendData(
                date: lastHistory.date,
                rawWeight: lastHistory.rawWeight,
                trendWeight: lastHistory.trendWeight,
                caloricImbalance: lastHistory.caloricImbalance,
                isProjected: true
            )
            return [bridgePoint] + projected
        }
        return projected
    }
    
    private var visibleRawData: [DailyTrendData] {
        let range = visibleRange
        return trendData.filter { $0.rawWeight != nil && $0.date >= range.lowerBound && $0.date <= range.upperBound }
    }
    
    // MARK: - Helpers
    
    private func statView(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(color)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func snapToNearestLevel() {
        // Calculate max available days for "All Time"
        let maxDays = Double(max(trendData.count, 90))
        let levels: [Double] = [90, 365, 1825, maxDays]
        
        // Find closest level
        let closest = levels.min(by: { abs($0 - visibleDays) < abs($1 - visibleDays) }) ?? 90
        
        // We also want to animate the snap while preserving the anchor (Right Edge)
        let currentEnd = scrollPosition.addingTimeInterval(visibleDays * 86400)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            visibleDays = closest
            // Adjust scroll position to keep the end date fixed at the new zoom level
            scrollPosition = currentEnd.addingTimeInterval(-(closest * 86400))
        }
    }
    
    private func scrollToEnd() {
        guard let lastDate = trendData.last?.date else { return }
        let leadingDate = lastDate.addingTimeInterval(-(visibleDays * 86400))
        scrollPosition = leadingDate
    }
    
    private func updateYDomain(targetScrollPosition: Date? = nil) {
        let visibleStart = targetScrollPosition ?? scrollPosition
        let visibleEnd = visibleStart.addingTimeInterval(visibleDays * 86400)
        
        let visibleData = trendData.filter { $0.date >= visibleStart && $0.date <= visibleEnd }
        
        guard !visibleData.isEmpty else {
            if let last = trendData.last {
                yAxisDomain = (last.trendWeight - 5)...(last.trendWeight + 5)
            }
            return
        }
        
        let allValues = visibleData.flatMap { [$0.trendWeight, $0.rawWeight].compactMap { $0 } }
        guard let minVal = allValues.min(), let maxVal = allValues.max() else { return }
        
        let range = maxVal - minVal
        let padding = range == 0 ? 0.5 : (range * 0.05)
        
        withAnimation(.easeOut(duration: 0.2)) {
            yAxisDomain = (minVal - padding)...(maxVal + padding)
        }
    }
    
    // MARK: - Calculation
    private func calculate() {
        let history = healthManager.weightHistory
        
        calculationTask?.cancel()
        calculationTask = Task {
            // Run expensive calculation on background thread
            let (newTrendData, newStats) = await Task.detached(priority: .userInitiated) {
                // Updated to use static methods on TrendEngine enum
                // This avoids MainActor isolated initializer issues
                let result = TrendEngine.calculateTrend(from: history)
                let stats = TrendEngine.getStats(from: result)
                return (result, stats)
            }.value
            
            // Check for cancellation before updating UI
            if !Task.isCancelled {
                // 1. Update Data First
                await MainActor.run {
                    self.trendData = newTrendData
                    self.stats = newStats
                }
                
                // 2. Wait a tick to allow SwiftUI to acknowledge new data/domain
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
                
                // 3. Update Scroll Position and Y-Axis
                await MainActor.run {
                    if !newTrendData.isEmpty {
                        // Logic to handle initial scroll or updates
                        if !hasPerformedInitialScroll {
                            // Calculate where we want to go
                            if let lastDate = newTrendData.last?.date {
                                let leadingDate = lastDate.addingTimeInterval(-(visibleDays * 86400))
                                
                                // Set state
                                self.scrollPosition = leadingDate
                                self.hasPerformedInitialScroll = true
                                
                                // Update Y-Axis immediately for this new position
                                self.updateYDomain(targetScrollPosition: leadingDate)
                            }
                        } else {
                            // Normal update
                            self.updateYDomain()
                        }
                    }
                }
            }
        }
    }
    
    private var xAxisDomain: ClosedRange<Date> {
        guard let first = trendData.first?.date, let last = trendData.last?.date else { return Date()...Date() }
        let extendedLast = Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last
        return first...extendedLast
    }
}
