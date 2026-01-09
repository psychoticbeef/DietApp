import SwiftUI

struct InputSheetView: View {
    @Binding var isEnteringFood: Bool
    @Binding var fillerFoodGrams: String
    let selectedFood: FillerFood?
    var onLog: () -> Void
    var onDismiss: () -> Void
    
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        if isEnteringFood, let food = selectedFood {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                
                VStack {
                    Spacer()
                    VStack(spacing: 20) {
                        HStack {
                            Text("Log \(food.name)")
                                .font(.headline)
                            Spacer()
                            Button(action: onDismiss) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.gray)
                                    .font(.title2)
                            }
                        }
                        
                        HStack {
                            TextField("Amount", text: $fillerFoodGrams)
                                .keyboardType(.decimalPad)
                                .focused($isInputFocused)
                                .font(.system(size: 34, weight: .bold))
                                .multilineTextAlignment(.center)
                                .frame(height: 60)
                            Text("g")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button {
                            onLog()
                        } label: {
                            Text("Log Food")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(20)
                    .padding()
                    .padding(.bottom, 20)
                }
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
    }
}
