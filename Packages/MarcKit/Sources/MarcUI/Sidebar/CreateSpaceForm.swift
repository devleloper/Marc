import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The in-sidebar form for a new Space: icon, name, profile and theme.
struct CreateSpaceForm: View {
    @Bindable var window: BrowserWindowModel
    @State private var name = ""
    @State private var icon: SpaceIcon = .symbol("circle.fill")
    @State private var profileID: Profile.ID?
    @State private var theme = Theme.presets.randomElement() ?? .default
    @State private var isPickingIcon = false
    @State private var isEditingTheme = false
    @FocusState private var nameFocused: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 18)
            Text("Create a Space")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.primaryText)
            Text("Separate your tabs for life, work, projects and more.")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            HStack(spacing: 8) {
                Button { isPickingIcon = true } label: {
                    SpaceIconView(icon: icon).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isPickingIcon) { IconPicker(selection: $icon) }
                TextField("Space name…", text: $name)
                    .textFieldStyle(.plain)
                    .font(Typography.addressHost)
                    .focused($nameFocused)
                    .onSubmit(create)
                    .accessibilityIdentifier("spaceNameField")
            }
            .formRow(palette)

            HStack {
                Image(systemName: "person.crop.circle").foregroundStyle(palette.icon)
                Text("Profile").font(Typography.addressHost).foregroundStyle(palette.primaryText)
                Spacer()
                Picker("Profile", selection: $profileID) {
                    ForEach(window.workspace.orderedProfiles) { profile in
                        Text(profile.name).tag(Profile.ID?.some(profile.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .formRow(palette)

            Button { isEditingTheme = true } label: {
                HStack {
                    Image(systemName: "paintbrush.pointed").foregroundStyle(palette.icon)
                    Text("Choose a Theme").font(Typography.addressHost).foregroundStyle(palette.primaryText)
                    Spacer()
                    ThemeSwatch(theme: theme).frame(width: 34, height: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .formRow(palette)
            .popover(isPresented: $isEditingTheme, arrowEdge: .trailing) {
                ThemeEditor(theme: $theme)
            }

            Spacer()

            Button("Create Space", action: create)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("createSpaceButton")
            Button("Cancel") { window.isCreatingSpace = false }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondaryText)
                .keyboardShortcut(.cancelAction)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, Metrics.Sidebar.inset)
        .focusOnAppear($nameFocused)
        .onAppear { profileID = window.profile?.id ?? window.workspace.orderedProfiles.first?.id }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let profileID, let spaceID = try? window.store.update({ try $0.addSpace(
            name: trimmed,
            profileID: profileID,
            icon: icon,
            theme: theme,
        ) }) else { return }
        window.isCreatingSpace = false
        window.switchSpace(to: spaceID)
    }
}

private extension View {
    func formRow(_ palette: ThemePalette) -> some View {
        padding(.horizontal, 10)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: Metrics.Sidebar.rowCornerRadius, style: .continuous).fill(palette.fieldFill))
    }
}

struct SpaceIconView: View {
    let icon: SpaceIcon
    @Environment(\.themePalette) private var palette

    var body: some View {
        switch icon {
        case let .emoji(emoji): Text(emoji).font(.system(size: 14))
        case let .symbol(symbol):
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.icon)
        }
    }
}

/// SF Symbols and a few emoji to choose from.
struct IconPicker: View {
    @Binding var selection: SpaceIcon
    @Environment(\.dismiss) private var dismiss
    private let emoji = ["🏠", "💼", "🎨", "📚", "🎮", "🎵", "✈️", "🧪", "💡", "🌱", "🔥", "⭐️", "🍿", "🛒", "🏋️", "🧘"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 6) {
                ForEach(SpaceIcon.suggestedSymbols, id: \.self) { symbol in
                    pickerButton(.symbol(symbol)) { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                }
            }
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 6) {
                ForEach(emoji, id: \.self) { character in
                    pickerButton(.emoji(character)) { Text(character).font(.system(size: 15)) }
                }
            }
        }
        .padding(12)
    }

    private func pickerButton(_ icon: SpaceIcon, @ViewBuilder label: () -> some View) -> some View {
        Button {
            selection = icon
            dismiss()
        } label: {
            label()
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(selection == icon ? Color.accentColor.opacity(0.25) : .clear))
        }
        .buttonStyle(.plain)
    }
}
