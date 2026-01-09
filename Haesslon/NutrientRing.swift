import SwiftUI

struct NutrientRing: View {
    let label: LocalizedStringKey
    let current: Double
    var previewAdd: Double = 0
    let target: Double
    let unit: String
    let color: Color
    
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                Circle().trim(from: 0, to: min(current / max(target, 1), 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                if previewAdd > 0 {
                    Circle().trim(from: min(current / max(target, 1), 1.0), to: min((current + previewAdd) / max(target, 1), 1.0))
                        .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: size, height: size)
            .animation(.spring, value: previewAdd)
            
            VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
                Text(label).font(isCompact ? .caption2 : .caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 2) {
                    Text("\(Int(current + previewAdd))").foregroundStyle(previewAdd > 0 ? color : .primary)
                    Text("/ \(Int(target))\(unit)")
                }.font(isCompact ? .caption2 : .caption).fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
