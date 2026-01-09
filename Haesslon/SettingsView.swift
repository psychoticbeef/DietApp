import SwiftUI
import HealthKit
import SwiftData

struct SettingsView: View {
    @Environment(HealthManager.self) private var healthManager
    @Environment(\.modelContext) private var modelContext
    
    // Bindable allows creating bindings to properties of the model
    @Bindable var breakfast: StandardBreakfast
    var fillerFoods: [FillerFood]
    
    @AppStorage("caloricDeficit") private var caloricDeficit: Double = 500.0
    @AppStorage("useActiveEnergyToday") private var useActiveEnergyToday: Bool = false
    
    @FocusState private var focusedField: String?
    
    var body: some View {
        Form {
            Section(header: Text("Goals")) {
                HStack {
                    Text("Target Deficit")
                    Spacer()
                    // Binding handles conversion for input
                    TextField("Deficit", text: energyBinding(for: $caloricDeficit))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: "caloricDeficit")
                        .frame(width: 80)
                    Text(healthManager.energyUnitString)
                        .foregroundStyle(.secondary)
                        .layoutPriority(1)
                }
            }
            Section(header: Text("Calculation Method")) {
                Toggle("Use Today's Active Energy", isOn: $useActiveEnergyToday)
            }
            Section(header: Text("Standard Breakfast")) {
                NavigationLink(destination: StandardBreakfastDetailView(breakfast: breakfast, healthManager: healthManager)) {
                    HStack {
                        Text(breakfast.name.isEmpty ? "Configure Breakfast" : breakfast.name)
                        Spacer()
                        if breakfast.totalKcal > 0 {
                            Text("\(Int(toDisplayEnergy(breakfast.totalKcal))) \(healthManager.energyUnitString)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section(header: Text("Filler Foods")) {
                ForEach(fillerFoods) { food in
                    NavigationLink(destination: FillerFoodDetailView(food: food, healthManager: healthManager)) {
                        HStack {
                            Text(food.name.isEmpty ? "New Food" : food.name)
                            Spacer()
                            if food.kcalPer100g > 0 {
                                Text("\(Int(toDisplayEnergy(food.kcalPer100g))) \(healthManager.energyUnitString)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { indices in
                    for index in indices {
                        modelContext.delete(fillerFoods[index])
                    }
                }
                
                Button("Add Filler Food") {
                    let newFood = FillerFood()
                    modelContext.insert(newFood)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
    
    // Helpers
    private func toDisplayEnergy(_ kcal: Double) -> Double {
        return healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) ? kcal * 4.184 : kcal
    }
    
    func energyBinding(for kcalBinding: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                let value = toDisplayEnergy(kcalBinding.wrappedValue)
                if value == 0 { return "" }
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 0
                formatter.usesGroupingSeparator = false
                return formatter.string(from: NSNumber(value: value)) ?? ""
            },
            set: { newValue in
                let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                if let val = Double(cleaned) {
                    if healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) {
                        kcalBinding.wrappedValue = val / 4.184
                    } else {
                        kcalBinding.wrappedValue = val
                    }
                } else {
                    kcalBinding.wrappedValue = 0
                }
            }
        )
    }
}

// MARK: - Detail Views (Internal to Settings)

struct StandardBreakfastDetailView: View {
    @Bindable var breakfast: StandardBreakfast
    var healthManager: HealthManager
    @FocusState private var focusedField: String?
    
    // Define field order for navigation
    private let fieldOrder = [
        "name", "bk_kcal", "bk_fat", "bk_satfat",
        "bk_carbs", "bk_sugar", "bk_fib", "bk_prot", "bk_salt"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("General")) {
                TextField("Name (e.g. Oatmeal)", text: $breakfast.name)
                    .focused($focusedField, equals: "name")
                
                let energyBinding = Binding<Double>(
                    get: {
                        healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) ? breakfast.totalKcal * 4.184 : breakfast.totalKcal
                    },
                    set: { val in
                        if healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) {
                            breakfast.totalKcal = val / 4.184
                        } else {
                            breakfast.totalKcal = val
                        }
                    }
                )
                
                macroField(label: "Total Energy", value: energyBinding, unit: healthManager.energyUnitString, fieldId: "bk_kcal")
            }
            
            Section(header: Text("Total Fats")) {
                macroField(label: "Total Fat", value: $breakfast.totalFat, unit: "g", fieldId: "bk_fat")
                macroField(label: "Saturated Fat", value: $breakfast.totalSatFat, unit: "g", fieldId: "bk_satfat")
            }
            
            Section(header: Text("Total Carbs")) {
                macroField(label: "Total Carbs", value: $breakfast.totalCarbs, unit: "g", fieldId: "bk_carbs")
                macroField(label: "Of which Sugar", value: $breakfast.totalSugar, unit: "g", fieldId: "bk_sugar")
            }
            
            Section(header: Text("Total Protein & Other")) {
                macroField(label: "Fiber", value: $breakfast.totalFiber, unit: "g", fieldId: "bk_fib")
                macroField(label: "Protein", value: $breakfast.totalProtein, unit: "g", fieldId: "bk_prot")
                
                let saltBinding = Binding<Double>(
                    get: { breakfast.totalSodium * 2.5 / 1000.0 },
                    set: { breakfast.totalSodium = ($0 * 1000.0) / 2.5 }
                )
                macroField(label: "Salt", value: saltBinding, unit: "g", fieldId: "bk_salt")
            }
        }
        .navigationTitle("Configure Breakfast")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 20) {
                    Button(action: { moveFocus(forward: false) }) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveBack)
                    
                    Button(action: { moveFocus(forward: true) }) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveForward)
                }
                
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
    
    // Navigation Helpers
    private func moveFocus(forward: Bool) {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return }
        
        let nextIndex = forward ? index + 1 : index - 1
        if nextIndex >= 0 && nextIndex < fieldOrder.count {
            focusedField = fieldOrder[nextIndex]
        }
    }
    
