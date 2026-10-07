#!/usr/bin/env swift
// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Draws the FM Script Paste logo and writes the app icon, the menu bar
// template icon and a README logo. Single source of truth for the artwork.
//
//   swift tools/icon/make-icons.swift
//
// The mark: a clipboard whose sides are the square brackets of a script step,
// `[ ]`, holding step rows ("Step Name" + parameters, the second one nested).

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

// MARK: The mark, on a 1024 grid

/// Brackets, clip and step rows. `rowAlpha` dims the parameter part of rows.
func drawMark(_ ctx: CGContext, color: CGColor, paramAlpha: CGFloat, clipHole: Bool) {
    let t: CGFloat = 58          // stroke thickness
    let top: CGFloat = 270, bottom: CGFloat = 800
    let left: CGFloat = 292, serif: CGFloat = 116
    let right = 1024 - left - t

    ctx.setFillColor(color)
    // [  left bracket
    roundedRect(ctx, left, top, t, bottom - top, 14)
    roundedRect(ctx, left, top, serif, t, 14)
    roundedRect(ctx, left, bottom - t, serif, t, 14)
    //  ]  right bracket
    roundedRect(ctx, right, top, t, bottom - top, 14)
    roundedRect(ctx, right + t - serif, top, serif, t, 14)
    roundedRect(ctx, right + t - serif, bottom - t, serif, t, 14)
    ctx.fillPath()

    // Clip: a wide base plate with a rounded tab, between the serifs
    roundedRect(ctx, 428, 244, 168, 68, 24)
    roundedRect(ctx, 512 - 56, 202, 112, 70, 32)
    ctx.fillPath()
    if clipHole {
        ctx.setBlendMode(.clear)
        roundedRect(ctx, 512 - 26, 224, 52, 20, 10)
        ctx.fillPath()
        ctx.setBlendMode(.normal)
    }

    // Step rows: name (solid) + parameters (dimmed); the middle one is nested
    let h: CGFloat = 46, r: CGFloat = 23
    let rows: [(y: CGFloat, name: (CGFloat, CGFloat), params: (CGFloat, CGFloat))] = [
        (404, (386, 500), (524, 638)),
        (510, (432, 528), (552, 638)),
        (616, (386, 470), (494, 580)),
    ]
    for row in rows {
        ctx.setFillColor(color)
        roundedRect(ctx, row.name.0, row.y, row.name.1 - row.name.0, h, r)
        ctx.fillPath()
        ctx.setFillColor(color.copy(alpha: color.alpha * paramAlpha)!)
        roundedRect(ctx, row.params.0, row.y, row.params.1 - row.params.0, h, r)
        ctx.fillPath()
    }
}

/// The full-colour app icon on the macOS icon grid (824 body in 1024).
func drawAppIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the body
    ctx.saveGState()
    shadow(ctx, y: 12, blur: 28, rgb(0x000000, 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(0x1B6FA8))
    ctx.fillPath()
    ctx.restoreGState()

    // Teal → deep blue gradient
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [rgb(0x3DD9C1), rgb(0x1F9FB8), rgb(0x1A4E9E)] as CFArray,
                              locations: [0, 0.45, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 300, y: 100), end: CGPoint(x: 724, y: 924),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft light from the top
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 620, options: [])
    // Hairline inner edge
    ctx.addPath(squircle)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    // White mark with a soft shadow, composited as one layer
    ctx.saveGState()
    shadow(ctx, y: 10, blur: 22, rgb(0x0B2A5C, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    drawMark(ctx, color: rgb(0xFFFFFF), paramAlpha: 0.55, clipHole: true)
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// The menu bar template: same mark, redrawn on an 18 pt grid with strokes
/// heavy enough for the menu bar.
func drawMenuBarIcon(_ ctx: CGContext) {
    let black = rgb(0x000000)
    ctx.setFillColor(black)
    let t: CGFloat = 1.9, top: CGFloat = 3.2, bottom: CGFloat = 16.6
    let left: CGFloat = 2.2, serif: CGFloat = 4.0, right = 18 - left - t
    roundedRect(ctx, left, top, t, bottom - top, 0.5)
    roundedRect(ctx, left, top, serif, t, 0.5)
    roundedRect(ctx, left, bottom - t, serif, t, 0.5)
    roundedRect(ctx, right, top, t, bottom - top, 0.5)
    roundedRect(ctx, right + t - serif, top, serif, t, 0.5)
    roundedRect(ctx, right + t - serif, bottom - t, serif, t, 0.5)
    // Clip
    roundedRect(ctx, 6.8, 2.2, 4.4, 2.2, 0.8)
    roundedRect(ctx, 7.8, 1.0, 2.4, 2.0, 0.8)
    ctx.fillPath()
    // Two step rows, the second nested
    roundedRect(ctx, 5.6, 7.3, 6.8, 1.9, 0.95)
    roundedRect(ctx, 7.4, 11.0, 5.0, 1.9, 0.95)
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
