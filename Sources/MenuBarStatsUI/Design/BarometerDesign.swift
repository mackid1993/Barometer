import AppKit
import MenuBarStatsCore
import SwiftUI

// MARK: - Tokens

/// Shared visual language for Barometer's dropdown panels and settings window.
///
/// Every dropdown is hosted inside an `NSMenu`, so these components only style the
/// hosted SwiftUI content. They never touch status-item identity, menu tracking, or
/// menu bar rendering geometry.
enum BarometerDesign {
    static let cardRadius: CGFloat = 14
    static let tileRadius: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let sectionSpacing: CGFloat = 10
    static let panelPadding: CGFloat = 12

    /// Tallest a dropdown grows before its content scrolls.
    static let maximumPanelHeight: CGFloat = 720

    /// Cards render with Liquid Glass. Flip to `false` to fall back to a material plate.
    static let usesGlassCards = true

    static let heroValueFont = Font.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
    static let titleFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let valueFont = Font.callout.monospacedDigit()
}

// MARK: - Accents

/// Two-color accent used for a module's tiles, graphs, and highlights.
struct ModuleAccent: Sendable {
    let primary: Color
    let secondary: Color

    var gradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var horizontalGradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .leading, endPoint: .trailing)
    }

    /// Signature colors used while the menu bar theme is the monochrome system default.
    static func signature(for module: ModuleID) -> ModuleAccent {
        switch module {
        case .cpu: ModuleAccent(primary: Color(hex: 0x3B82F6), secondary: Color(hex: 0x22D3EE))
        case .gpu: ModuleAccent(primary: Color(hex: 0xA855F7), secondary: Color(hex: 0xEC4899))
        case .memory: ModuleAccent(primary: Color(hex: 0x6366F1), secondary: Color(hex: 0xA78BFA))
        case .disks: ModuleAccent(primary: Color(hex: 0x14B8A6), secondary: Color(hex: 0x4ADE80))
        case .network: ModuleAccent(primary: Color(hex: 0x0EA5E9), secondary: Color(hex: 0x34D399))
        case .sensors: ModuleAccent(primary: Color(hex: 0xF97316), secondary: Color(hex: 0xEF4444))
        case .battery: ModuleAccent(primary: Color(hex: 0x22C55E), secondary: Color(hex: 0xA3E635))
        case .weather: ModuleAccent(primary: Color(hex: 0x38BDF8), secondary: Color(hex: 0xFBBF24))
        case .time: ModuleAccent(primary: Color(hex: 0x8B5CF6), secondary: Color(hex: 0x38BDF8))
        case .combined: ModuleAccent(primary: Color(hex: 0x2F7CF6), secondary: Color(hex: 0x6BA4FF))
        }
    }

    /// The accent for a module under the current theme.
    ///
    /// The system theme keeps the menu bar monochrome, so the dropdowns use each module's
    /// signature colors. Any other theme flows its configured graph and fill colors through.
    @MainActor
    static func resolve(_ settings: AppSettings, module: ModuleID) -> ModuleAccent {
        guard settings.appearancePreset != .system else {
            return signature(for: module)
        }
        return ModuleAccent(
            primary: AppearanceColorResolver.graph(settings, module: module),
            secondary: AppearanceColorResolver.fill(settings, module: module)
        )
    }
}

extension Color {
    /// Creates an opaque color from a 24-bit RGB value.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Containers

/// Container shared by every dropdown: fixed width, height that follows the content.
///
/// The menu controller measures the hosted view's ideal size and caps it at
/// `BarometerDesign.maximumPanelHeight`; taller panels scroll inside the menu instead
/// of losing information.
struct DropdownScaffold<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            GlassEffectContainer(spacing: BarometerDesign.sectionSpacing) {
                VStack(alignment: .leading, spacing: BarometerDesign.sectionSpacing) {
                    content()
                }
            }
            .padding(BarometerDesign.panelPadding)
            .frame(width: size.width)
        }
        .frame(width: size.width)
    }
}

