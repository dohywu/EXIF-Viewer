import AppKit

// Renders the app icon: a dark rounded tile, a cyan aperture ring and
// metadata bars, suggesting "inspect what is inside an image".
func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024.0
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    let bg = CGPath(roundedRect: rect.insetBy(dx: 40 * s, dy: 40 * s),
                    cornerWidth: 200 * s, cornerHeight: 200 * s, transform: nil)
    ctx.saveGState()
    ctx.addPath(bg); ctx.clip()
    let colors = [NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.17, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // metadata bars
    let barColors = [NSColor(calibratedRed: 0.26, green: 0.68, blue: 0.95, alpha: 0.95),
                     NSColor(calibratedRed: 0.65, green: 0.52, blue: 0.95, alpha: 0.9),
                     NSColor(calibratedRed: 0.35, green: 0.78, blue: 0.55, alpha: 0.85),
                     NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.33, alpha: 0.8)]
    let widths: [CGFloat] = [380, 300, 340, 240]
    for i in 0..<4 {
        barColors[i].setFill()
        let y = 640 - CGFloat(i) * 92
        let r = CGRect(x: 170 * s, y: y * s, width: widths[i] * s, height: 44 * s)
        NSBezierPath(roundedRect: r, xRadius: 22 * s, yRadius: 22 * s).fill()
    }

    // aperture ring
    ctx.setLineWidth(46 * s)
    NSColor(calibratedRed: 0.26, green: 0.68, blue: 0.95, alpha: 1).setStroke()
    let ring = NSBezierPath(ovalIn: CGRect(x: 470 * s, y: 420 * s, width: 360 * s, height: 360 * s))
    ring.lineWidth = 46 * s
    ring.stroke()
    NSColor(calibratedWhite: 1, alpha: 0.95).setStroke()
    let handle = NSBezierPath()
    handle.move(to: CGPoint(x: 520 * s, y: 420 * s))
    handle.line(to: CGPoint(x: 380 * s, y: 270 * s))
    handle.lineWidth = 52 * s
    handle.lineCapStyle = .round
    handle.stroke()
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let img = render(size: 1024)
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
