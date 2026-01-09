import SwiftUI
import HealthKit
import SwiftData

struct DashboardView: View {
    @Environment(HealthManager.self) private var healthManager
    
    // Bindings / State passed from parent
    var previewSnapshot: MacroSnapshot
    var isEnteringFood: Bool
    
    // SwiftData Models (Classes)
    var breakfast: StandardBreakfast
    var fillerFoods: [FillerFood]
    
    @Binding var hasRequestedHealthAuthorization: Bool
    
    // Actions for parent to handle state changes
    var onSelectFillerFood: (FillerFood) -> Void
    var onAddBreakfast: () -> Void
    
    // Settings needed for calculations
    @AppStorage("caloricDeficit") private var caloricDeficit: Double = 500.0
    @AppStorage("useActiveEnergyToday") private var useActiveEnergyToday: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            if !healthManager.isAuthorized {
                ContentUnavailableView {
                    Label("Health Access Required", systemImage: "heart.text.square")
                } description: {
                    Text(healthManager.errorMessage ?? "Please allow access to Health data to calculate your calorie goals.")
                } actions: {
                    Button("Open Health Settings") {
                        hasRequestedHealthAuthorization = true
                        Task { await healthManager.requestAuthorization(); healthManager.startObserving() }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: isEnteringFood ? 12 : 24) {
                        mainStatusCard(preview: previewSnapshot, isCompact: isEnteringFood)
                        
                        healthCompassCard(preview: previewSnapshot, isCompact: isEnteringFood)
                        
                        if !isEnteringFood {
                            if healthManager.dietaryEnergyToday == 0 && breakfast.isValid {
                                Button {
                                    let generator = UIImpactFeedbackGenerator(style: .medium)
                                    generator.impactOccurred()
                                    onAddBreakfast()
                                } label: {
                                    Label("Add \(breakfast.name)", systemImage: "cup.and.saucer.fill")
                                        .font(.headline).frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(12)
                                }
                            }
                            
                            if healthManager.weightMissingToday { weightWarning }
                            
                            if let remaining = calculateRemaining(), remaining > 0, !fillerFoods.isEmpty {
                                fillerFoodsSection(remainingKcal: remaining)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, isEnteringFood ? 300 : 0)
                }
                .refreshable { healthManager.fetchData() }
            }
        }
    }
    
    // MARK: - Components
    
