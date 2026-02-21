import SwiftUI

struct ContextBar: View {
    let percentage: Double

    private var barColor: Color {
        if percentage >= 85 { return .red }
        if percentage >= 60 { return .yellow }
        return .green
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("Context:")
                .font(.caption2)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(percentage / 100, 1.0))
                }
            }
            .frame(width: 80, height: 6)

            Text("\(Int(percentage))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if percentage >= 85 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }
}