/// A rounded glass card with optional accent tint.
struct GlassCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = BarometerDesign.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BarometerDesign.cardRadius, style: .continuous)
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(shape: shape, tint: tint))
    }
}

private struct CardSurface: ViewModifier {
    let shape: RoundedRectangle
    let tint: Color?

    func body(content: Content) -> some View {
        if BarometerDesign.usesGlassCards {
            content
                .glassEffect(.regular.tint(tint?.opacity(0.10)), in: shape)
        } else {
            content
                .background(shape.fill(.thinMaterial))
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }
}

/// A subtle inset plate used inside cards for graphs and grids.
struct InsetPlate: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: BarometerDesign.tileRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .clipShape(RoundedRectangle(cornerRadius: BarometerDesign.tileRadius, style: .continuous))
    }
}

extension View {
    func insetPlate() -> some View {
        modifier(InsetPlate())
    }
}

// MARK: - Headers and labels

/// Gradient icon tile used in hero headers and settings.
struct IconTile: View {
    let symbolName: String
    let accent: ModuleAccent
    var size: CGFloat = 36
    var renderingMode: SymbolRenderingMode = .hierarchical

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        ZStack {
            shape.fill(accent.gradient)
            shape.fill(
                LinearGradient(
                    colors: [.white.opacity(0.35), .white.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.75)
            Image(systemName: symbolName)
                .symbolRenderingMode(renderingMode)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: accent.primary.opacity(0.35), radius: 8, y: 3)
    }
}

/// Module header: icon tile, title, subtitle, and an animated headline value or a custom accessory.
struct HeroHeader<Accessory: View>: View {
    let symbolName: String
    let title: String
    var subtitle: String?
    var value: String?
    let accent: ModuleAccent
    @ViewBuilder var accessory: () -> Accessory

    init(
        symbolName: String,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        accent: ModuleAccent,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.accent = accent
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(symbolName: symbolName, accent: accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BarometerDesign.titleFont)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
            Spacer(minLength: 8)
            if let value {
                HeroValue(text: value, accent: accent)
            }
            accessory()
        }
        .padding(.horizontal, 2)
    }
}

/// Large rounded numeric readout that animates digit changes.
struct HeroValue: View {
    let text: String
    let accent: ModuleAccent

    var body: some View {
        Text(text)
            .font(BarometerDesign.heroValueFont)
            .foregroundStyle(accent.horizontalGradient)
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Small-caps section label with optional trailing accessory.
struct SectionLabel<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center) {
            Text(text.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.9)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            trailing()
        }
    }
}

/// Label and value row with monospaced digits, an optional symbol, and hover highlight.
struct MetricRow: View {
    let label: String
    let value: String
    var symbol: String?
    var tint: Color?
    var valueTint: Color?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.caption)
                    .foregroundStyle(tint ?? Color.secondary)
                    .frame(width: 16)
            }
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 10)
            Text(value)
                .font(BarometerDesign.valueFont)
                .foregroundStyle(valueTint ?? Color.primary)
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .font(.callout)
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Compact tile showing a symbol, caption, and value. Used in grids.
struct StatTile: View {
    let symbol: String
    let label: String
    let value: String
    var tint: Color = .secondary
    var renderingMode: SymbolRenderingMode = .hierarchical

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .symbolRenderingMode(renderingMode)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.numericText())
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .insetPlate()
    }
}

/// Small colored capsule used for legends and states.
struct Chip: View {
    let text: String
    var color: Color = .secondary
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .foregroundStyle(symbol == nil ? Color.primary : color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - Controls

/// Capsule segmented picker with an animated gradient selection.
struct CapsulePicker<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let accent: ModuleAccent
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selection = option
                    }
                } label: {
                    Text(label(option))
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(accent.gradient)
                                    .shadow(color: accent.primary.opacity(0.45), radius: 5, y: 1)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// Gradient progress capsule.
struct CapsuleBar: View {
    let fraction: Double
    let gradient: LinearGradient
    var height: CGFloat = 6
    var glowColor: Color?

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(1, max(0, fraction))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(gradient)
                    .frame(width: max(height, geometry.size.width * clamped))
                    .shadow(color: (glowColor ?? .clear).opacity(0.45), radius: 3)
            }
        }
        .frame(height: height)
    }
}

