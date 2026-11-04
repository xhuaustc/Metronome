import AppKit
import ImageIO
import UniformTypeIdentifiers

// Compose store artwork with the unmodified, real application screenshot.
// Usage: swift store/scripts/design-first-screenshot.swift <source.png> <output.png>
let args = CommandLine.arguments
precondition(args.count == 3, "Expected source and output PNG paths")
let source = NSImage(contentsOfFile: args[1])!
let width = Int(source.size.width), height = Int(source.size.height)
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
let context = NSGraphicsContext.current!.cgContext
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: CGFloat(width) / 1320, y: -CGFloat(width) / 1320)
let h = CGFloat(height) * 1320 / CGFloat(width)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
let blue = color(83, 185, 255), white = color(242, 247, 250)
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(19, 36, 49).cgColor, color(8, 14, 21).cgColor] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1320, y: h), options: [])
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ ink: NSColor, _ weight: NSFont.Weight = .regular) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
    let line = NSAttributedString(string: value, attributes: attrs)
    let bounds = line.size()
    context.saveGState()
    context.translateBy(x: x, y: y + bounds.height)
    context.scaleBy(x: 1, y: -1)
    line.draw(at: .zero)
    context.restoreGState()
}
text("知拍节拍器", 110, 108, 47, white, .semibold)
text("钢琴练习 · 节奏训练", 110, 180, 32, color(150, 174, 190))
text("打开就练", 102, 285, 136, white, .bold)
text("稳稳跟上每一拍", 106, 461, 103, blue, .bold)
let labels = [("离线使用", CGFloat(110)), ("按小节提速", CGFloat(444)), ("机械摆针", CGFloat(824))]
for (label, x) in labels {
    blue.setFill()
    NSBezierPath(ovalIn: CGRect(x: x, y: 665, width: 10, height: 10)).fill()
    text(label, x + 26, 642, 38, color(190, 208, 220), .medium)
}
let phoneWidth: CGFloat = 894
let phoneHeight = phoneWidth * CGFloat(height) / CGFloat(width)
let phone = CGRect(x: (1320 - phoneWidth) / 2, y: 798, width: phoneWidth, height: phoneHeight)
let frame = phone.insetBy(dx: -13, dy: -13)
context.setShadow(offset: CGSize(width: 0, height: 18), blur: 58, color: NSColor.black.withAlphaComponent(0.6).cgColor)
color(67, 84, 96).setFill()
NSBezierPath(roundedRect: frame, xRadius: 74, yRadius: 74).fill()
context.setShadow(offset: .zero, blur: 0)
context.saveGState()
NSBezierPath(roundedRect: phone, xRadius: 62, yRadius: 62).addClip()
var rect = CGRect(origin: .zero, size: source.size)
let cgImage = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
context.translateBy(x: phone.minX, y: phone.maxY)
context.scaleBy(x: 1, y: -1)
context.interpolationQuality = .high
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: phone.width, height: phone.height))
context.restoreGState()
NSGraphicsContext.restoreGraphicsState()
let opaque = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(canvas.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
    UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "PNG export failed")
print("Exported \(width)×\(height) RGB: \(args[2])")
