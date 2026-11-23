import AppKit
import SwiftUI

// 鈴（suzu_ai/Sources/SuzuApp/Theme.swift）と同じ配色・部品。昼＝白と水色、夜＝紺と光る青。

struct Palette: Equatable, Sendable {
    var background: Color, card: Color, tint: Color, accent: Color, accent2: Color, ink: Color, subtle: Color, blush: Color, line: Color

    static let day = Palette(hex: ["background": "#F6F8FF", "card": "#FFFFFF", "tint": "#E8EEFF", "accent": "#5B7FE0", "accent2": "#8FA8F0",
                                   "ink": "#2B3A6E", "subtle": "#7A86B0", "blush": "#F6B9C9", "line": "#DCE4FA"])
    static let night = Palette(hex: ["background": "#0F1530", "card": "#18204A", "tint": "#222C5C", "accent": "#8FB0FF", "accent2": "#6C86E8",
                                     "ink": "#EAF0FF", "subtle": "#9AA6D6", "blush": "#F2A7BE", "line": "#2C3770"])

    /// 締切・休講など「目立たせる」色
    var alert: Color { Color(hex: "#E5607E")! }
    var warn: Color { Color(hex: "#F0A050")! }
    /// カレンダーの「予定」（授業の水色と見分けるため）
    var mint: Color { Color(hex: "#5FC9B0")! }

    init(hex: [String: String]) {
        func c(_ k: String) -> Color { hex[k].flatMap(Color.init(hex:)) ?? .accentColor }
        background = c("background"); card = c("card"); tint = c("tint"); accent = c("accent"); accent2 = c("accent2")
        ink = c("ink"); subtle = c("subtle"); blush = c("blush"); line = c("line")
    }
}

extension Color {
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.day }
extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// 鈴の絵（Resources/Appearance）
@MainActor
enum Artwork {
    private static var cache: [String: NSImage] = [:]
    private static let bundle: Bundle = {
        let name = "CampusHub_CampusHub.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let b = base.flatMap({ Bundle(url: $0.appendingPathComponent(name)) }) { return b }
        }
        return Bundle.module
    }()

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let img = bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Appearance").flatMap(NSImage.init(contentsOf:))
        cache[name] = img
        return img
    }
}

// MARK: - 部品

/// 角の丸い札（白い面・薄い縁・やわらかい影）
struct Card<Content: View>: View {
    @Environment(\.palette) private var p
    var title: String?
    var symbol: String?
    var tint: Color?
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 6) {
                    if let symbol { Image(systemName: symbol).foregroundStyle(tint ?? p.accent) }
                    Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(tint ?? p.ink)
                    Spacer()
                    if let trailing { Text(trailing).font(.system(.caption, design: .rounded)).foregroundStyle(p.subtle) }
                    Image(systemName: "sparkle").font(.caption2).foregroundStyle(p.accent2.opacity(0.6))
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke((tint ?? p.line).opacity(tint == nil ? 1 : 0.45), lineWidth: 1))
        .shadow(color: p.accent.opacity(0.08), radius: 14, y: 6)
    }
}

/// 小さな丸い札
struct Chip: View {
    @Environment(\.palette) private var p
    var text: String
    var symbol: String?
    var color: Color?
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(color ?? p.accent)
        .background((color ?? p.accent).opacity(0.13), in: Capsule())
        .fixedSize()
    }
}

/// 鈴の顔（丸い額にリボンの色の縁）
struct SuzuFace: View {
    @Environment(\.palette) private var p
    var image: NSImage?
    var size: CGFloat
    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                p.tint
                Text("鈴").font(.system(size: size * 0.4, weight: .semibold, design: .rounded)).foregroundStyle(p.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(LinearGradient(colors: [p.accent2, p.accent, p.blush.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                 lineWidth: max(2, size * 0.04)))
        .shadow(color: p.accent.opacity(0.25), radius: size * 0.08, y: size * 0.03)
    }
}

/// やわらかい横の棒
struct SoftBar: View {
    @Environment(\.palette) private var p
    var value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.tint)
                Capsule().fill(LinearGradient(colors: [p.accent2.opacity(0.7), p.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * min(1, max(0, value))))
            }
        }.frame(height: 6)
    }
}

/// ふわっとした背景（淡い色の玉）
struct DreamyBackground: View {
    @Environment(\.palette) private var p
    var body: some View {
        ZStack {
            p.background
            Circle().fill(p.accent2.opacity(0.18)).frame(width: 420).blur(radius: 90).offset(x: 320, y: -260)
            Circle().fill(p.blush.opacity(0.14)).frame(width: 360).blur(radius: 90).offset(x: -300, y: 280)
            Circle().fill(p.accent.opacity(0.10)).frame(width: 300).blur(radius: 80).offset(x: 60, y: 120)
        }.ignoresSafeArea()
    }
}

/// 見出し（花の印つき）
struct PageTitle: View {
    @Environment(\.palette) private var p
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "camera.macro").foregroundStyle(p.accent2)
                Text(title).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(p.ink)
            }
            if let subtitle { Text(subtitle).font(.system(.callout, design: .rounded)).foregroundStyle(p.subtle) }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(.white)
            .background(LinearGradient(colors: destructive ? [Color(hex: "#F09AB0")!, Color(hex: "#E07090")!] : [p.accent2, p.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    @Environment(\.palette) private var p
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded).weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .foregroundStyle(p.accent)
            .background(p.tint, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// 丸い入力欄の見た目
struct SoftFieldStyle: ViewModifier {
    @Environment(\.palette) private var p
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(p.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(p.line))
    }
}

extension View {
    func softField() -> some View { modifier(SoftFieldStyle()) }
}
