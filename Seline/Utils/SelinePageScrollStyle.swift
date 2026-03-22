import SwiftUI

struct SelinePrimaryPageScrollModifier: ViewModifier {
    let keyboardDismissMode: ScrollDismissesKeyboardMode

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(keyboardDismissMode)
            .scrollContentBackground(.hidden)
    }
}

extension View {
    func selinePrimaryPageScroll(
        keyboardDismissMode: ScrollDismissesKeyboardMode = .interactively
    ) -> some View {
        modifier(SelinePrimaryPageScrollModifier(keyboardDismissMode: keyboardDismissMode))
    }
}
