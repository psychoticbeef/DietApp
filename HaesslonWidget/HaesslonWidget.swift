import WidgetKit
import SwiftUI
import AppIntents

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(
            date: Date(),
            remainingCalories: 1200,
            consumedCalories: 0,
            kcalProgress: 0.4,
            proteinProgress: 0.6,
            fiberProgress: 0.3,
            weighedIn: false
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> ()) {
        let entry = CaloriesEntry(
            date: Date(),
            remainingCalories: 1200,
            consumedCalories: 800,
            kcalProgress: 0.4,
            proteinProgress: 0.6,
            fiberProgress: 0.3,
            weighedIn: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> ()) {
        let sharedDefaults = UserDefaults(suiteName: AppConstants.appGroupId)
        
        let remaining = sharedDefaults?.double(forKey: AppConstants.Keys.remainingCalories) ?? 0
        let kcalProgress = sharedDefaults?.double(forKey: AppConstants.Keys.kcalProgress) ?? 0
        let proteinProgress = sharedDefaults?.double(forKey: AppConstants.Keys.proteinProgress) ?? 0
        let fiberProgress = sharedDefaults?.double(forKey: AppConstants.Keys.fiberProgress) ?? 0
        let weighedIn = sharedDefaults?.bool(forKey: AppConstants.Keys.weighedInToday) ?? false
        
        // Infer consumption state from progress
        let consumed = (kcalProgress > 0.01) ? 100.0 : 0.0
        
        let currentDate = Date()
        let entry = CaloriesEntry(
            date: currentDate,
            remainingCalories: remaining,
            consumedCalories: consumed,
            kcalProgress: kcalProgress,
            proteinProgress: proteinProgress,
            fiberProgress: fiberProgress,
            weighedIn: weighedIn
        )

        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let remainingCalories: Double
    let consumedCalories: Double
    let kcalProgress: Double
    let proteinProgress: Double
    let fiberProgress: Double
    let weighedIn: Bool
}

struct HaesslonWidgetEntryView : View {
    var entry: CaloriesProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            ZStack {
                // Background Rings
                Group {
                    RingShape(progress: 1.0)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 120, height: 120)
                    RingShape(progress: 1.0)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 92, height: 92)
                    RingShape(progress: 1.0)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 64, height: 64)
                }
                
                // Progress Rings
                Group {
                    // Outer: Calories
                    RingShape(progress: entry.kcalProgress)
                        .stroke(
                            entry.remainingCalories >= 0 ? Color.blue : Color.red,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    // Middle: Protein
                    RingShape(progress: entry.proteinProgress)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(-90))
                    
                    // Inner: Fiber
                    RingShape(progress: entry.fiberProgress)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                }
                
                // Center Text
                VStack(spacing: 0) {
                    Text("\(Int(entry.remainingCalories))")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    
                    if !entry.weighedIn {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                }
                
                // Interactive Button Overlay (Only if not eaten yet)
                if entry.consumedCalories == 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(intent: LogBreakfastIntent()) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
            
        default:
            VStack {
                Text("\(Int(entry.remainingCalories)) kcal left")
                if entry.consumedCalories == 0 {
                    Button(intent: LogBreakfastIntent()) {
                        Label("Log Breakfast", systemImage: "cup.and.saucer.fill")
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        }
    }
}

struct RingShape: Shape {
    var progress: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.width / 2, y: rect.height / 2),
            radius: rect.width / 2,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * progress),
            clockwise: false
        )
        return path
    }
}

@main
struct HaesslonWidget: Widget {
    let kind: String = "HaesslonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CaloriesProvider()) { entry in
            HaesslonWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nutrition Rings")
        .description("Track calories, protein, and fiber at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
