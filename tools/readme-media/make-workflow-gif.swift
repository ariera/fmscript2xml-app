#!/usr/bin/env swift
// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Renders docs/images/workflow.gif: an illustration (not a screen recording)
// of the workflow. A text editor on the left, FileMaker's Script Workspace on
// the right: select the text, ⌘C, ⌃⌥⌘F, the success message, click into the
// Script Workspace, ⌘V, the steps appear.
//
//   swift tools/readme-media/make-workflow-gif.swift
//
// The script shown is tools/readme-media/demo-script.txt (synthetic, D14).

import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let script = try! String(contentsOf: root.appending(path: "tools/readme-media/demo-script.txt"), encoding: .utf8)
    .replacingOccurrences(of: "\t", with: "    ")
    .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    .filter { !$0.isEmpty }
let output = root.appending(path: "docs/images/workflow.gif")

// MARK: Layout

let W: CGFloat = 1010, H: CGFloat = 440
let fps: Double = 20
let menuBarHeight: CGFloat = 26
let left = CGRect(x: 18, y: 46, width: 452, height: 284)
let right = CGRect(x: 490, y: 46, width: 502, height: 284)
let titleBar: CGFloat = 30
let editorFont = NSFont(name: "Menlo", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
let lineHeight: CGFloat = 19
let textOrigin = CGPoint(x: left.minX + 18, y: left.minY + titleBar + 18)
let stepsOrigin = CGPoint(x: right.minX + 46, y: right.minY + titleBar + 46)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func charWidth(_ font: NSFont) -> CGFloat {
    ("M" as NSString).size(withAttributes: [.font: font]).width
}

let cw = charWidth(editorFont)
func lineEnd(_ i: Int) -> CGPoint {
    CGPoint(x: textOrigin.x + CGFloat(script[i].count) * cw, y: textOrigin.y + CGFloat(i) * lineHeight)
}

// MARK: Drawing helpers

func roundedRect(_ r: CGRect, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    fill.setFill()
    p.fill()
    if let stroke {
        stroke.setStroke()
        p.lineWidth = 1
        p.stroke()
    }
}

func text(_ s: String, at p: CGPoint, font: NSFont, color c: NSColor) {
    (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: c])
}

func textSize(_ s: String, font: NSFont) -> CGSize {
    (s as NSString).size(withAttributes: [.font: font])
}

func window(_ r: CGRect, title: String, active: Bool) {
    // Shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, active ? 0.28 : 0.16)
    shadow.shadowBlurRadius = active ? 18 : 10
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    roundedRect(r, 10, fill: .white)
    NSGraphicsContext.restoreGraphicsState()
    // Title bar
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
    color(active ? 0xEDEDED : 0xF5F5F5).setFill()
    CGRect(x: r.minX, y: r.minY, width: r.width, height: titleBar).fill()
    color(0xD6D6D6).setFill()
    CGRect(x: r.minX, y: r.minY + titleBar - 1, width: r.width, height: 1).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        let c = active ? color(UInt32(hex)) : color(0xD5D5D5)
        roundedRect(CGRect(x: r.minX + 13 + CGFloat(i) * 20, y: r.minY + 9, width: 12, height: 12), 6, fill: c)
    }
    let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    let size = textSize(title, font: font)
    text(title, at: CGPoint(x: r.midX - size.width / 2, y: r.minY + (titleBar - size.height) / 2), font: font,
         color: active ? color(0x3A3A3A) : color(0xAAAAAA))
}

func arrowCursor(at p: CGPoint) {
    let path = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4.2, 13.2), (7.3, 20), (9.6, 19), (6.6, 12.4), (12, 12.4)]
    path.move(to: CGPoint(x: p.x + pts[0].0, y: p.y + pts[0].1))
    for q in pts.dropFirst() { path.line(to: CGPoint(x: p.x + q.0, y: p.y + q.1)) }
    path.close()
    NSColor.black.setFill()
    path.fill()
    NSColor.white.setStroke()
    path.lineWidth = 1.4
    path.stroke()
}

