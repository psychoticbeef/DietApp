import SwiftUI
import HealthKit

struct DetailStat: View {
    let label: LocalizedStringKey
    let value: Int
    var unit: String = ""
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct RingView: View {
    var percentage: Double
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 15)
            Circle()
                .trim(from: 0, to: percentage)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: percentage)
        }
    }
}

// MARK: - Metric Card for Grid
struct MetricCard: View {
    let label: LocalizedStringKey
    let value: String
    let unit: String
    let category: LocalizedStringKey?
    let color: Color
    var trend: Double? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .bold()
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                if let category = category {
                    Text(category)
                        .font(.caption2)
                        .bold()
                        .foregroundStyle(color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.1))
                        .clipShape(Capsule())
                }
                
                if let trend = trend {
                    if category != nil {
                        Spacer()
                    }
                    HStack(spacing: 2) {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        Text(String(format: "%.1f", abs(trend)))
                    }
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(trend > 0 ? .red : .green)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Health Evaluation Logic
struct HealthEvaluator {
    static func evaluateBMI(weightKg: Double, heightCm: Double) -> (LocalizedStringKey?, Color) {
        let heightM = heightCm / 100.0
        guard heightM > 0 else { return (nil, .primary) }
        let bmi = weightKg / (heightM * heightM)
        
        if bmi < 18.5 { return ("Underweight", .orange) }
        if bmi <= 25.0 { return ("Normal", .green) }
        return ("Overweight", .red)
    }
    
    static func evaluateBodyFat(percent: Double, age: Int, sex: HKBiologicalSex) -> (LocalizedStringKey?, Color) {
        let isMale = sex == .male
        
        func eval(_ vGood: Double, _ good: Double, _ avg: Double) -> (LocalizedStringKey?, Color) {
            let p = percent * 100
            if p < vGood { return ("Excellent", .blue) }
            if p <= good { return ("Good", .green) }
            if p <= avg { return ("Average", .orange) }
            return ("Poor", .red)
        }
        
        if isMale {
            switch age {
            case 10...14: return eval(11, 16, 21)
            case 15...19: return eval(12, 17, 22)
            case 20...29: return eval(13, 18, 23)
            case 30...39: return eval(14, 19, 24)
            case 40...49: return eval(15, 20, 25)
            case 50...59: return eval(16, 21, 26)
            case 60...69: return eval(17, 22, 27)
            case 70...120: return eval(18, 23, 28)
            default: return (nil, .primary)
            }
        } else {
            switch age {
            case 10...14: return eval(16, 21, 26)
            case 15...19: return eval(17, 22, 27)
            case 20...29: return eval(18, 23, 28)
            case 30...39: return eval(19, 24, 29)
            case 40...49: return eval(20, 25, 30)
            case 50...59: return eval(21, 26, 31)
            case 60...69: return eval(22, 27, 32)
            case 70...120: return eval(23, 28, 33)
            default: return (nil, .primary)
            }
        }
    }
    
    static func evaluateVO2Max(value: Double, age: Int, sex: HKBiologicalSex) -> (LocalizedStringKey?, Color) {
        func check(_ thresholds: [Double]) -> (LocalizedStringKey?, Color) {
            if value >= thresholds[0] { return ("Superior", .purple) }
            if value >= thresholds[1] { return ("Excellent", .blue) }
            if value >= thresholds[2] { return ("Good", .green) }
            if value >= thresholds[3] { return ("Fair", .orange) }
            return ("Poor", .red)
        }
        
        let isMale = sex == .male
        
        if isMale {
            switch age {
            case 20...29: return check([55.4, 51.1, 45.4, 41.7])
            case 30...39: return check([54.0, 48.3, 44.0, 40.5])
            case 40...49: return check([52.5, 46.4, 42.4, 38.5])
            case 50...59: return check([48.9, 43.4, 39.2, 35.6])
            case 60...69: return check([45.7, 39.5, 35.5, 32.3])
            case 70...120: return check([42.1, 36.7, 32.3, 29.4])
            default: return (nil, .primary)
            }
        } else {
            switch age {
            case 20...29: return check([49.6, 43.9, 39.5, 36.1])
            case 30...39: return check([47.4, 42.4, 37.8, 34.4])
            case 40...49: return check([45.3, 39.7, 36.3, 33.0])
            case 50...59: return check([41.1, 36.7, 33.0, 30.1])
            case 60...69: return check([37.8, 33.0, 30.0, 27.5])
            case 70...120: return check([36.7, 30.9, 28.1, 25.9])
            default: return (nil, .primary)
            }
        }
    }
    
    static func evaluatePAL(value: Double) -> (LocalizedStringKey?, Color) {
        // Multipliers: 1.2, 1.375, 1.55, 1.725, 1.9
        // Breakpoints calculated as midpoints between these targets
        if value < 1.29 { return ("Sedentary", .red) }
        if value < 1.46 { return ("Lightly Active", .orange) }
        if value < 1.64 { return ("Moderately Active", .green) }
        if value < 1.81 { return ("Very Active", .blue) }
        return ("Extra Active", .purple)
    }
}

