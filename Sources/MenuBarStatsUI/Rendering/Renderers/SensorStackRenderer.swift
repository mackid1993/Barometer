import AppKit
import MenuBarStatsCore

/// One labeled, stable-width field in a compact Sensors stack.
public struct SensorStackValue {
    public let label: String
    public let value: String
    public let reservedValue: String
    /// Widest label this field may ever show; the column reserves its width.
    public let reservedLabel: String?

    /// Creates one menu bar sensor field.
    public init(label: String, value: String, reservedValue: String, reservedLabel: String? = nil) {
        self.label = label
        self.value = value
        self.reservedValue = reservedValue
        self.reservedLabel = reservedLabel
    }
}

/// Renders arbitrary labeled readings in matched two-row columns.
public struct SensorStackRenderer: MenuBarRenderer {
    private let values: [SensorStackValue]

    /// Creates a compact stack in user-selected order.
    public init(values: [SensorStackValue]) {
        self.values = values
    }

    static func displayLabel(_ label: String) -> String {
        guard !label.isEmpty, !label.hasSuffix(":") else { return label }
        return "\(label):"
    }

    /// Renders two readings per column and expands horizontally for additional values.
    @MainActor
    public func render(in context: RenderContext) -> NSImage {
        let metrics = MenuBarLayoutMetrics(context: context)
        let valuePointSize = metrics.compactPointSize
        let labelPointSize = valuePointSize
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: context.font(ofSize: labelPointSize, weight: context.fontWeight.nsWeight, monospacedDigits: false),
            .foregroundColor: context.foregroundColor.withAlphaComponent(MenuBarLayoutMetrics.labelEmphasis),
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: context.font(ofSize: valuePointSize, weight: context.fontWeight.nsWeight, monospacedDigits: true),
            .foregroundColor: context.foregroundColor,
        ]
        let fields =
            values.isEmpty
            ? [SensorStackValue(label: "SENS", value: "—", reservedValue: "999.9°C")]
            : values
        let columns = stride(from: 0, to: fields.count, by: 2).map { start in
            Array(fields[start..<min(start + 2, fields.count)])
        }
        let labelGap = metrics.densePairGap
        let columnGap = metrics.sensorColumnGap
        let sidePadding = metrics.denseTextPadding
        let labelWidths = columns.map { column in
            column.reduce(CGFloat(0)) { width, field in
                let liveLabelWidth = NSAttributedString(
                    string: Self.displayLabel(field.label),
                    attributes: labelAttributes
                ).size().width
                let reservedLabelWidth =
                    field.reservedLabel.map {
                        NSAttributedString(string: Self.displayLabel($0), attributes: labelAttributes).size().width
                    } ?? 0
                return max(width, ceil(max(liveLabelWidth, reservedLabelWidth)))
            }
        }
        let valueWidths = columns.map { column in
            column.reduce(CGFloat(0)) { width, field in
                let reservedWidth = NSAttributedString(
                    string: field.reservedValue,
                    attributes: valueAttributes
                ).size().width
                let valueWidth = NSAttributedString(string: field.value, attributes: valueAttributes).size().width
                return max(width, ceil(max(reservedWidth, valueWidth)))
            }
        }
        let columnWidths = zip(labelWidths, valueWidths).map { labelWidth, valueWidth in
            labelWidth + labelGap + valueWidth
        }
        let contentWidth =
            sidePadding * 2
            + columnWidths.reduce(0, +)
            + columnGap * CGFloat(max(0, columns.count - 1))

        return makeImage(width: contentWidth, context: context) { rect in
            var x = sidePadding
            for (columnIndex, column) in columns.enumerated() {
                let columnWidth = columnWidths[columnIndex]
                for (rowIndex, field) in column.enumerated() {
                    let label = NSAttributedString(
                        string: Self.displayLabel(field.label),
                        attributes: labelAttributes
                    )
                    let value = NSAttributedString(string: field.value, attributes: valueAttributes)
                    let origins = Self.rowOrigins(
                        columnX: x,
                        columnWidth: columnWidth,
                        labelWidth: label.size().width,
                        valueWidth: value.size().width,
                        gap: labelGap,
                        backingScaleFactor: context.backingScaleFactor
                    )
                    let combinedHeight = max(label.size().height, value.size().height)
                    let y =
                        fields.count == 1
                        ? floor((rect.height - combinedHeight) / 2)
                        : metrics.compactRowY(rowIndex, textHeight: combinedHeight)
                    label.draw(at: NSPoint(x: origins.label, y: y))
                    value.draw(at: NSPoint(x: origins.value, y: y))
                }
                x += columnWidth + columnGap
            }
        }
    }

    /// Keeps each label attached to its reading and balances unused reserve around the pair.
    static func rowOrigins(
        columnX: CGFloat,
        columnWidth: CGFloat,
        labelWidth: CGFloat,
        valueWidth: CGFloat,
        gap: CGFloat,
        backingScaleFactor: CGFloat
    ) -> (label: CGFloat, value: CGFloat) {
        let unusedWidth = max(0, columnWidth - labelWidth - gap - valueWidth)
        let scale = max(1, backingScaleFactor)
        let label = columnX + floor(unusedWidth / 2 * scale) / scale
        let labelEdge = ceil((label + labelWidth) * scale) / scale
        return (label, labelEdge + gap)
    }
}
