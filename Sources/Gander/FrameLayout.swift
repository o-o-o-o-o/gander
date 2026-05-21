import AppKit
import Foundation

// MARK: - Dimensions and anchors

enum FrameDimension: Equatable {
    case points(Double)
    case percent(Double)  // 0–100 of visible width/height

    func resolve(against total: CGFloat) -> CGFloat {
        switch self {
        case .points(let p): return CGFloat(p)
        case .percent(let pct): return total * CGFloat(pct) / 100
        }
    }

    static func parse(_ raw: String) -> FrameDimension? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s == "full" || s == "max" || s == "100%" { return .percent(100) }
        if s.hasSuffix("%") {
            let num = String(s.dropLast())
            guard let v = Double(num) else { return nil }
            return .percent(v)
        }
        guard let v = Double(s) else { return nil }
        return .points(v)
    }
}

enum FrameAxis: Equatable {
    case points(Double)
    case percent(Double)   // from minX / minY
    case right
    case left
    case bottom
    case top

    func resolveX(width: CGFloat, visible: CGRect) -> CGFloat {
        switch self {
        case .points(let p): return CGFloat(p)
        case .percent(let pct): return visible.minX + visible.width * CGFloat(pct) / 100
        case .right: return visible.maxX - width
        case .left: return visible.minX
        case .bottom, .top: return visible.minX
        }
    }

    func resolveY(height: CGFloat, visible: CGRect) -> CGFloat {
        switch self {
        case .points(let p): return CGFloat(p)
        case .percent(let pct): return visible.minY + visible.height * CGFloat(pct) / 100
        case .bottom: return visible.minY
        case .top: return visible.maxY - height
        case .left, .right: return visible.minY
        }
    }

    static func parse(_ raw: String) -> FrameAxis? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch s {
        case "right": return .right
        case "left": return .left
        case "bottom": return .bottom
        case "top": return .top
        default: break
        }
        if s.hasSuffix("%") {
            let num = String(s.dropLast())
            guard let v = Double(num) else { return nil }
            return .percent(v)
        }
        guard let v = Double(s) else { return nil }
        return .points(v)
    }
}

// MARK: - Presets and auto rules

struct FramePreset: Codable, Equatable {
    var width: FrameDimension?
    var height: FrameDimension?
    var x: FrameAxis?
    var y: FrameAxis?

    enum CodingKeys: String, CodingKey { case width, height, x, y }

    init(width: FrameDimension? = nil, height: FrameDimension? = nil,
         x: FrameAxis? = nil, y: FrameAxis? = nil) {
        self.width = width; self.height = height; self.x = x; self.y = y
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width  = try c.decodeIfPresent(FrameDimension.self, forKey: .width)
        height = try c.decodeIfPresent(FrameDimension.self, forKey: .height)
        x      = try c.decodeIfPresent(FrameAxis.self, forKey: .x)
        y      = try c.decodeIfPresent(FrameAxis.self, forKey: .y)
    }
}

struct FrameAutoMatch: Codable, Equatable {
    var screenCount: Int?
    var screenCountMin: Int?
    var frame: String

    enum CodingKeys: String, CodingKey { case screenCount, screenCountMin, frame }

    init(screenCount: Int? = nil, screenCountMin: Int? = nil, frame: String) {
        self.screenCount = screenCount
        self.screenCountMin = screenCountMin
        self.frame = frame
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frame = try c.decode(String.self, forKey: .frame)
        screenCount = nil
        screenCountMin = nil
        if let n = try? c.decode(Int.self, forKey: .screenCount) {
            screenCount = n
        } else if let box = try? c.decode(ScreenCountMinBox.self, forKey: .screenCount) {
            screenCountMin = box.min
        }
        if screenCountMin == nil {
            screenCountMin = try? c.decode(Int.self, forKey: .screenCountMin)
        }
    }

    private struct ScreenCountMinBox: Codable { var min: Int }

    func matches(screenCount count: Int) -> Bool {
        if let exact = self.screenCount {
            return count == exact
        }
        if let min = screenCountMin {
            return count >= min
        }
        return true
    }
}

