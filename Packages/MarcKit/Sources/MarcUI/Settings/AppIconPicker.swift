import MarcCore
import SwiftUI

/// Icon tiles for choosing the icon Marc shows in the Dock. The images come from the app's asset
/// catalog; "Match Appearance" shows both, split diagonally.
struct AppIconPicker: View {
    @Binding var selection: AppIconStyle

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach(AppIconStyle.allCases, id: \.self) { style in
                Button { selection = style } label: {
                    VStack(spacing: 6) {
                        preview(for: style)
                            .frame(width: 64, height: 64)
                            .padding(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: 3)
                                    .opacity(selection == style ? 1 : 0),
                            )
                        Text(style.displayName)
                            .font(.caption)
                            .foregroundStyle(selection == style ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityAddTraits(selection == style ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("appIcon-\(style.rawValue)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private func preview(for style: AppIconStyle) -> some View {
        switch style {
        case .marc:
            Image(AppIconStyle.marcImageName).resizable()
        case .aurora:
            Image(AppIconStyle.auroraImageName).resizable()
        case .matchAppearance:
            Image(AppIconStyle.marcImageName).resizable()
                .overlay { Image(AppIconStyle.auroraImageName).resizable().mask(LowerRightHalf()) }
        }
    }
}

/// The triangle below the diagonal from the top-right to the bottom-left corner.
private struct LowerRightHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
