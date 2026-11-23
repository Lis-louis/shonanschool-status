// SVG のアイコンを 1024px の PNG にする。
// macOS 26 以降は、外側に透明な余白があるアイコンの後ろへ白い角丸の板を敷いてしまうため、
// 既定では「余白なし」（板をキャンバスいっぱいに広げ、角も背景色で埋める）で書き出す。角の丸めは macOS が行う。
// 使い方: swift scripts/svg-to-icon.swift <入力.svg> <出力.png> [--inset]
//   --inset … 従来どおり余白つき（824px の板）で書き出す
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let svg = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    print("SVGを読み込めませんでした"); exit(1)
}
let inset = args.contains("--inset")
// SVG 側の板は 32〜992（960px）
let plate: CGFloat = 960, plateOrigin: CGFloat = 32
let target: CGFloat = inset ? 824 : 1024
let scale = target / plate
let drawSize = 1024 * scale
let origin = (1024 - target) / 2 - plateOrigin * scale

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.set()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
if !inset {
    // 板の角の外側も、板と同じ水色のグラデーションで埋める（SVG の #bg と同じ色）
    func c(_ h: UInt32) -> NSColor { NSColor(srgbRed: CGFloat(h >> 16 & 0xFF) / 255, green: CGFloat(h >> 8 & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: 1) }
    NSGradient(colors: [c(0xE8F5FF), c(0xB8DCFF)])!.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), angle: -90)
}
svg.draw(in: NSRect(x: origin, y: origin, width: drawSize, height: drawSize), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("作成しました: \(args[2])")
