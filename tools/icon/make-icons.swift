#!/usr/bin/env swift
// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the fmscript2xml logo and writes the app icon, the menu bar
// template icon and a README logo. Single source of truth for the artwork.
//
//   swift tools/icon/make-icons.swift
//
// The story: before, script steps were retyped by hand (grey, scribbled
// lines); a lightning strike splits the tile; after, they are FileMaker
// steps (teal, clean step rows), each beside the line it came from.

import AppKit

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appending(path: "App/Sources/Assets.xcassets")

// MARK: Drawing helpers (top-left origin)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func roundedRect(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
    ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                       cornerWidth: min(r, w / 2), cornerHeight: min(r, h / 2), transform: nil))
}

/// Pixels per design unit of the image being rendered. Shadow offsets and
/// blur are in device space, so they're scaled by hand.
nonisolated(unsafe) var deviceScale: CGFloat = 1

func shadow(_ ctx: CGContext, y: CGFloat, blur: CGFloat, _ color: CGColor) {
    // Device space has y up, so a downward offset is negative
    ctx.setShadow(offset: CGSize(width: 0, height: -y * deviceScale), blur: blur * deviceScale, color: color)
}

func render(pixels: Int, unit: CGFloat, _ draw: (CGContext) -> Void) -> Data {
    deviceScale = CGFloat(pixels) / unit
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    // Flip to a top-left origin and scale from design units to pixels
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: CGFloat(pixels) / unit, y: -CGFloat(pixels) / unit)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: Shapes

func scribble(_ ctx: CGContext, x: CGFloat, y: CGFloat, width: CGFloat, amp: CGFloat, wave: CGFloat, lineWidth: CGFloat, _ color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: x, y: y))
    var t: CGFloat = 0
    var up = true
    while t < width {
        let step = min(wave / 2, width - t)
        ctx.addQuadCurve(to: CGPoint(x: x + t + step, y: y),
                         control: CGPoint(x: x + t + step / 2, y: y + (up ? -amp : amp) * 2))
        t += step
        up.toggle()
    }
    ctx.strokePath()
}

func polyline(_ ctx: CGContext, _ points: [CGPoint], _ color: CGColor, lineWidth: CGFloat) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.butt)
    ctx.setLineJoin(.round)
    ctx.move(to: points[0])
    for p in points.dropFirst() { ctx.addLine(to: p) }
    ctx.strokePath()
}

/// A step row: the step name (solid) and its parameters (dimmed).
func stepRow(_ ctx: CGContext, x: CGFloat, y: CGFloat, name: CGFloat, params: CGFloat, height: CGFloat, gap: CGFloat, _ color: CGColor, paramAlpha: CGFloat) {
    ctx.setFillColor(color)
    roundedRect(ctx, x, y, name, height, height / 2)
    ctx.fillPath()
    ctx.setFillColor(color.copy(alpha: color.alpha * paramAlpha)!)
    roundedRect(ctx, x + name + gap, y, params, height, height / 2)
    ctx.fillPath()
}

// MARK: App icon, on the 1024 macOS icon grid (824 body)

let amber = rgb(0xF7B731)

/// The lightning seam: top to bottom, with one zig in the middle.
let seam: [CGPoint] = [CGPoint(x: 560, y: 0), CGPoint(x: 470, y: 540), CGPoint(x: 560, y: 540), CGPoint(x: 470, y: 1024)]
/// Line positions: each scribble on the left becomes the step beside it.
let lineYs: [CGFloat] = [366, 494, 622]

func drawAppIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body
    ctx.saveGState()
    shadow(ctx, y: 12, blur: 28, rgb(0x000000, 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0x1A5FA8))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // After: teal → deep blue
    let space = CGColorSpace(name: CGColorSpace.sRGB)
    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x3DD9C1), rgb(0x1A5FA8)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 100), end: CGPoint(x: 724, y: 924),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Before: flat grey, up to the seam
    ctx.setFillColor(rgb(0x4A505C))
    ctx.move(to: .zero)
    for p in seam { ctx.addLine(to: p) }
    ctx.addLine(to: CGPoint(x: 0, y: 1024))
    ctx.closePath()
    ctx.fillPath()

    // Soft light from the top
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 620, options: [])

    // The strike
    polyline(ctx, seam, amber, lineWidth: 34)

    // Hairline inner edge
    ctx.addPath(squircle)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // Before: hand-typed lines
    for (y, width) in zip(lineYs, [240, 180, 220] as [CGFloat]) {
        scribble(ctx, x: 160, y: y + 23, width: width, amp: 13, wave: 54, lineWidth: 26, rgb(0x9AA3B2))
    }

    // After: FileMaker steps, with a soft shadow
    ctx.saveGState()
    shadow(ctx, y: 10, blur: 22, rgb(0x0B2A5C, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let white = rgb(0xFFFFFF)
    stepRow(ctx, x: 600, y: lineYs[0], name: 130, params: 120, height: 46, gap: 22, white, paramAlpha: 0.55)
    stepRow(ctx, x: 646, y: lineYs[1], name: 104, params: 104, height: 46, gap: 22, white, paramAlpha: 0.55)
    stepRow(ctx, x: 600, y: lineYs[2], name: 110, params: 130, height: 46, gap: 22, white, paramAlpha: 0.55)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// MARK: Menu bar template icon, on an 18 pt grid

/// The same story reduced to strokes: two typed lines, the strike, two steps.
func drawMenuBarIcon(_ ctx: CGContext) {
    let black = rgb(0x000000)
    for y: CGFloat in [5.4, 12.6] {
        scribble(ctx, x: 1.2, y: y, width: 5.6, amp: 0.85, wave: 3.6, lineWidth: 1.6, black)
    }
    polyline(ctx, [CGPoint(x: 10.4, y: 0.6), CGPoint(x: 8.2, y: 9.7), CGPoint(x: 10.6, y: 9.7), CGPoint(x: 8.4, y: 17.4)],
             black, lineWidth: 1.8)
    ctx.setFillColor(black)
    roundedRect(ctx, 11.9, 4.5, 5.0, 1.8, 0.9)
    roundedRect(ctx, 12.6, 11.7, 4.3, 1.8, 0.9)
    ctx.fillPath()
}

// MARK: Output

func write(_ data: Data, _ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func contents(_ json: String) -> Data { Data((json + "\n").utf8) }

// App icon: 16–512 pt at 1x and 2x
let appIcon = assets.appending(path: "AppIcon.appiconset")
var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try write(render(pixels: pt * scale, unit: 1024, drawAppIcon), appIcon.appending(path: name))
        images.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(pt)x\#(pt)" }"#)
    }
}
try write(contents("""
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""), appIcon.appending(path: "Contents.json"))

// Menu bar template icon: 18 pt at 1x and 2x
let menuIcon = assets.appending(path: "MenuBarIcon.imageset")
for scale in [1, 2] {
    try write(render(pixels: 18 * scale, unit: 18, drawMenuBarIcon),
              menuIcon.appending(path: "menubar\(scale == 1 ? "" : "@\(scale)x").png"))
}
try write(contents("""
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
"""), menuIcon.appending(path: "Contents.json"))

try write(contents(#"{ "info" : { "author" : "xcode", "version" : 1 } }"#), assets.appending(path: "Contents.json"))

// README logo
try write(render(pixels: 256, unit: 1024, drawAppIcon), root.appending(path: "docs/logo.png"))

print("Wrote \(appIcon.path), \(menuIcon.path) and docs/logo.png")
