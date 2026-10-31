import SwiftUI

/// The menu bar item: the bell glyph, plus the next meeting's title and countdown when enabled.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image())
            if let text = model.menuBarText {
                Text(text)
            }
        }
    }
}
