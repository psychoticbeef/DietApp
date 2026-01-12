import SwiftUI
import HealthKit
import SwiftData

struct DashboardView: View {
    @Environment(HealthManager.self) private var healthManager
    
    // Bindings / State passed from parent
    var previewSnapshot: MacroSnapshot
    var isEnteringFood: Bool
    
    // SwiftData Models
    var breakfast: StandardBreakfast
    var fillerFoods: [FillerFood]
    
    @Binding var hasRequestedHealthAuthorization: Bool
    
    // Actions
    var onSelectFillerFood: (FillerFood) -> Void
    var onAddBreakfast: () -> Void
    
    // Settings using Constants
    @AppStorage(AppConstants.Keys.caloricDeficit) private var caloricDeficit: Double = 500.0
    @AppStorage(AppConstants.Keys.autoDeficitEnabled) private var autoDeficitEnabled: Bool = false
    @AppStorage(AppConstants.Keys.isCurrentlyInDeficitMode) private var isCurrentlyInDeficitMode: Bool = false
    
    let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    
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
                        Task { await healthManager.requestAuthorization() }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: isEnteringFood ? 12 : 24) {
                        
                        // --- Logic Projection ---
                        let budget = DietLogic.calculateBudget(
                            bmr: healthManager.bmr,
                            activeEnergyYesterday: healthManager.activeEnergyYesterday,
                            dietaryEnergyToday: healthManager.dietaryEnergyToday,
                            baseDeficit: caloricDeficit,
                            autoDeficitEnabled: autoDeficitEnabled,
                            isCurrentlyInDeficitMode: isCurrentlyInDeficitMode
                        )
                        
                        let projectedEaten = healthManager.dietaryEnergyToday + previewSnapshot.kcal
                        let remainingWithPreview = budget.dailyGoal - projectedEaten
                        
                        // --- Cards ---
                        
                        mainStatusCard(
                            budget: budget,
                            projectedEaten: projectedEaten,
                            remaining: remainingWithPreview,
                            isCompact: isEnteringFood
                        )
                        
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
                            
                            if remainingWithPreview > 0 && !fillerFoods.isEmpty {
                                fillerFoodsSection(remainingKcal: remainingWithPreview)
                            }
                        }
                    }
                    .padding()
                    .padding(.bottom, isEnteringFood ? 300 : 0)
                }
                .id(isEnteringFood)
                .refreshable { healthManager.fetchData() }
            }
        }
    }
    
    // MARK: - Component Extraction
    
    func mainStatusCard(budget: DietLogic.BudgetResult, projectedEaten: Double, remaining: Double, isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 16) {
            if !isCompact {
                Text("Daily Budget").font(.headline).foregroundStyle(.secondary)
            }
            
            if healthManager.bmr != nil {
                if isCompact {
                    HStack(spacing: 20) {
                        ZStack {
                            RingView(percentage: min(projectedEaten / (budget.dailyGoal > 0 ? budget.dailyGoal : 1), 1.0))
                                .frame(width: 50, height: 50)
                                .animation(.spring, value: previewSnapshot.kcal)
                            Text("\(Int(toDisplayEnergy(remaining)))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Budget").font(.caption).bold()
                            Text("\(Int(toDisplayEnergy(remaining))) \(energyLabel) remaining")
                                .font(.caption).foregroundStyle(remaining >= 0 ? .green : .red)
                        }
                        Spacer()
                    }
                } else {
                    ZStack {
                        RingView(percentage: min(projectedEaten / (budget.dailyGoal > 0 ? budget.dailyGoal : 1), 1.0))
                            .frame(width: 180, height: 180)
                            .animation(.spring, value: previewSnapshot.kcal)
                        
                        VStack {
                            Text("\(Int(toDisplayEnergy(remaining)))")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundStyle(remaining >= 0 ? Color.primary : Color.red)
                                .contentTransition(.numericText())
                            Text("\(energyLabel) remaining").font(.subheadline).foregroundStyle(.secondary)
                            
                            if autoDeficitEnabled {
                                Text(budget.isDeficitActive ? "Deficit Active" : "Maintenance Mode")
                                    .font(.caption)
                                    .foregroundStyle(budget.isDeficitActive ? .orange : .blue)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    Divider()
                    HStack(spacing: 20) {
                        DetailStat(label: "BMR", value: Int(toDisplayEnergy(healthManager.bmr ?? 0)), unit: energyLabel)
                        DetailStat(label: "Active (Yst)", value: Int(toDisplayEnergy(healthManager.activeEnergyYesterday)), unit: energyLabel)
                        DetailStat(label: "Eaten", value: Int(toDisplayEnergy(projectedEaten)), unit: energyLabel)
                    }
                }
            } else {
                Text("Missing Health Data").font(.title3)
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
            Text("Health Compass").font(isCompact ? .subheadline : .headline).foregroundStyle(.secondary)
            
            let currentEaten = healthManager.dietaryEnergyToday
            let projectedEaten = currentEaten + preview.kcal
            let displayEaten = max(projectedEaten, 1)
            
            HStack(spacing: spacing) {
                let weight = healthManager.currentWeight ?? 70
                let proteinTarget = weight * 0.8
                
                NutrientRing(
                    label: "Protein", current: healthManager.dietaryProteinToday, previewAdd: preview.protein,
                    target: proteinTarget, unit: "g", color: .blue, size: ringSize, lineWidth: lineWidth, isCompact: isCompact
                )
                
                NutrientRing(
                    label: "Fiber", current: healthManager.dietaryFiberToday, previewAdd: preview.fiber,
                    target: 30.0, unit: "g", color: .green, size: ringSize, lineWidth: lineWidth, isCompact: isCompact
                )
            }
            Divider()
            
            HStack(spacing: spacing) {
                let fatKcal = (healthManager.dietaryFatTotalToday + preview.fat) * 9
                let fatPct = (fatKcal / displayEaten) * 100
                let fatColor: Color = (fatPct > 40) ? .red : (fatPct < 30 ? .orange : .green)
                
                LimitRing(label: "Fats", subLabel: "30-40%", current: fatPct, previewAdd: 0, limit: 40, unit: "%", color: fatColor, size: ringSize, lineWidth: lineWidth, isCompact: isCompact)
                
                let sugarKcal = (healthManager.dietarySugarToday + preview.sugar) * 4
                let sugarPct = (sugarKcal / displayEaten) * 100
                let sugarColor: Color = (sugarPct > 10) ? .red : .green
                
                LimitRing(label: "Sugar", subLabel: "<10%", current: sugarPct, previewAdd: 0, limit: 10, unit: "%", color: sugarColor, size: ringSize, lineWidth: lineWidth, isCompact: isCompact)
            }
            
            HStack(spacing: spacing) {
                let satFatKcal = (healthManager.dietaryFatSaturatedToday + preview.satFat) * 9
                let satFatPct = (satFatKcal / displayEaten) * 100
                let satFatColor: Color = (satFatPct > 10) ? .red : .green
                
                LimitRing(label: "Sat. Fat", subLabel: "<10%", current: satFatPct, previewAdd: 0, limit: 10, unit: "%", color: satFatColor, size: ringSize, lineWidth: lineWidth, isCompact: isCompact)
                
                let saltGrams = (healthManager.dietarySodiumToday + preview.sodium) * 2.5
                let saltColor: Color = (saltGrams > 6) ? .red : .green
                
                LimitRing(label: "Salt", subLabel: "<6g", current: saltGrams, previewAdd: 0, limit: 6, unit: "g", color: saltColor, size: ringSize, lineWidth: lineWidth, isCompact: isCompact)
            }
            
            if let weight = healthManager.currentWeight {
                Divider()
                VStack(spacing: 8) {
                    HStack { Text("Body Composition (7d Avg)").font(.caption).foregroundStyle(.secondary); Spacer() }
                    LazyVGrid(columns: columns, spacing: 12) {
                        
                        // CLEVER: Instead of repeating "Overweight" or "Normal", show the
                        // "Normal" weight range for the user's height (BMI 18.5 - 25).
                        // This gives the user a concrete target range.
                        let weightRangeLabel: String? = {
                            guard let h = healthManager.height else { return nil }
                            let m = h / 100.0
                            let lower = 18.5 * m * m
                            let upper = 25.0 * m * m
                            return "\(Int(ceil(lower)))-\(Int(floor(upper)))kg"
                        }()
                        
                        MetricCard(
                            label: "Weight",
                            value: String(format: "%.1f", weight),
                            unit: "kg",
                            category: weightRangeLabel.map { LocalizedStringKey($0) },
                            color: .primary, // Neutral color for the info pill
                            trend: healthManager.weightTrend,
                            invertTrendColor: false // Losing weight is green
                        )
                        
                        if let height = healthManager.height {
                            let (cat, col) = HealthEvaluator.evaluateBMI(weightKg: weight, heightCm: height)
                            MetricCard(
                                label: "BMI",
                                value: String(format: "%.1f", weight / pow(height/100, 2)),
                                unit: "",
                                category: cat,
                                color: col,
                                trend: healthManager.bmiTrend,
                                invertTrendColor: false // Lower BMI is green
                            )
                        }
                        
                        if let bf = healthManager.bodyFat, let age = healthManager.age {
                            let (cat, col) = HealthEvaluator.evaluateBodyFat(percent: bf, age: age, sex: healthManager.biologicalSex)
                            MetricCard(
                                label: "Body Fat",
                                value: String(format: "%.1f", bf * 100),
                                unit: "%",
                                category: cat,
                                color: col,
                                trend: healthManager.bodyFatTrend != nil ? healthManager.bodyFatTrend! * 100 : nil,
                                invertTrendColor: false // Lower body fat is green
                            )
                        }
                        
                        if let vo2 = healthManager.vo2Max, let age = healthManager.age {
                            let (cat, col) = HealthEvaluator.evaluateVO2Max(value: vo2, age: age, sex: healthManager.biologicalSex)
                            MetricCard(
                                label: "VO2 Max",
                                value: String(format: "%.1f", vo2),
                                unit: "ml/kg",
                                category: cat,
                                color: col,
                                trend: healthManager.vo2MaxTrend,
                                invertTrendColor: true // Higher VO2 max is green
                            )
                        }
                        
                        if let pal = healthManager.physicalActivityLevel {
                            let (cat, col) = HealthEvaluator.evaluatePAL(value: pal)
                            MetricCard(
                                label: "PA Level",
                                value: String(format: "%.2f", pal),
                                unit: "",
                                category: cat,
                                color: col,
                                trend: healthManager.physicalActivityLevelTrend,
                                invertTrendColor: true // Higher activity is green
                            )
                        }
                    }
                }
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isCompact)
    }
    
    var weightWarning: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("You haven't weighed in today.").font(.subheadline).fontWeight(.medium)
            Spacer()
        }
        .padding().background(Color.orange.opacity(0.15)).cornerRadius(12)
    }
    
    func fillerFoodsSection(remainingKcal: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filler Foods").font(.headline).foregroundStyle(.secondary)
            ForEach(fillerFoods) { food in
                if food.kcalPer100g > 0 && !food.name.isEmpty {
                    Button { onSelectFillerFood(food) } label: {
                        HStack {
                            Text(food.name).fontWeight(.medium).foregroundStyle(Color.primary)
                            Spacer()
                            // Calculate grams based on remaining kcal
                            let grams = remainingKcal / (food.kcalPer100g / 100.0)
                            Text("\(Int(round(grams)))g").font(.title3).bold().foregroundStyle(.blue)
                        }
                        .padding().background(Color(.secondarySystemBackground)).cornerRadius(12)
                    }
                }
            }
        }
    }
    
    private func toDisplayEnergy(_ kcal: Double) -> Double {
        return healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) ? kcal * 4.184 : kcal
    }
    
    private var energyLabel: String { healthManager.energyUnitString }
}
