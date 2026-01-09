import SwiftUI

struct LimitRing: View {
    let label: LocalizedStringKey
    let subLabel: LocalizedStringKey
    let current: Double
    var previewAdd: Double = 0
    let limit: Double
    let unit: String
    let color: Color
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    var isCompact: Bool = false
    
    var body: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            let total = current + previewAdd
            ZStack {
                Circle().stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                Circle().trim(from: 0, to: min(total / max(limit, 1), 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: total)
            }
            .frame(width: size, height: size)
            
            VStack(alignment: .leading, spacing: isCompact ? 0 : 2) {
                Text(label).font(isCompact ? .caption2 : .caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 2) {
                    if limit < 10 { Text(String(format: "%.1f%@", total, unit)).foregroundStyle(color) }
                    else { Text("\(Int(total))\(unit)").foregroundStyle(color) }
                    Text(subLabel).foregroundStyle(.secondary)
                }.font(isCompact ? .caption2 : .caption).fontWeight(.bold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