func beamCursor(at p: CGPoint) {
    let path = NSBezierPath()
    path.move(to: CGPoint(x: p.x - 3, y: p.y - 9)); path.line(to: CGPoint(x: p.x + 3, y: p.y - 9))
    path.move(to: CGPoint(x: p.x, y: p.y - 9)); path.line(to: CGPoint(x: p.x, y: p.y + 9))
    path.move(to: CGPoint(x: p.x - 3, y: p.y + 9)); path.line(to: CGPoint(x: p.x + 3, y: p.y + 9))
    NSColor.white.setStroke(); path.lineWidth = 3.4; path.stroke()
    NSColor.black.setStroke(); path.lineWidth = 1.4; path.stroke()
}

/// Key caps with a caption, centred near the bottom.
func keys(_ caps: [String], caption: String, alpha: CGFloat) {
    guard alpha > 0 else { return }
    let capFont = NSFont.systemFont(ofSize: 22, weight: .medium)
    let captionFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    let capW: CGFloat = 46, gap: CGFloat = 8
    let width = CGFloat(caps.count) * capW + CGFloat(caps.count - 1) * gap + 36
    let panel = CGRect(x: W / 2 - width / 2, y: H - 88, width: width, height: 80)
    roundedRect(panel, 14, fill: color(0x1D1D1F, 0.86 * alpha))
    for (i, cap) in caps.enumerated() {
        let r = CGRect(x: panel.minX + 18 + CGFloat(i) * (capW + gap), y: panel.minY + 12, width: capW, height: 40)
        roundedRect(r, 7, fill: color(0xFFFFFF, alpha), stroke: color(0xBBBBBB, alpha))
        let s = textSize(cap, font: capFont)
        text(cap, at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2), font: capFont, color: color(0x1D1D1F, alpha))
    }
    let s = textSize(caption, font: captionFont)
    text(caption, at: CGPoint(x: panel.midX - s.width / 2, y: panel.maxY - 24), font: captionFont, color: color(0xFFFFFF, 0.9 * alpha))
}

/// The app's HUD: "8 steps ready to paste".
func hud(alpha: CGFloat) {
    guard alpha > 0 else { return }
    let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    let message = "\(script.count) steps ready to paste"
    let size = textSize(message, font: font)
    let panel = CGRect(x: W / 2 - (size.width + 66) / 2, y: 286, width: size.width + 66, height: 48)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.25 * alpha)
    shadow.shadowBlurRadius = 14
    shadow.set()
    roundedRect(panel, 14, fill: color(0xF7F7F7, alpha))
    NSGraphicsContext.restoreGraphicsState()
    let circle = CGRect(x: panel.minX + 18, y: panel.midY - 10, width: 20, height: 20)
    roundedRect(circle, 10, fill: color(0x30C048, alpha))
    let check = NSBezierPath()
    check.move(to: CGPoint(x: circle.minX + 5, y: circle.midY))
    check.line(to: CGPoint(x: circle.minX + 8.5, y: circle.midY + 4))
    check.line(to: CGPoint(x: circle.maxX - 5, y: circle.midY - 4))
    color(0xFFFFFF, alpha).setStroke()
    check.lineWidth = 2.2
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.stroke()
    text(message, at: CGPoint(x: circle.maxX + 10, y: panel.midY - size.height / 2), font: font, color: color(0x1D1D1F, alpha))
}

