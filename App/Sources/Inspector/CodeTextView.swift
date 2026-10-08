// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// A plain-text code view (NSTextView) with line numbers, gutter marks,
/// a highlighted range, and hover/click/cursor callbacks. Editable or
/// read-only. Text substitutions (smart quotes, dashes, …) are off, since
/// they would change the script.
struct CodeTextView: NSViewRepresentable {
    /// The text to show. A plain value plus `onTextChange` rather than a
    /// Binding: a custom Binding reading @Observable state gets re-evaluated
    /// by SwiftUI outside view updates, which crashes Observation tracking.
    var text: String
    var onTextChange: ((String) -> Void)?
    var isEditable = true
    /// Foreground colours for ranges (UTF-16), e.g. XML syntax tint.
    var colors: [(NSRange, NSColor)] = []
    /// Background highlight (UTF-16), e.g. the linked step.
    var highlight: NSRange?
    /// Line number → mark colour in the gutter.
    var lineMarks: [Int: NSColor] = [:]
    /// Changing this scrolls `highlight` into view.
    var revealToken = 0
    var onCursorLine: ((Int) -> Void)?
    /// UTF-16 offset under the mouse, or nil when it leaves.
    var onHoverOffset: ((Int?) -> Void)?
    var onClickOffset: ((Int) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = HoverTextView()
        textView.coordinator = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 6)
        // No wrapping: scroll horizontally like a code editor
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        let ruler = LineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Applying text and attributes makes AppKit lay out synchronously,
        // which would re-enter SwiftUI's view graph in the middle of this
        // update (and corrupt Observation tracking). Apply right after it.
        context.coordinator.schedule(self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextView
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        var lastRevealToken = 0
        var isApplyingUpdate = false
        private var scheduled = false

        func schedule(_ config: CodeTextView) {
            parent = config
            guard !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                self.apply(self.parent)
            }
        }

        private func apply(_ config: CodeTextView) {
            guard let textView else { return }
            isApplyingUpdate = true
            defer { isApplyingUpdate = false }
            textView.isEditable = config.isEditable
            textView.isSelectable = true

            if textView.string != config.text {
                let selection = textView.selectedRanges
                let length = (config.text as NSString).length
                textView.string = config.text
                let kept = selection.filter { $0.rangeValue.upperBound <= length }
                textView.selectedRanges = kept.isEmpty ? [NSValue(range: NSRange(location: length, length: 0))] : kept
            }

            // Syntax colours (attributes on the text storage; read-only use)
            if let storage = textView.textStorage, !(config.colors.isEmpty && config.isEditable) {
                let full = NSRange(location: 0, length: storage.length)
                storage.beginEditing()
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
                for (range, color) in config.colors where NSMaxRange(range) <= storage.length {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
                storage.endEditing()
            }

            // Highlight (temporary attributes don't touch the text)
            let length = (textView.string as NSString).length
            if let layout = textView.layoutManager {
                layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
                if let highlight = config.highlight, NSMaxRange(highlight) <= length {
                    layout.addTemporaryAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(0.18),
                                                 forCharacterRange: highlight)
                }
            }

            if ruler?.marks != config.lineMarks { ruler?.marks = config.lineMarks }
            ruler?.needsDisplay = true

            if config.revealToken != lastRevealToken {
                lastRevealToken = config.revealToken
                if let highlight = config.highlight, NSMaxRange(highlight) <= length {
                    textView.scrollRangeToVisible(highlight)
                }
            }
        }

        init(_ parent: CodeTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView else { return }
            if parent.text != textView.string { parent.onTextChange?(textView.string) }
            ruler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isApplyingUpdate, let textView else { return }
            let line = lineNumber(at: textView.selectedRange().location, in: textView.string)
            // Deliver outside the current event/update cycle
            DispatchQueue.main.async { [weak self] in self?.parent.onCursorLine?(line) }
        }

        func hover(_ offset: Int?) {
            DispatchQueue.main.async { [weak self] in self?.parent.onHoverOffset?(offset) }
        }

        func click(_ offset: Int) {
            DispatchQueue.main.async { [weak self] in self?.parent.onClickOffset?(offset) }
        }
    }
}

/// UTF-16 offsets where each line starts. Line breaks are "\n", "\r\n" and
/// "\r", as the converter counts them (universal newlines).
func lineStarts(in text: String) -> [Int] {
    let ns = text as NSString
    var starts = [0]
    var i = 0
    while i < ns.length {
        let c = ns.character(at: i)
        if c == 0x0D, i + 1 < ns.length, ns.character(at: i + 1) == 0x0A { i += 1 }
        if c == 0x0A || c == 0x0D { starts.append(i + 1) }
        i += 1
    }
    return starts
}

/// 1-based line number of a UTF-16 offset.
func lineNumber(at offset: Int, in text: String) -> Int {
    let starts = lineStarts(in: text)
    var line = 1
    for (i, start) in starts.enumerated() where start <= offset { line = i + 1 }
    return line
}

/// UTF-16 range covering lines `lines` (1-based) of `text`, without the last
/// line break.
func utf16Range(ofLines lines: ClosedRange<Int>, in text: String) -> NSRange? {
    let starts = lineStarts(in: text)
    let length = (text as NSString).length
    guard lines.lowerBound >= 1, lines.lowerBound <= starts.count else { return nil }
    let start = starts[lines.lowerBound - 1]
    var end = lines.upperBound < starts.count ? starts[lines.upperBound] : length
    let ns = text as NSString
    while end > start, [0x0A, 0x0D].contains(ns.character(at: end - 1)) { end -= 1 }
    return NSRange(location: start, length: end - start)
}

/// NSTextView that reports the character under the mouse.
final class HoverTextView: NSTextView {
    weak var coordinator: CodeTextView.Coordinator?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func offset(for event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        guard point.y >= rect.minY, point.y <= rect.maxY + 2 else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        coordinator?.hover(offset(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        coordinator?.hover(nil)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let o = offset(for: event) { coordinator?.click(o) }
    }
}

/// Line numbers, plus a coloured bar on lines with errors or warnings.
final class LineNumberRuler: NSRulerView {
    var marks: [Int: NSColor] = [:]
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(redraw),
                                               name: NSView.boundsDidChangeNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let text = textView.string as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let firstChar = layoutManager.characterIndexForGlyph(at: glyphs.location)
        var line = lineNumber(at: firstChar, in: textView.string)
        // Start at the beginning of the first visible line
        var index = text.lineRange(for: NSRange(location: firstChar, length: 0)).location
        let originY = convert(NSPoint.zero, from: textView).y + textView.textContainerOrigin.y

        func drawLine(_ y: CGFloat, _ height: CGFloat) {
            if let mark = marks[line] {
                mark.setFill()
                NSRect(x: 0, y: y, width: 3, height: height).fill()
            }
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + (height - size.height) / 2), withAttributes: attributes)
        }

        while index < text.length {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))
            let glyph = layoutManager.glyphIndexForCharacter(at: lineRange.location)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = fragment.minY + originY
            if y > bounds.maxY { break }
            drawLine(y, fragment.height)
            index = NSMaxRange(lineRange)
            line += 1
        }
        // An empty last line (after a trailing newline, or empty text)
        if text.length == 0 || text.hasSuffix("\n") {
            let fragment = layoutManager.extraLineFragmentRect
            let height = fragment.height > 0 ? fragment.height : 15
            drawLine(fragment.minY + originY, height)
        }
    }
}