    private var canMoveBack: Bool {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return false }
        return index > 0
    }
    
    private var canMoveForward: Bool {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return false }
        return index < fieldOrder.count - 1
    }
    
    func macroField(label: LocalizedStringKey, value: Binding<Double>, unit: String, fieldId: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: stringBinding(for: value))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: fieldId)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
                .layoutPriority(1)
        }
    }
    
    func stringBinding(for doubleBinding: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                if doubleBinding.wrappedValue == 0 { return "" }
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 2
                formatter.usesGroupingSeparator = false
                return formatter.string(from: NSNumber(value: doubleBinding.wrappedValue)) ?? ""
            },
            set: { newValue in
                let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(cleaned) { doubleBinding.wrappedValue = value } else { doubleBinding.wrappedValue = 0 }
            }
        )
    }
}

struct FillerFoodDetailView: View {
    @Bindable var food: FillerFood
    var healthManager: HealthManager
    @FocusState private var focusedField: String?
    
    // Define field order for navigation
    private let fieldOrder = [
        "name", "ff_kcal", "ff_fat", "ff_satfat",
        "ff_carbs", "ff_sugar", "ff_fib", "ff_prot", "ff_salt"
    ]
    
    var body: some View {
        Form {
            Section(header: Text("General")) {
                TextField("Name (e.g. Peanuts)", text: $food.name)
                    .focused($focusedField, equals: "name")
                
                let energyBinding = Binding<Double>(
                    get: {
                        healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) ? food.kcalPer100g * 4.184 : food.kcalPer100g
                    },
                    set: { val in
                        if healthManager.energyUnit == HKUnit.jouleUnit(with: .kilo) {
                            food.kcalPer100g = val / 4.184
                        } else {
                            food.kcalPer100g = val
                        }
                    }
                )
                
                macroField(label: "Energy / 100g", value: energyBinding, unit: healthManager.energyUnitString, fieldId: "ff_kcal")
            }
            
            Section(header: Text("Fats / 100g")) {
                macroField(label: "Total Fat", value: $food.fatPer100g, unit: "g", fieldId: "ff_fat")
                macroField(label: "Saturated Fat", value: $food.satFatPer100g, unit: "g", fieldId: "ff_satfat")
            }
            
            Section(header: Text("Carbs / 100g")) {
                macroField(label: "Carbs", value: $food.carbsPer100g, unit: "g", fieldId: "ff_carbs")
                macroField(label: "Of which Sugar", value: $food.sugarPer100g, unit: "g", fieldId: "ff_sugar")
            }
            
            Section(header: Text("Protein & Other / 100g")) {
                macroField(label: "Fiber", value: $food.fiberPer100g, unit: "g", fieldId: "ff_fib")
                macroField(label: "Protein", value: $food.proteinPer100g, unit: "g", fieldId: "ff_prot")
                
                let saltBinding = Binding<Double>(
                    get: { food.sodiumPer100g * 2.5 / 1000.0 },
                    set: { food.sodiumPer100g = ($0 * 1000.0) / 2.5 }
                )
                macroField(label: "Salt", value: saltBinding, unit: "g", fieldId: "ff_salt")
            }
        }
        .navigationTitle(food.name.isEmpty ? "New Food" : food.name)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 20) {
                    Button(action: { moveFocus(forward: false) }) {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveBack)
                    
                    Button(action: { moveFocus(forward: true) }) {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveForward)
                }
                
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
    
    // Navigation Helpers
    private func moveFocus(forward: Bool) {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return }
        
        let nextIndex = forward ? index + 1 : index - 1
        if nextIndex >= 0 && nextIndex < fieldOrder.count {
            focusedField = fieldOrder[nextIndex]
        }
    }
    
    private var canMoveBack: Bool {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return false }
        return index > 0
    }
    
    private var canMoveForward: Bool {
        guard let current = focusedField,
              let index = fieldOrder.firstIndex(of: current) else { return false }
        return index < fieldOrder.count - 1
    }
    
    func macroField(label: LocalizedStringKey, value: Binding<Double>, unit: String, fieldId: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: stringBinding(for: value))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: fieldId)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .leading)
                .layoutPriority(1)
        }
    }
    
    func stringBinding(for doubleBinding: Binding<Double>) -> Binding<String> {
        Binding(
            get: {
                if doubleBinding.wrappedValue == 0 { return "" }
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 2
                formatter.usesGroupingSeparator = false
                return formatter.string(from: NSNumber(value: doubleBinding.wrappedValue)) ?? ""
            },
            set: { newValue in
                let cleaned = newValue.replacingOccurrences(of: ",", with: ".")
                if let value = Double(cleaned) { doubleBinding.wrappedValue = value } else { doubleBinding.wrappedValue = 0 }
            }
        )
    }
}
