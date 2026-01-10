//
//  ContentView.swift
//  Haesslon
//
//  Created by Daniel Arndt on 09.01.26.
//

import SwiftUI
import HealthKit
import SwiftData

struct ContentView: View {
    @Environment(HealthManager.self) private var healthManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    
    // Settings
    @AppStorage("hasRequestedHealthAuthorization") private var hasRequestedHealthAuthorization: Bool = false
    
    // Data Persistence via SwiftData
    @Query private var breakfasts: [StandardBreakfast]
    @Query(sort: \FillerFood.name) private var fillerFoods: [FillerFood]

    // State
    @State private var selectedFillerFood: FillerFood? = nil
    @State private var fillerFoodGrams: String = ""
    @State private var isEnteringFood: Bool = false
    
    // Helper to get the single breakfast instance safely
    private var breakfast: StandardBreakfast {
        if let existing = breakfasts.first {
            return existing
        } else {
            return StandardBreakfast() // Fallback for view render until .onAppear inserts one
        }
    }
    
    // Preview Logic
    var previewSnapshot: MacroSnapshot {
        guard let food = selectedFillerFood,
              let grams = Double(fillerFoodGrams.replacingOccurrences(of: ",", with: ".")),
              grams > 0 else {
            return MacroSnapshot.zero
        }
        
        let ratio = grams / 100.0
        return MacroSnapshot(
            kcal: food.kcalPer100g * ratio,
            protein: food.proteinPer100g * ratio,
            fiber: food.fiberPer100g * ratio,
            fat: food.fatPer100g * ratio,
            satFat: food.satFatPer100g * ratio,
            sugar: food.sugarPer100g * ratio,
            sodium: (food.sodiumPer100g / 1000.0) * ratio // Convert mg to g for preview
        )
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(
                    previewSnapshot: previewSnapshot,
                    isEnteringFood: isEnteringFood,
                    breakfast: breakfast,
                    fillerFoods: fillerFoods,
                    hasRequestedHealthAuthorization: $hasRequestedHealthAuthorization,
                    onSelectFillerFood: { food in
                        selectedFillerFood = food
                        fillerFoodGrams = ""
                        isEnteringFood = true
                    },
                    onAddBreakfast: addBreakfast
                )
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
            
            NavigationStack {
                TrendView()
            }
            .tabItem { Label("Trend", systemImage: "chart.xyaxis.line") }
            
            NavigationStack {
                SettingsView(breakfast: breakfast, fillerFoods: fillerFoods)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
        .sheet(isPresented: $isEnteringFood, onDismiss: { fillerFoodGrams = "" }) {
            if let food = selectedFillerFood {
                FillerFoodInputSheet(
                    food: food,
                    grams: $fillerFoodGrams,
                    onLog: {
                        logFillerFood()
                        isEnteringFood = false
                    },
                    onCancel: {
                        isEnteringFood = false
                    }
                )
                .presentationDetents([.height(215)])
                .presentationDragIndicator(.visible)
            }
        }
        .onAppear { initializeDataIfNeeded() }
        .onChange(of: scenePhase) { _, newPhase in if newPhase == .active { healthManager.fetchData() } }
        .onChange(of: healthManager.dietaryEnergyToday) { updateWidget() }
        .task {
            if hasRequestedHealthAuthorization { await healthManager.requestAuthorization() }
            if healthManager.isAuthorized {
                healthManager.fetchData()
                healthManager.startObserving()
            }
        }
    }
    
    private func updateWidget() { healthManager.updateWidgetData() }
    
    private func initializeDataIfNeeded() {
        if breakfasts.isEmpty {
            let newBreakfast = StandardBreakfast()
            modelContext.insert(newBreakfast)
        }
    }
    
    // MARK: - Actions
    func addBreakfast() {
        Task {
            await healthManager.logBreakfast(
                totalKcal: breakfast.totalKcal,
                fat: breakfast.totalFat,
                satFat: breakfast.totalSatFat,
                carbs: breakfast.totalCarbs,
                sugar: breakfast.totalSugar,
                protein: breakfast.totalProtein,
                fiber: breakfast.totalFiber,
                sodium: breakfast.totalSodium
            )
        }
    }
    
    func logFillerFood() {
        guard let food = selectedFillerFood,
              let grams = Double(fillerFoodGrams.replacingOccurrences(of: ",", with: ".")),
              grams > 0 else { return }
        
        let ratio = grams / 100.0
        
        Task {
            await healthManager.logBreakfast(
                totalKcal: food.kcalPer100g * ratio,
                fat: food.fatPer100g * ratio,
                satFat: food.satFatPer100g * ratio,
                carbs: food.carbsPer100g * ratio,
                sugar: food.sugarPer100g * ratio,
                protein: food.proteinPer100g * ratio,
                fiber: food.fiberPer100g * ratio,
                sodium: food.sodiumPer100g * ratio
            )
        }
    }
}

// Separate Sheet Component for Input
struct FillerFoodInputSheet: View {
    let food: FillerFood
    @Binding var grams: String
    var onLog: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Log \(food.name)")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                        .font(.title3)
                }
            }
            
            HStack(alignment: .firstTextBaseline) {
                TextField("Amount", text: $grams)
                    .keyboardType(.decimalPad)
                    .focused($isInputFocused)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(height: 44)
                Text("g")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            Button(action: {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                onLog()
            }) {
                Text("Log Food")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .onAppear {
            isInputFocused = true
        }
    }
}

