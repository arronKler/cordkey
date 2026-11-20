import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Generates the macOS squircle AppIcon.iconset using pure CoreGraphics vector drawing
/// based on Icon Concept 03 ("Tactile Inline Remote").
enum IconGenerator {
    static func writeIconset(to directory: String) -> Never {
        let dirURL = URL(fileURLWithPath: directory)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let specs: [(String, Int)] = [
                ("icon_16x16.png", 16),
                ("icon_16x16@2x.png", 32),
                ("icon_32x32.png", 32),
                ("icon_32x32@2x.png", 64),
                ("icon_128x128.png", 128),
                ("icon_128x128@2x.png", 256),
                ("icon_256x256.png", 256),
                ("icon_256x256@2x.png", 512),
                ("icon_512x512.png", 512),
                ("icon_512x512@2x.png", 1024),
            ]
            for (filename, px) in specs {
                let data = renderIconPNG(size: px)
                try data.write(to: dirURL.appendingPathComponent(filename))
            }
            exit(0)
        } catch {
            FileHandle.standardError.write("failed to generate iconset: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    private static func rgba(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
        let r = CGFloat((hex >> 16) & 0xff) / 255.0
        let g = CGFloat((hex >> 8) & 0xff) / 255.0
        let b = CGFloat(hex & 0xff) / 255.0
        return CGColor(colorSpace: srgb, components: [r, g, b, alpha])!
    }

    private static func makeGradient(colors: [(CGColor, CGFloat)]) -> CGGradient? {
        let cgColors = colors.map(\.0) as CFArray
        let locations = colors.map(\.1)
        return CGGradient(colorsSpace: srgb, colors: cgColors, locations: locations)
    }

    private static func renderIconPNG(size: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = NSSize(width: size, height: size)

        guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let ctx = nsCtx.cgContext
        let s = CGFloat(size)
        let scale = s / 1024.0

        // Flip into SVG top-down 1024x1024 coordinate space so + sits at top and − at bottom.
        ctx.translateBy(x: 0, y: s)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // 1. Dark anodized titanium squircle base (100, 100, 824, 824, rx: 186)
        let baseRect = CGRect(x: 100, y: 100, width: 824, height: 824)
        let basePath = CGPath(roundedRect: baseRect, cornerWidth: 186, cornerHeight: 186, transform: nil)

        ctx.saveGState()
        ctx.addPath(basePath)
        ctx.clip()

        if let bgGrad = makeGradient(colors: [
            (rgba(0x2c303a), 0.0),
            (rgba(0x1b1e25), 0.5),
            (rgba(0x111318), 1.0),
        ]) {
            ctx.drawLinearGradient(
                bgGrad,
                start: CGPoint(x: 100, y: 100),
                end: CGPoint(x: 100 + 824 * 0.85, y: 924),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Subtle warm orange ambient radial glow centered behind capsule
        if let ambientGrad = makeGradient(colors: [
            (rgba(0xff6b35, alpha: 0.28), 0.0),
            (rgba(0xff6b35, alpha: 0.0), 1.0),
        ]) {
            ctx.drawRadialGradient(
                ambientGrad,
                startCenter: CGPoint(x: 512, y: 512),
                startRadius: 0,
                endCenter: CGPoint(x: 512, y: 512),
                endRadius: 824 * 0.45,
                options: []
            )
        }

        // 2. Vertical audio cord running through top & bottom inside squircle
        ctx.setLineCap(.butt)
        ctx.setStrokeColor(rgba(0x525b6d))
        ctx.setLineWidth(34)
        ctx.move(to: CGPoint(x: 512, y: 100))
        ctx.addLine(to: CGPoint(x: 512, y: 924))
        ctx.strokePath()

        ctx.setStrokeColor(rgba(0x8590a6, alpha: 0.45))
        ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: 504, y: 100))
        ctx.addLine(to: CGPoint(x: 504, y: 924))
        ctx.strokePath()

        ctx.restoreGState()

        // Crisp light inner rim on squircle base
        let rimRect = CGRect(x: 104, y: 104, width: 816, height: 816)
        let rimPath = CGPath(roundedRect: rimRect, cornerWidth: 182, cornerHeight: 182, transform: nil)
        ctx.addPath(rimPath)
        ctx.setStrokeColor(rgba(0xffffff, alpha: 0.14))
        ctx.setLineWidth(6)
        ctx.strokePath()

        // 3. Machined aluminum inline remote capsule (372, 218, 280, 588, rx: 140)
        let capsuleRect = CGRect(x: 372, y: 218, width: 280, height: 588)
        let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: 140, cornerHeight: 140, transform: nil)

        // Drop shadow (default Quartz space: negative height = downward on screen)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -28 * scale),
            blur: 36 * scale,
            color: rgba(0x000000, alpha: 0.68)
        )
        ctx.addPath(capsulePath)
        ctx.setFillColor(rgba(0xd8dde6))
        ctx.fillPath()
        ctx.restoreGState()