    func mainStatusCard(preview: MacroSnapshot, isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 16) {
            if !isCompact {
                Text("Daily Budget")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            if let bmr = healthManager.bmr {
                let activeEnergy = useActiveEnergyToday ? healthManager.activeEnergyToday : healthManager.activeEnergyYesterday
                let tdee = bmr + activeEnergy
                let dailyGoal = tdee - caloricDeficit
                
                let currentEaten = healthManager.dietaryEnergyToday
                let projectedEaten = currentEaten + preview.kcal
                let remaining = dailyGoal - projectedEaten
                
                if isCompact {
                    HStack(spacing: 20) {
                        ZStack {
                            RingView(percentage: min(projectedEaten / (dailyGoal > 0 ? dailyGoal : 1), 1.0))
                                .frame(width: 50, height: 50)
                                .animation(.spring, value: preview.kcal)
                            
                            // Display Remaining in Preferred Unit
                            Text("\(Int(toDisplayEnergy(remaining)))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Budget")
                                .font(.caption).bold()
                            Text("\(Int(toDisplayEnergy(remaining))) \(energyLabel) remaining")
                                .font(.caption).foregroundStyle(remaining >= 0 ? .green : .red)
                        }
                        Spacer()
                    }
                } else {
                    ZStack {
                        RingView(percentage: min(projectedEaten / (dailyGoal > 0 ? dailyGoal : 1), 1.0))
                            .frame(width: 180, height: 180)
                            .animation(.spring, value: preview.kcal)
                        
                        VStack {
                            Text("\(Int(toDisplayEnergy(remaining)))")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                                .contentTransition(.numericText())
                            Text("\(energyLabel) remaining")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    HStack(spacing: 20) {
                        DetailStat(label: "BMR", value: Int(toDisplayEnergy(bmr)), unit: energyLabel)
                        DetailStat(
                            label: useActiveEnergyToday ? "Active (Today)" : "Active (Yst)",
                            value: Int(toDisplayEnergy(activeEnergy)),
                            unit: energyLabel
                        )
                        DetailStat(label: "Eaten", value: Int(toDisplayEnergy(projectedEaten)), unit: energyLabel)
                    }
                }
            } else {
                Text("Missing Health Data")
                    .font(.title3)
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }
    
    func healthCompassCard(preview: MacroSnapshot, isCompact: Bool) -> some View {
        let ringSize: CGFloat = isCompact ? 22 : 44
        let lineWidth: CGFloat = isCompact ? 3 : 5
        let spacing: CGFloat = isCompact ? 8 : 20
        let verticalSpacing: CGFloat = isCompact ? 8 : 16
        
        return VStack(alignment: .leading, spacing: verticalSpacing) {
            Text("Health Compass")
                .font(isCompact ? .subheadline : .headline)
                .foregroundStyle(.secondary)
            
            let currentEaten = healthManager.dietaryEnergyToday
            let projectedEaten = currentEaten + preview.kcal
            let displayEaten = max(projectedEaten, 1)
            
            HStack(spacing: spacing) {
                let weight = healthManager.currentWeight ?? 70
                let proteinTarget = weight * 0.8
                
                NutrientRing(
                    label: "Protein",
                    current: healthManager.dietaryProteinToday,
                    previewAdd: preview.protein,
                    target: proteinTarget,
                    unit: "g",
                    color: .blue,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
                
                NutrientRing(
                    label: "Fiber",
                    current: healthManager.dietaryFiberToday,
                    previewAdd: preview.fiber,
                    target: 30.0,
                    unit: "g",
                    color: .green,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
            }
            
            Divider()
            
            HStack(spacing: spacing) {
                let fatKcal = (healthManager.dietaryFatTotalToday + preview.fat) * 9
                let fatPct = (fatKcal / displayEaten) * 100
                let fatColor: Color = (fatPct > 40) ? .red : (fatPct < 30 ? .orange : .green)
                
                LimitRing(
                    label: "Fats",
                    subLabel: "30-40%",
                    current: fatPct,
                    previewAdd: 0,
                    limit: 40,
                    unit: "%",
                    color: fatColor,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
                
                let sugarKcal = (healthManager.dietarySugarToday + preview.sugar) * 4
                let sugarPct = (sugarKcal / displayEaten) * 100
                let sugarColor: Color = (sugarPct > 10) ? .red : .green
                
                LimitRing(
                    label: "Sugar",
                    subLabel: "<10%",
                    current: sugarPct,
                    previewAdd: 0,
                    limit: 10,
                    unit: "%",
                    color: sugarColor,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
            }
            
            HStack(spacing: spacing) {
                let satFatKcal = (healthManager.dietaryFatSaturatedToday + preview.satFat) * 9
                let satFatPct = (satFatKcal / displayEaten) * 100
                let satFatColor: Color = (satFatPct > 10) ? .red : .green
                
                LimitRing(
                    label: "Sat. Fat",
                    subLabel: "<10%",
                    current: satFatPct,
                    previewAdd: 0,
                    limit: 10,
                    unit: "%",
                    color: satFatColor,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
                
                let saltGrams = (healthManager.dietarySodiumToday + preview.sodium) * 2.5
                let saltColor: Color = (saltGrams > 6) ? .red : .green
                
                LimitRing(
                    label: "Salt",
                    subLabel: "<6g",
                    current: saltGrams,
                    previewAdd: 0,
                    limit: 6,
                    unit: "g",
                    color: saltColor,
                    size: ringSize,
                    lineWidth: lineWidth,
                    isCompact: isCompact
                )
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCompact)
    }
    
    var weightWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("You haven't weighed in today.")
                .font(.subheadline)
                .fontWeight(.medium)
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
    }
    
    func fillerFoodsSection(remainingKcal: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filler Foods")
                .font(.headline)
                .foregroundStyle(.secondary)
            
            ForEach(fillerFoods) { food in
                if food.kcalPer100g > 0 && !food.name.isEmpty {
                    Button {
                        onSelectFillerFood(food)
                    } label: {
                        HStack {
                            Text(food.name)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.primary)
                            Spacer()
                            // Calculate grams based on kcal, display using prefered unit
                            let grams = remainingKcal / (food.kcalPer100g / 100.0)
                            Text("\(Int(round(grams)))g")
                                .font(.title3)
                                .bold()
                                .foregroundStyle(.blue)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func toDisplayEnergy(_ kcal: Double) -> Double {
        return healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) ? kcal * 4.184 : kcal
    }
    
    private var energyLabel: String {
        return healthManager.energyUnitString
    }
    
    private func calculateRemaining() -> Double? {
        guard let bmr = healthManager.bmr else { return nil }
        let activeEnergy = useActiveEnergyToday ? healthManager.activeEnergyToday : healthManager.activeEnergyYesterday
        let tdee = bmr + activeEnergy
        let dailyGoal = tdee - caloricDeficit
        return dailyGoal - healthManager.dietaryEnergyToday
    }
}
