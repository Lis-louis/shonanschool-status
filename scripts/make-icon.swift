// アプリアイコン（AppIcon.icns）を作る。鈴の顔＋水色の地＋角帽のバッジ。
// 使い方: swift scripts/make-icon.swift <顔の画像> <出力先.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let face = NSImage(contentsOfFile: args[1]) else {
    print("usage: make-icon.swift <face.jpg> <out.png>"); exit(1)
}
func hex(_ s: String) -> NSColor {
    let v = UInt32(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// 角丸の四角（macOS のアイコン枠: 824pt・余白100）
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 18; shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
hex("#8FA8F0").setFill(); path.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
path.addClip()
NSGradient(colors: [hex("#F6F8FF"), hex("#C9D6FA"), hex("#8FA8F0")])!.draw(in: body, angle: -90)
// ふわっとした光の玉
hex("#F6B9C9").withAlphaComponent(0.35).setFill()
NSBezierPath(ovalIn: NSRect(x: 80, y: 80, width: 420, height: 420)).fill()
NSColor.white.withAlphaComponent(0.45).setFill()
NSBezierPath(ovalIn: NSRect(x: 560, y: 620, width: 360, height: 360)).fill()

// 鈴の顔（丸）
let faceRect = NSRect(x: 222, y: 230, width: 580, height: 580)
hex("#FFFFFF").setFill()
NSBezierPath(ovalIn: faceRect.insetBy(dx: -22, dy: -22)).fill()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(ovalIn: faceRect).addClip()
let side = min(face.size.width, face.size.height) / 1.2
let src = NSRect(x: (face.size.width - side) / 2, y: (face.size.height - side) / 2 + (min(face.size.width, face.size.height) - side) * 0.15,
                 width: side, height: side)
face.draw(in: faceRect, from: src, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
let ring = NSBezierPath(ovalIn: faceRect.insetBy(dx: -22, dy: -22)); ring.lineWidth = 10
hex("#5B7FE0").withAlphaComponent(0.55).setStroke(); ring.stroke()

// 角帽のバッジ（右下）
let badge = NSRect(x: 640, y: 150, width: 230, height: 230)
NSGraphicsContext.saveGraphicsState()
let bs = NSShadow(); bs.shadowColor = hex("#2B3A6E").withAlphaComponent(0.3); bs.shadowBlurRadius = 14; bs.shadowOffset = NSSize(width: 0, height: -6); bs.set()
NSGradient(colors: [hex("#8FA8F0"), hex("#5B7FE0")])!.draw(in: NSBezierPath(ovalIn: badge), angle: -45)
NSGraphicsContext.restoreGraphicsState()
let ob = NSBezierPath(ovalIn: badge.insetBy(dx: -8, dy: -8)); ob.lineWidth = 16; NSColor.white.setStroke(); ob.stroke()
if let sym = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 120, weight: .semibold).applying(.init(paletteColors: [.white]))) {
    let s = sym.size
    sym.draw(in: NSRect(x: badge.midX - s.width / 2, y: badge.midY - s.height / 2, width: s.width, height: s.height))
}
NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
