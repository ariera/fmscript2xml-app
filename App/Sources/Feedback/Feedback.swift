// Copyright © 2026 the fmscript2xml-app contributors. Created by Alejandro Riera.
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// HUD and sound feedback after a conversion.
@MainActor
final class Feedback {
    static let shared = Feedback()

    enum Kind {
        case success(String), warning(String), failure(String), info(String)

        var message: String {
            switch self {
            case .success(let m), .warning(let m), .failure(let m), .info(let m): return m
            }
        }

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            case .info: return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .failure: return .red
            case .info: return .secondary
            }
        }

        var sound: NSSound.Name? {
            switch self {
            case .success: return "Tink"
            case .warning: return "Pop"
            case .failure: return "Basso"
            case .info: return nil
            }
        }
    }

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ kind: Kind) {
        #if DEBUG
        debugLog("feedback: \(kind.message)")
        #endif
        if AppSettings.playSound, let name = kind.sound { NSSound(named: name)?.play() }
        guard AppSettings.showHUD else { return }
        showHUD(kind)
    }

    private func showHUD(_ kind: Kind) {
        hideTask?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: HUDView(kind: kind))
        panel.contentView = hosting
        let size = hosting.fittingSize
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.18,
                                  width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return p
    }
}

private struct HUDView: View {
    let kind: Feedback.Kind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.symbol)
                .font(.title2)
                .foregroundStyle(kind.tint)
            Text(kind.message)
                .font(.system(size: 15, weight: .medium))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .fixedSize()
    }
}