struct FrameAutoConfig: Codable, Equatable {
    var onLayoutChange: Bool?
    var match: [FrameAutoMatch]?

    init(onLayoutChange: Bool? = nil, match: [FrameAutoMatch]? = nil) {
        self.onLayoutChange = onLayoutChange
        self.match = match
    }

    func presetName(forScreenCount count: Int) -> String? {
        guard let rules = match else { return nil }
        for rule in rules where rule.matches(screenCount: count) {
            return rule.frame
        }
        return nil
    }
}

// MARK: - IPC / CLI partial frame

struct FrameConfig {
    var preset: String?
    var x: String?
    var y: String?
    var width: String?
    var height: String?

    var isEmpty: Bool {
        preset == nil && x == nil && y == nil && width == nil && height == nil
    }
}

// MARK: - Resolution

enum FrameResolver {
    static let minSide: CGFloat = 240

    static func computedRect(_ preset: FramePreset, visible: CGRect, fallbackWidth: CGFloat = 420) -> CGRect {
        let w = preset.width?.resolve(against: visible.width) ?? fallbackWidth
        let h = preset.height?.resolve(against: visible.height) ?? visible.height
        let x = preset.x?.resolveX(width: w, visible: visible) ?? (visible.maxX - w)
        let y = preset.y?.resolveY(height: h, visible: visible) ?? visible.minY
        return clamp(CGRect(x: x, y: y, width: w, height: h), to: visible)
    }

    static func computedRect(_ preset: FramePreset, on screen: NSScreen, fallbackWidth: CGFloat = 420) -> CGRect {
        computedRect(preset, visible: screen.visibleFrame, fallbackWidth: fallbackWidth)
    }

    static func clamp(_ rect: CGRect, to visible: CGRect) -> CGRect {
        var r = rect
        r.size.width = min(max(r.size.width, minSide), visible.width)
        r.size.height = min(max(r.size.height, minSide), visible.height)
        r.origin.x = min(max(r.origin.x, visible.minX), visible.maxX - r.size.width)
        r.origin.y = min(max(r.origin.y, visible.minY), visible.maxY - r.size.height)
        return r
    }

    static func applyPartial(_ partial: FrameConfig, to current: CGRect, visible: CGRect) -> CGRect {
        var r = current
        if let w = partial.width.flatMap(FrameDimension.parse) {
            r.size.width = w.resolve(against: visible.width)
        }
        if let h = partial.height.flatMap(FrameDimension.parse) {
            r.size.height = h.resolve(against: visible.height)
        }
        if let x = partial.x.flatMap(FrameAxis.parse) {
            r.origin.x = x.resolveX(width: r.size.width, visible: visible)
        }
        if let y = partial.y.flatMap(FrameAxis.parse) {
            r.origin.y = y.resolveY(height: r.size.height, visible: visible)
        }
        return clamp(r, to: visible)
    }
}

// MARK: - Codable for dimension / axis

extension FrameDimension: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Double.self) {
            self = .points(n)
            return
        }
        if let s = try? container.decode(String.self), let parsed = FrameDimension.parse(s) {
            self = parsed
            return
        }
        throw DecodingError.dataCorruptedError(in: container,
            debugDescription: "frame dimension must be a number or string like \"30%\" or \"full\"")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .points(let p): try container.encode(p)
        case .percent(let pct): try container.encode("\(pct.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(pct)) : String(pct))%")
        }
    }
}

extension FrameAxis: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let n = try? container.decode(Double.self) {
            self = .points(n)
            return
        }
        if let s = try? container.decode(String.self), let parsed = FrameAxis.parse(s) {
            self = parsed
            return
        }
        throw DecodingError.dataCorruptedError(in: container,
            debugDescription: "frame axis must be a number, \"right\", \"bottom\", or \"50%\"")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .points(let p): try container.encode(p)
        case .percent(let pct):
            try container.encode("\(pct.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(pct)) : String(pct))%")
        case .right: try container.encode("right")
        case .left: try container.encode("left")
        case .bottom: try container.encode("bottom")
        case .top: try container.encode("top")
        }
    }
}
