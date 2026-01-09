//
//  HaesslonWidget.swift
//  HaesslonWidget
//
//  Created by Daniel Arndt on 09.01.26.
//

import WidgetKit
import SwiftUI
import AppIntents

// Renamed to avoid conflicts
struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry {
        CaloriesEntry(
            date: Date(),
            remainingCalories: 1200,
            consumedCalories: 0, // Placeholder
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
            consumedCalories: 800, // Example snapshot
            kcalProgress: 0.4,
            proteinProgress: 0.6,
            fiberProgress: 0.3,
            weighedIn: false
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> ()) {
        // ⚠️ CHANGE THIS to your actual App Group ID
        let appGroupID = "group.com.haesslon.shared"
        let sharedDefaults = UserDefaults(suiteName: appGroupID)
        
        let remaining = sharedDefaults?.double(forKey: "remainingCalories") ?? 0
        let kcalProgress = sharedDefaults?.double(forKey: "kcalProgress") ?? 0
        let proteinProgress = sharedDefaults?.double(forKey: "proteinProgress") ?? 0
        let fiberProgress = sharedDefaults?.double(forKey: "fiberProgress") ?? 0
        let weighedIn = sharedDefaults?.bool(forKey: "weighedInToday") ?? false
        
        // Calculate consumed based on progress and remaining isn't perfectly reliable here
        // because we don't save 'consumed' explicitly in HealthManager's widget update.
        // However, we can infer it: if progress is near 0, consumed is near 0.
        // Better yet: we should update HealthManager to save 'consumedCalories'.
        // For now, let's trust that if kcalProgress is effectively 0, we haven't eaten.
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

        // Refresh every 30 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate) ?? currentDate.addingTimeInterval(1800)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let remainingCalories: Double
    let consumedCalories: Double // Added to track if we should show button
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
                // Background Rings (Track)
                Group {
                    RingShape(progress: 1.0, thickness: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 120, height: 120)
                    
                    RingShape(progress: 1.0, thickness: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 92, height: 92)
                    
                    RingShape(progress: 1.0, thickness: 12)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                        .frame(width: 64, height: 64)
                }
                
                // Progress Rings
                Group {
                    // Outer: Calories (Red/Green based on remaining)
                    RingShape(progress: entry.kcalProgress, thickness: 12)
                        .stroke(
                            entry.remainingCalories >= 0 ? Color.blue : Color.red,
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .frame(width: 120, height: 120)
                        .rotationEffect(.degrees(-90))
                    
                    // Middle: Protein (Blue)
                    RingShape(progress: entry.proteinProgress, thickness: 12)
                        .stroke(Color.purple, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: 92, height: 92)
                        .rotationEffect(.degrees(-90))
                    
                    // Inner: Fiber (Green)
                    RingShape(progress: entry.fiberProgress, thickness: 12)
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
                
                // Interactive Button Overlay
                // Only show if consumed calories (represented by progress here for now) is zero
                if entry.consumedCalories == 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            // 🟢 INTERACTIVE BUTTON HERE
                            Button(intent: LogBreakfastIntent()) {
                                Image(systemName: "cup.and.saucer.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .padding(6)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain) // Required for widget buttons
                        }
                    }
                }
            }
            .containerBackground(for: .widget) {
                Color(.systemBackground)
            }
            
        default:
            // Fallback for larger sizes (could be expanded later)
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

// Custom Shape for Rings to allow centering properly
struct RingShape: Shape {
    var progress: Double
    var thickness: CGFloat
    
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