/// The menu bar glyph (same strokes as the app's menu bar icon), 18 pt.
func menuBarIcon(at origin: CGPoint, highlighted: Bool) {
    if highlighted {
        roundedRect(CGRect(x: origin.x - 5, y: origin.y - 3, width: 28, height: 22), 5, fill: color(0x000000, 0.12))
    }
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform()
    t.translateX(by: origin.x, yBy: origin.y - 1)
    t.concat()
    let ink = color(0x1D1D1F)
    ink.setStroke()
    for y: CGFloat in [5.4, 12.6] {
        let w = NSBezierPath()
        w.move(to: CGPoint(x: 1.2, y: y))
        var x: CGFloat = 1.2
        var up = true
        while x < 6.8 {
            w.curve(to: CGPoint(x: x + 1.8, y: y), controlPoint1: CGPoint(x: x + 0.6, y: y + (up ? -1.4 : 1.4)),
                    controlPoint2: CGPoint(x: x + 1.2, y: y + (up ? -1.4 : 1.4)))
            x += 1.8
            up.toggle()
        }
        w.lineWidth = 1.6
        w.lineCapStyle = .round
        w.stroke()
    }
    let strike = NSBezierPath()
    strike.move(to: CGPoint(x: 10.4, y: 0.6)); strike.line(to: CGPoint(x: 8.2, y: 9.7))
    strike.line(to: CGPoint(x: 10.6, y: 9.7)); strike.line(to: CGPoint(x: 8.4, y: 17.4))
    strike.lineWidth = 1.8
    strike.stroke()
    ink.setFill()
    NSBezierPath(roundedRect: CGRect(x: 11.9, y: 4.5, width: 5, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
    NSBezierPath(roundedRect: CGRect(x: 12.6, y: 11.7, width: 4.3, height: 1.8), xRadius: 0.9, yRadius: 0.9).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: Timeline

struct State {
    var cursor = CGPoint(x: 720, y: 250)
    var beam = false
    /// Selection end: line index and fraction of that line (nil: none).
    var selection: (line: Int, fraction: CGFloat)?
    var rightActive = false
    var caretVisible = false
    var pasted = false
    var keys: (caps: [String], caption: String, alpha: CGFloat)?
    var hudAlpha: CGFloat = 0
    var iconHighlighted = false
}

func ease(_ t: Double) -> CGFloat {
    let x = min(max(t, 0), 1)
    return CGFloat(x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2)
}

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

func fade(_ t: Double, from start: Double, to end: Double, ramp: Double = 0.15) -> CGFloat {
    guard t >= start, t <= end else { return 0 }
    return CGFloat(min(1, (t - start) / ramp, (end - t) / ramp))
}

let selectStart = CGPoint(x: textOrigin.x - 1, y: textOrigin.y + lineHeight / 2)
let pastePoint = CGPoint(x: right.minX + 250, y: right.maxY - 22)

func state(at t: Double) -> State {
    var s = State()
    // 0.4–1.2: move to the start of the text
    if t >= 0.4 { s.cursor = lerp(State().cursor, selectStart, ease((t - 0.4) / 0.8)) }
    if t >= 1.1 { s.beam = true }
    // 1.3–2.6: drag-select to the end
    if t >= 1.3 {
        let p = min(1, (t - 1.3) / 1.3)
        let total = Double(script.count) - 0.0001
        let pos = p * total
        let line = min(script.count - 1, Int(pos))
        let fraction = p >= 1 ? 1 : CGFloat(pos - Double(line))
        s.selection = (line, fraction)
        let end = lineEnd(line)
        s.cursor = CGPoint(x: textOrigin.x + (end.x - textOrigin.x) * fraction, y: end.y + lineHeight / 2)
    }
    // 2.8–3.8: ⌘C
    if t >= 2.8 && t < 3.9 { s.keys = (["⌘", "C"], "Copy", fade(t, from: 2.8, to: 3.9)) }
    // 4.1–5.2: ⌃⌥⌘F, the menu bar icon reacts, then the HUD
    if t >= 4.1 && t < 5.3 { s.keys = (["⌃", "⌥", "⌘", "F"], "Convert with FM Script Paste", fade(t, from: 4.1, to: 5.3)) }
    s.iconHighlighted = t >= 4.4 && t < 4.9
    s.hudAlpha = fade(t, from: 4.6, to: 6.6, ramp: 0.2)
    // 5.6–6.4: move to the Script Workspace and click
    if t >= 5.6 {
        s.beam = false
        let lastEnd = lineEnd(script.count - 1)
        s.cursor = lerp(CGPoint(x: lastEnd.x, y: lastEnd.y + lineHeight / 2), pastePoint, ease((t - 5.6) / 0.8))
    }
    if t >= 6.45 {
        s.rightActive = true
        s.caretVisible = true
        s.selection = (script.count - 1, 1)
    }
    // 6.8–7.9: ⌘V, the steps appear
    if t >= 6.8 && t < 7.9 { s.keys = (["⌘", "V"], "Paste", fade(t, from: 6.8, to: 7.9)) }
    if t >= 7.05 {
        s.pasted = true
        s.caretVisible = false
    }
    return s
}

// MARK: Frame

func render(_ s: State) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: H)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    // Desktop and menu bar
    color(0xD9E1EB).setFill()
    CGRect(x: 0, y: 0, width: W, height: H).fill()
    color(0xF3F5F8, 0.95).setFill()
    CGRect(x: 0, y: 0, width: W, height: menuBarHeight).fill()
    let menuFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    text(s.rightActive ? "FileMaker Pro" : "TextEdit", at: CGPoint(x: 18, y: 5),
         font: .systemFont(ofSize: 13, weight: .bold), color: color(0x1D1D1F))
    text("9:41", at: CGPoint(x: W - 46, y: 5), font: menuFont, color: color(0x1D1D1F))
    menuBarIcon(at: CGPoint(x: W - 82, y: 4), highlighted: s.iconHighlighted)

    // Text editor (left)
    window(left, title: "invoice-total.txt", active: !s.rightActive)
    if let sel = s.selection {
        let highlight = s.rightActive ? color(0xDCDCDC) : color(0xB4D5FE)
        highlight.setFill()
        for i in 0...sel.line {
            let full = lineEnd(i).x - textOrigin.x
            let width = i < sel.line ? full : full * sel.fraction
            CGRect(x: textOrigin.x, y: textOrigin.y + CGFloat(i) * lineHeight - 1, width: max(width, 0), height: lineHeight).fill()
        }
    }
    for (i, line) in script.enumerated() {
        text(line, at: CGPoint(x: textOrigin.x, y: textOrigin.y + CGFloat(i) * lineHeight), font: editorFont, color: color(0x1D1D1F))
    }

    // Script Workspace (right)
    window(right, title: "FileMaker Pro — Script Workspace", active: s.rightActive)
    let tab = CGRect(x: right.minX + 12, y: right.minY + titleBar + 8, width: 120, height: 24)
    roundedRect(tab, 6, fill: color(0xE6EEF9), stroke: color(0xC5D4EA))
    text("Update Totals", at: CGPoint(x: tab.minX + 12, y: tab.minY + 4), font: .systemFont(ofSize: 12, weight: .medium), color: color(0x1D3B66))
    let stepFont = editorFont
    let gutter = CGRect(x: right.minX + 1, y: stepsOrigin.y - 6, width: 32, height: right.maxY - stepsOrigin.y)
    color(0xF6F7F9).setFill()
    gutter.fill()
    if s.pasted {
        color(0xD5E4FB).setFill()
        CGRect(x: right.minX + 34, y: stepsOrigin.y - 2, width: right.width - 46, height: CGFloat(script.count) * 21).fill()
        for (i, line) in script.enumerated() {
            let y = stepsOrigin.y + CGFloat(i) * 21
            let n = "\(i + 1)"
            text(n, at: CGPoint(x: right.minX + 26 - textSize(n, font: .systemFont(ofSize: 10)).width, y: y + 1),
                 font: .systemFont(ofSize: 10), color: color(0x9A9A9A))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = CGFloat(line.prefix { $0 == " " }.count / 4) * 18
            let isComment = trimmed.hasPrefix("#")
            text(trimmed, at: CGPoint(x: stepsOrigin.x + indent, y: y), font: stepFont,
                 color: isComment ? color(0x3F8F4F) : color(0x1D1D1F))
        }
    } else if s.caretVisible {
        color(0x1D1D1F).setFill()
        CGRect(x: stepsOrigin.x, y: stepsOrigin.y - 1, width: 1.5, height: 17).fill()
    }

    hud(alpha: s.hudAlpha)
    if let k = s.keys { keys(k.caps, caption: k.caption, alpha: k.alpha) }
    if s.beam { beamCursor(at: s.cursor) } else { arrowCursor(at: s.cursor) }

    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

// MARK: Encode

let duration = 10.0
let frameCount = Int(duration * fps)
var frames: [(image: CGImage, delay: Double)] = []
var lastData: Data?
for f in 0..<frameCount {
    let image = render(state(at: Double(f) / fps))
    let data = NSBitmapImageRep(cgImage: image).tiffRepresentation
    if let lastData, data == lastData {
        frames[frames.count - 1].delay += 1 / fps  // merge identical frames
    } else {
        frames.append((image, 1 / fps))
        lastData = data
    }
}
frames[frames.count - 1].delay += 1.5  // hold the result before looping

try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    CGImageDestinationAddImage(destination, frame.image, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frame.delay,
            kCGImagePropertyGIFUnclampedDelayTime: frame.delay,
        ],
    ] as CFDictionary)
}
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("Wrote \(output.path): \(frames.count) frames, \(size / 1024) KB")