/// Circular gradient progress ring with a centered label.
struct ProgressRing<Label: View>: View {
    let fraction: Double
    let accent: ModuleAccent
    var lineWidth: CGFloat = 7
    var size: CGFloat = 64
    @ViewBuilder let label: () -> Label

    var body: some View {
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    AngularGradient(
                        colors: [accent.primary, accent.secondary, accent.primary],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.primary.opacity(0.45), radius: 5)
            label()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Graphs

/// Gradient area chart with a glowing line, dotted gridlines, and a live-point marker.
struct AreaGraph: View {
    let values: [Double]
    let accent: ModuleAccent
    var lineWidth: CGFloat = 1.75
    var showsGrid = true
    var showsMarker = true

    var body: some View {
        ZStack {
            if showsGrid {
                NormalizedGraphGrid()
                    .stroke(
                        Color.primary.opacity(0.09),
                        style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
                    )
            }
            NormalizedGraphSeries(
                values: values,
                accent: accent,
                lineWidth: lineWidth,
                showsMarker: showsMarker
            )
        }
        .insetPlate()
    }
}

/// Two series drawn on one plate, the first behind the second. Used for network rates.
struct DualAreaGraph: View {
    let primary: [Double]
    let secondary: [Double]
    let primaryAccent: ModuleAccent
    let secondaryAccent: ModuleAccent

    var body: some View {
        ZStack {
            NormalizedGraphGrid()
                .stroke(
                    Color.primary.opacity(0.09),
                    style: StrokeStyle(lineWidth: 0.5, dash: [2, 3])
                )
            NormalizedGraphSeries(
                values: primary, accent: primaryAccent, lineWidth: 1.5, showsMarker: true)
            NormalizedGraphSeries(
                values: secondary, accent: secondaryAccent, lineWidth: 1.5, showsMarker: true)
        }
        .insetPlate()
    }
}

/// Series above and below a centerline. Used for disk reads and writes.
struct MirroredAreaGraph: View {
    let upper: [Double]
    let lower: [Double]
    let upperAccent: ModuleAccent
    let lowerAccent: ModuleAccent

    var body: some View {
        GeometryReader { geometry in
            let halfHeight = geometry.size.height / 2
            ZStack {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 0.5)
                VStack(spacing: 0) {
                    NormalizedGraphSeries(
                        values: upper, accent: upperAccent, lineWidth: 1.5, showsMarker: true)
                        .frame(height: halfHeight)
                    NormalizedGraphSeries(
                        values: lower, accent: lowerAccent, lineWidth: 1.5, showsMarker: true)
                        .frame(height: halfHeight)
                        .scaleEffect(x: 1, y: -1)
                }
            }
        }
        .insetPlate()
    }
}

/// Minimal gradient sparkline for table rows.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        NormalizedGraphSeries(
            values: values,
            accent: ModuleAccent(primary: color, secondary: color),
            lineWidth: 1.25,
            showsMarker: false,
            showsGlow: false,
            fillOpacity: (0.35, 0.02),
            verticalInset: 1.5
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct NormalizedGraphGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [0.25, 0.5, 0.75] {
            let y = rect.height * (1 - fraction)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct NormalizedGraphSeries: View {
    let values: [Double]
    let accent: ModuleAccent
    let lineWidth: CGFloat
    let showsMarker: Bool
    var showsGlow = true
    var fillOpacity: (top: Double, bottom: Double) = (0.42, 0.03)
    var verticalInset: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let horizontalInset: CGFloat = showsMarker ? 4 : 0
            let line = NormalizedGraphLine(
                values: values,
                horizontalInset: horizontalInset,
                verticalInset: verticalInset
            )
            ZStack {
                NormalizedGraphArea(
                    values: values,
                    horizontalInset: horizontalInset,
                    verticalInset: verticalInset
                )
                .fill(
                    LinearGradient(
                        colors: [accent.primary.opacity(fillOpacity.top), accent.secondary.opacity(fillOpacity.bottom)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                if showsGlow {
                    line
                        .stroke(accent.primary.opacity(0.55), lineWidth: lineWidth + 1.5)
                        .blur(radius: 3)
                }
                line.stroke(
                    LinearGradient(
                        colors: [accent.primary, accent.secondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                if showsMarker, values.count > 1,
                   let point = NormalizedGraphGeometry.point(
                    at: values.count - 1,
                    values: values,
                    size: geometry.size,
                    horizontalInset: horizontalInset,
                    verticalInset: verticalInset
                   ) {
                    Circle()
                        .fill(accent.secondary.opacity(0.28))
                        .frame(width: 10, height: 10)
                        .position(point)
                    Circle()
                        .fill(accent.secondary)
                        .frame(width: 5, height: 5)
                        .position(point)
                }
            }
        }
    }
}

private struct NormalizedGraphLine: Shape {
    let values: [Double]
    let horizontalInset: CGFloat
    let verticalInset: CGFloat

    func path(in rect: CGRect) -> Path {
        var line = Path()
        for index in values.indices {
            guard let point = NormalizedGraphGeometry.point(
                at: index,
                values: values,
                size: rect.size,
                horizontalInset: horizontalInset,
                verticalInset: verticalInset
            ) else { continue }
            index == 0 ? line.move(to: point) : line.addLine(to: point)
        }
        return line
    }
}

private struct NormalizedGraphArea: Shape {
    let values: [Double]
    let horizontalInset: CGFloat
    let verticalInset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard values.count > 1,
              let first = NormalizedGraphGeometry.point(
                at: 0,
                values: values,
                size: rect.size,
                horizontalInset: horizontalInset,
                verticalInset: verticalInset
              ),
              let last = NormalizedGraphGeometry.point(
                at: values.count - 1,
                values: values,
                size: rect.size,
                horizontalInset: horizontalInset,
                verticalInset: verticalInset
              ) else { return Path() }
        var area = NormalizedGraphLine(
            values: values,
            horizontalInset: horizontalInset,
            verticalInset: verticalInset
        ).path(in: rect)
        area.addLine(to: CGPoint(x: last.x, y: rect.maxY))
        area.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        area.closeSubpath()
        return area
    }
}

enum NormalizedGraphGeometry {
    static func point(
        at index: Int,
        values: [Double],
        size: CGSize,
        horizontalInset: CGFloat,
        verticalInset: CGFloat
    ) -> CGPoint? {
        guard values.count > 1, values.indices.contains(index) else { return nil }
        let fraction = CGFloat(index) / CGFloat(values.count - 1)
        let value = CGFloat(min(1, max(0, values[index])))
        let plotHeight = size.height - verticalInset * 2
        let plotWidth = size.width - horizontalInset * 2
        return CGPoint(
            x: horizontalInset + min(1, max(0, fraction)) * plotWidth,
            y: verticalInset + (1 - value) * plotHeight
        )
    }
}

// MARK: - Rows

/// Process row with icon, name, optional share bar, value, and a hover-revealed action.
struct ProcessRow<Trailing: View>: View {
    let icon: NSImage
    let name: String
    let detail: String
    var fraction: Double?
    let accent: ModuleAccent
    @ViewBuilder var trailing: () -> Trailing
    @State private var isHovering = false

    init(
        icon: NSImage,
        name: String,
        detail: String,
        fraction: Double? = nil,
        accent: ModuleAccent,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.name = name
        self.detail = detail
        self.fraction = fraction
        self.accent = accent
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.callout)
                    .lineLimit(1)
                if let fraction {
                    CapsuleBar(fraction: fraction, gradient: accent.horizontalGradient, height: 3)
                        .frame(maxWidth: 120)
                }
            }
            Spacer(minLength: 8)
            Text(detail)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
            trailing()
                .opacity(isHovering ? 1 : 0.35)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// Glass-styled footer button used for dropdown actions.
struct DropdownActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.glass)
        .controlSize(.small)
    }
}
