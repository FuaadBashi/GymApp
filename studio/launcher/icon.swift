import AppKit
func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024, inset = 100 * s
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset), xRadius: 185 * s, yRadius: 185 * s)
    NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill(); bg.fill()
    let volt = NSColor(red: 0.78, green: 0.95, blue: 0.26, alpha: 1); volt.setFill()
    NSBezierPath(roundedRect: NSRect(x: 250 * s, y: 492 * s, width: 524 * s, height: 40 * s), xRadius: 20 * s, yRadius: 20 * s).fill()
    for x in [250, 330, 634, 714] as [CGFloat] {
        let h: CGFloat = (x == 250 || x == 714) ? 220 : 320
        NSBezierPath(roundedRect: NSRect(x: x * s, y: (512 - h / 2) * s, width: 60 * s, height: h * s), xRadius: 22 * s, yRadius: 22 * s).fill()
    }
    // a rising line under the bar: the studio is about progress
    let line = NSBezierPath(); line.lineWidth = 34 * s; line.lineCapStyle = .round; line.lineJoinStyle = .round
    line.move(to: NSPoint(x: 260 * s, y: 270 * s)); line.line(to: NSPoint(x: 430 * s, y: 330 * s)); line.line(to: NSPoint(x: 560 * s, y: 290 * s)); line.line(to: NSPoint(x: 770 * s, y: 390 * s))
    volt.withAlphaComponent(0.55).setStroke(); line.stroke()
    NSGraphicsContext.restoreGraphicsState(); return rep
}
let dir = CommandLine.arguments[1]
for (n, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(CGFloat(px)).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/icon_\(n).png"))
}
