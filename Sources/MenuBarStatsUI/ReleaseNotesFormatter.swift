import AppKit
import Foundation

/// Converts the GitHub release-note Markdown Barometer supports into an efficient AppKit document.
enum ReleaseNotesFormatter {
    private enum Block {
        case heading(level: Int, text: String)
        case unordered(text: String)
        case ordered(marker: String, text: String)
        case quote(text: String)
        case code(text: String)
        case paragraph(text: String)
        case rule
    }

    static func attributedString(markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let blocks = blocks(markdown: markdown)
        for block in blocks {
            append(block, to: output)
        }
        return output
    }

    private static func blocks(markdown: String) -> [Block] {
        var blocks: [Block] = []
        var insideCodeFence = false
        var paragraphLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            var text = ""
            for line in paragraphLines {
                let explicitBreak = text.hasSuffix("  ")
                if !text.isEmpty {
                    if explicitBreak {
                        text.removeLast(2)
                        text += "\n"
                    } else {
                        text += " "
                    }
                }
                text += line
            }
            blocks.append(.paragraph(text: text))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            let line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                flushParagraph()
                insideCodeFence.toggle()
                continue
            }
            if insideCodeFence {
                blocks.append(.code(text: line))
            } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flushParagraph()
            } else {
                let block = block(for: line)
                if case let .paragraph(text) = block {
                    paragraphLines.append(text)
                } else {
                    flushParagraph()
                    blocks.append(block)
                }
            }
        }
        flushParagraph()
        return blocks
    }

    private static func block(for line: String) -> Block {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let headingMarks = trimmed.prefix(while: { $0 == "#" })
        if (1...6).contains(headingMarks.count),
           trimmed.dropFirst(headingMarks.count).first == " " {
            return .heading(
                level: headingMarks.count,
                text: String(trimmed.dropFirst(headingMarks.count + 1))
            )
        }
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            return .rule
        }
        if let marker = ["- ", "* ", "+ "].first(where: { trimmed.hasPrefix($0) }) {
            return .unordered(text: String(trimmed.dropFirst(marker.count)))
        }
        if let ordered = orderedItem(in: trimmed) {
            return .ordered(marker: ordered.marker, text: ordered.text)
        }
        if trimmed.hasPrefix(">") {
            return .quote(text: String(trimmed.dropFirst().drop(while: { $0 == " " })))
        }
        return .paragraph(text: trimmed)
    }

    private static func orderedItem(in line: String) -> (marker: String, text: String)? {
        let digits = line.prefix(while: \Character.isNumber)
        guard !digits.isEmpty else { return nil }
        let remainder = line.dropFirst(digits.count)
        guard let punctuation = remainder.first,
              punctuation == "." || punctuation == ")",
              remainder.dropFirst().first == " " else {
            return nil
        }
        return ("\(digits)\(punctuation)", String(remainder.dropFirst(2)))
    }

    private static func append(_ block: Block, to output: NSMutableAttributedString) {
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let bodyColor = NSColor.labelColor
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 7
        var prefix = ""
        var text: String
        var font = bodyFont
        var color = bodyColor
        var codeBlock = false

        switch block {
        case let .heading(level, value):
            text = value
            let size: CGFloat = switch level {
            case 1: 20
            case 2: 17
            case 3: 15
            default: NSFont.systemFontSize
            }
            font = .systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold)
            paragraphStyle.paragraphSpacingBefore = level == 1 ? 0 : 7
            paragraphStyle.paragraphSpacing = 8
        case let .unordered(value):
            prefix = "•\t"
            text = value
            configureListStyle(paragraphStyle)
        case let .ordered(marker, value):
            prefix = "\(marker)\t"
            text = value
            configureListStyle(paragraphStyle)
        case let .quote(value):
            prefix = "│  "
            text = value
            color = .secondaryLabelColor
            paragraphStyle.headIndent = 12
            paragraphStyle.firstLineHeadIndent = 0
        case let .code(value):
            text = value.isEmpty ? " " : value
            font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            codeBlock = true
            paragraphStyle.headIndent = 8
            paragraphStyle.firstLineHeadIndent = 8
            paragraphStyle.tailIndent = -8
            paragraphStyle.paragraphSpacing = 0
        case let .paragraph(value):
            text = value
        case .rule:
            let rule = NSAttributedString(
                string: "────────────\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.separatorColor,
                    .paragraphStyle: paragraphStyle,
                ]
            )
            output.append(rule)
            return
        }

        if !prefix.isEmpty {
            output.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color]))
        }
        let content = inlineMarkdown(text, baseFont: font, color: color)
        output.append(content)
        let blockRange = NSRange(
            location: output.length - content.length - prefix.utf16.count,
            length: content.length + prefix.utf16.count
        )
        output.addAttribute(.paragraphStyle, value: paragraphStyle, range: blockRange)
        if codeBlock {
            output.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: blockRange)
        }
        output.append(NSAttributedString(string: "\n"))
    }

    private static func configureListStyle(_ style: NSMutableParagraphStyle) {
        style.tabStops = [NSTextTab(textAlignment: .left, location: 18)]
        style.defaultTabInterval = 18
        style.headIndent = 18
        style.firstLineHeadIndent = 0
        style.paragraphSpacing = 3
    }

    private static func inlineMarkdown(_ source: String, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: source, options: options) else {
            return NSAttributedString(string: source, attributes: [.font: baseFont, .foregroundColor: color])
        }

        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let value = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent
            var font = baseFont
            if intent?.contains(.code) == true {
                font = .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
            } else {
                var traits: NSFontTraitMask = []
                if intent?.contains(.stronglyEmphasized) == true {
                    traits.insert(.boldFontMask)
                }
                if intent?.contains(.emphasized) == true {
                    traits.insert(.italicFontMask)
                }
                if !traits.isEmpty {
                    font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
                }
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: run.link == nil ? color : NSColor.linkColor,
            ]
            if intent?.contains(.code) == true {
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor
            }
            if intent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.append(NSAttributedString(string: value, attributes: attributes))
        }
        return output
    }
}
