import SwiftUI

extension View {
    /// Gives a text field keyboard focus once it is installed in its window. Setting a
    /// `@FocusState` in `onAppear` alone is unreliable on macOS: the backing `NSTextField` may not
    /// be in the window yet, and the first-responder change is dropped.
    func focusOnAppear(_ focus: FocusState<Bool>.Binding) -> some View {
        defaultFocus(focus, true)
            .onAppear {
                focus.wrappedValue = true
                DispatchQueue.main.async { focus.wrappedValue = true }
            }
    }
}