        // Metallic light gradient fill
        ctx.saveGState()
        ctx.addPath(capsulePath)
        ctx.clip()
        if let capGrad = makeGradient(colors: [
            (rgba(0xf5f7fa), 0.0),
            (rgba(0xd8dde6), 0.55),
            (rgba(0xaeb6c4), 1.0),
        ]) {
            ctx.drawLinearGradient(
                capGrad,
                start: CGPoint(x: 372, y: 218),
                end: CGPoint(x: 652, y: 806),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Capsule inner white specular rim
        let capRimRect = CGRect(x: 378, y: 224, width: 268, height: 576)
        let capRimPath = CGPath(roundedRect: capRimRect, cornerWidth: 134, cornerHeight: 134, transform: nil)
        ctx.addPath(capRimPath)
        ctx.setStrokeColor(rgba(0xffffff, alpha: 0.78))
        ctx.setLineWidth(6)
        ctx.strokePath()

        // 4. Subtle etched + (top, y: 316) and − (bottom, y: 708)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(rgba(0x5b6475))
        ctx.setLineWidth(18)

        ctx.move(to: CGPoint(x: 482, y: 316))
        ctx.addLine(to: CGPoint(x: 542, y: 316))
        ctx.move(to: CGPoint(x: 512, y: 286))
        ctx.addLine(to: CGPoint(x: 512, y: 346))
        ctx.move(to: CGPoint(x: 482, y: 708))
        ctx.addLine(to: CGPoint(x: 542, y: 708))
        ctx.strokePath()

        // 5. Tactile Signal-Orange center keycap button (410, 406, 204, 212, rx: 64)
        let btnRect = CGRect(x: 410, y: 406, width: 204, height: 212)
        let btnPath = CGPath(roundedRect: btnRect, cornerWidth: 64, cornerHeight: 64, transform: nil)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 16 * scale,
            color: rgba(0x8a1c00, alpha: 0.42)
        )
        ctx.addPath(btnPath)
        ctx.setFillColor(rgba(0xf95722))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(btnPath)
        ctx.clip()
        if let btnGrad = makeGradient(colors: [
            (rgba(0xff7a45), 0.0),
            (rgba(0xf95722), 0.5),
            (rgba(0xd9380b), 1.0),
        ]) {
            ctx.drawLinearGradient(
                btnGrad,
                start: CGPoint(x: 410 + 204 * 0.2, y: 406),
                end: CGPoint(x: 410 + 204 * 0.8, y: 618),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        ctx.restoreGState()

        // Subtle inner peach rim
        let btnRimRect = CGRect(x: 416, y: 412, width: 192, height: 200)
        let btnRimPath = CGPath(roundedRect: btnRimRect, cornerWidth: 58, cornerHeight: 58, transform: nil)
        ctx.addPath(btnRimPath)
        ctx.setStrokeColor(rgba(0xffba99, alpha: 0.65))
        ctx.setLineWidth(5)
        ctx.strokePath()

        // Crisp white rounded center tactile bar (474, 498, 76, 28, rx: 14)
        let barRect = CGRect(x: 474, y: 498, width: 76, height: 28)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.addPath(barPath)
        ctx.setFillColor(rgba(0xffffff, alpha: 0.95))
        ctx.fillPath()

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

/// Custom 18×18pt pure-vector Menu Bar icons matching Concept 03 ("Tactile Inline Remote").
enum MenuBarIcons {
    static let signalOrange = NSColor(srgbRed: 0.976, green: 0.341, blue: 0.133, alpha: 1.0) // #F95722

    static let idleImage: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            drawCordStubs(lineWidth: 1.5)

            let capsule = NSBezierPath(
                roundedRect: NSRect(x: 5.4, y: 3.2, width: 7.2, height: 11.6),
                xRadius: 3.6,
                yRadius: 3.6
            )
            capsule.lineWidth = 1.55
            capsule.stroke()

            let button = NSBezierPath(
                roundedRect: NSRect(x: 7.1, y: 6.8, width: 3.8, height: 4.4),
                xRadius: 1.3,
                yRadius: 1.3
            )
            button.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    static let activeImage: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.labelColor.withAlphaComponent(0.85).setStroke()
            drawCordStubs(lineWidth: 1.5)

            let capsule = NSBezierPath(
                roundedRect: NSRect(x: 5.4, y: 3.2, width: 7.2, height: 11.6),
                xRadius: 3.6,
                yRadius: 3.6
            )
            signalOrange.setFill()
            capsule.fill()

            // Crisp inverted white center keycap indicator
            let button = NSBezierPath(
                roundedRect: NSRect(x: 7.1, y: 6.8, width: 3.8, height: 4.4),
                xRadius: 1.3,
                yRadius: 1.3
            )
            NSColor.white.setFill()
            button.fill()
            return true
        }
        img.isTemplate = false
        return img
    }()

    private static func drawCordStubs(lineWidth: CGFloat) {
        let cord = NSBezierPath()
        cord.lineWidth = lineWidth
        cord.lineCapStyle = .round
        cord.move(to: NSPoint(x: 9, y: 1.5))
        cord.line(to: NSPoint(x: 9, y: 3.3))
        cord.move(to: NSPoint(x: 9, y: 14.7))
        cord.line(to: NSPoint(x: 9, y: 16.5))
        cord.stroke()
    }
}

/// Miniature SwiftUI rendering of Concept 03 ("Tactile Inline Remote") for the Popover header.
struct CordKeyBadgeView: View {
    let enabled: Bool
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.173, green: 0.188, blue: 0.227),
                            Color(red: 0.106, green: 0.118, blue: 0.145),
                            Color(red: 0.067, green: 0.075, blue: 0.094),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if enabled {
                RadialGradient(
                    colors: [Color(red: 1.0, green: 0.420, blue: 0.208).opacity(0.28), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 14
                )
            }

            Rectangle()
                .fill(Color(red: 0.322, green: 0.357, blue: 0.427))
                .frame(width: 1.4, height: 30)

            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.961, green: 0.969, blue: 0.980),
                                Color(red: 0.847, green: 0.867, blue: 0.902),
                                Color(red: 0.682, green: 0.714, blue: 0.769),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.65), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.55), radius: 1.5, x: 0, y: 1)
                    .frame(width: 10.5, height: 21)

                VStack(spacing: 1.8) {
                    ZStack {
                        Capsule().frame(width: 2.6, height: 0.7)
                        Capsule().frame(width: 0.7, height: 2.6)
                    }
                    .foregroundColor(Color(red: 0.357, green: 0.392, blue: 0.459))

                    ZStack {
                        RoundedRectangle(cornerRadius: 2.3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.478, blue: 0.271),
                                        accent,
                                        Color(red: 0.851, green: 0.220, blue: 0.043),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 7.4, height: 7.8)
                        Capsule()
                            .fill(Color.white.opacity(0.95))
                            .frame(width: 2.8, height: 1.0)
                    }

                    Capsule()
                        .fill(Color(red: 0.357, green: 0.392, blue: 0.459))
                        .frame(width: 2.6, height: 0.7)
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(RoundedRectangle(cornerRadius: 7.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .saturation(enabled ? 1.0 : 0.25)
        .opacity(enabled ? 1.0 : 0.65)
    }
}
