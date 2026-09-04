import SwiftUI

/// Canonical form rows for a light and dark menu bar color pair.
struct MenuBarColorPickerRows: View {
    let lightColor: Binding<Color>
    let darkColor: Binding<Color>
    var isDisabled = false

    var body: some View {
        Group {
            LabeledContent("Light appearance") {
                ColorPicker("Light appearance color", selection: lightColor, supportsOpacity: false)
                    .labelsHidden()
            }
            LabeledContent("Dark appearance") {
                ColorPicker("Dark appearance color", selection: darkColor, supportsOpacity: false)
                    .labelsHidden()
            }
        }
        .disabled(isDisabled)
    }
}
