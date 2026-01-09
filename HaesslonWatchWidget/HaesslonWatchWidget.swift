//
//  HaesslonWatchWidget.swift
//  HaesslonWatchWidget
//
//  Created by Daniel Arndt on 09.01.26.
//

import WidgetKit
import SwiftUI

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry {
        WatchEntry(date: Date(), remainingCalories: 1200, weighedIn: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> ()) {
        let entry = WatchEntry(date: Date(), remainingCalories: 1200, weighedIn: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> ()) {
        // ⚠️ Ensure "group.com.haesslon.shared" is added to the Watch App and Watch Widget Extension entitlements.
        // This allows the Watch App (which receives data) to share it with the Widget.
        let sharedDefaults = UserDefaults(suiteName: "group.com.haesslon.shared")
        
        let remaining = sharedDefaults?.double(forKey: "remainingCalories") ?? 0
        let weighedIn = sharedDefaults?.bool(forKey: "weighedInToday") ?? false
        
        let currentDate = Date()
        let entry = WatchEntry(date: currentDate, remainingCalories: remaining, weighedIn: weighedIn)

        // Refresh every 30 minutes
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: currentDate)!
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct WatchEntry: TimelineEntry {
    let date: Date
    let remainingCalories: Double
    let weighedIn: Bool
}

struct HaesslonWatchWidgetEntryView : View {
    var entry: WatchProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                // Circle()
                //    .stroke(Color.gray.opacity(0.3), lineWidth: 4)
                VStack(spacing: 0) {
                    Text("\(Int(entry.remainingCalories))")
                        .font(.system(size: 14, weight: .bold))
                    Text("kcal")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
            
        case .accessoryRectangular:
            HStack {
                VStack(alignment: .leading) {
                    Text("Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Int(entry.remainingCalories)) kcal")
                        .font(.headline)
                        .foregroundStyle(entry.remainingCalories >= 0 ? .green : .red)
                    
                    if !entry.weighedIn {
                         Text("Weigh In!")
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
            .containerBackground(.fill.tertiary, for: .widget)
            
        case .accessoryInline:
            Text("\(Int(entry.remainingCalories)) kcal left")
            
        case .accessoryCorner:
            Text("\(Int(entry.remainingCalories))")
                .widgetLabel("kcal left")
                
        default:
            Text("\(Int(entry.remainingCalories))")
        }
    }
}

struct HaesslonWatchWidget: Widget {
    let kind: String = "HaesslonWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchProvider()) { entry in
            HaesslonWatchWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Calorie Budget")
        .description("Shows remaining calories.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

