import Foundation

/// A rounded-rectangle alpha mask shared by the desktop drawing backends.
/// Three separable box filters approximate a Gaussian without drawing nested
/// translucent outlines. Radius is the Gaussian standard deviation, in points.
public struct ShadowMask {
  public let width: Int
  public let height: Int
  public let scale: Double
  public let inset: Double
  public let alpha: [UInt8]

  public static func padding(radius: Double) -> Double {
    radius.isFinite ? ceil(max(0, radius) * 3) + 2 : 0
  }

  public init?(
    width: Double, height: Double, cornerRadius: Double,
    radius: Double, scale: Double = 1
  ) {
    guard width.isFinite, height.isFinite, !cornerRadius.isNaN,
      radius.isFinite, scale.isFinite, width > 0, height > 0, scale > 0
    else { return nil }
    let padding = Self.padding(radius: radius)
    let paddedWidth = width + padding * 2
    let paddedHeight = height + padding * 2
    guard paddedWidth.isFinite, paddedHeight.isFinite else { return nil }
    // Bound temporary storage for oversized views; Gaussian shadows are
    // low-frequency so capping resolution on large blurs preserves smoothness
    // while avoiding multi-million-pixel CPU blurs.
    let maxDim = max(paddedWidth, paddedHeight)
    let targetLimit = radius >= 4 && maxDim > 160 ? 512.0 : 2048.0
    let scale = min(scale, targetLimit / maxDim)
    let w = Int(ceil(paddedWidth * scale))
    let h = Int(ceil(paddedHeight * scale))
    guard w > 0, h > 0 else { return nil }
    self.width = w
    self.height = h
    self.scale = scale
    self.inset = padding
    let left = padding * scale
    let top = padding * scale
    let right = left + width * scale
    let bottom = top + height * scale
    let corner = max(0, min(cornerRadius, min(width, height) / 2)) * scale
    var pixels = [Float](repeating: 0, count: w * h)
    // Integrate coverage along each scanline; fill interior spans directly.
    pixels.withUnsafeMutableBufferPointer { buf in
      guard let base = buf.baseAddress else { return }
      let yStart = max(0, Int(floor(top)))
      let yEnd = min(h, Int(ceil(bottom)))
      guard yStart < yEnd else { return }
      let flatTop = top + corner
      let flatBottom = bottom - corner
      let interiorX0 = max(0, Int(ceil(left)))
      let interiorX1 = min(w, Int(floor(right)))
      for y in yStart..<yEnd {
        let row = base + y * w
        let yd = Double(y)
        if yd >= flatTop && yd + 1 <= flatBottom && interiorX0 < interiorX1 {
          for x in interiorX0..<interiorX1 { row[x] = 1.0 }
          let lx = interiorX0 - 1
          if lx >= 0 && lx < w {
            row[lx] = Float(max(0, min(Double(lx + 1), right) - max(Double(lx), left)))
          }
          if interiorX1 >= 0 && interiorX1 < w {
            row[interiorX1] = Float(
              max(0, min(Double(interiorX1 + 1), right) - max(Double(interiorX1), left)))
          }
          continue
        }
        for sample in 0..<4 {
          let py = yd + (Double(sample) + 0.5) * 0.25
          guard py > top, py < bottom else { continue }
          let dy = max(0, flatTop - py, py - flatBottom)
          let cut = corner - sqrt(max(0, corner * corner - dy * dy))
          let start = left + cut
          let end = right - cut
          let x0 = max(0, Int(floor(start)))
          let x1 = min(w, Int(ceil(end)))
          if x0 >= x1 { continue }
          let full0 = min(x1, max(x0, Int(ceil(start))))
          let full1 = max(full0, min(x1, Int(floor(end))))
          if x0 < full0 {
            row[x0] += Float(max(0, min(Double(x0 + 1), end) - max(Double(x0), start))) * 0.25
          }
          if full0 < full1 {
            for x in full0..<full1 { row[x] += 0.25 }
          }
          if full1 < x1 {
            row[full1] += Float(max(0, min(Double(full1 + 1), end) - max(Double(full1), start))) * 0.25
          }
        }
      }
    }
    let sigma = max(0, radius) * scale
    if sigma > 0 {
      // Choose adjacent odd box widths whose combined variance is sigma².
      let ideal = sqrt(4 * sigma * sigma + 1)
      var lower = Int(floor(ideal))
      if lower % 2 == 0 { lower -= 1 }
      lower = max(1, lower)
      let upper = lower + 2
      let count = Int(
        round(
          (12 * sigma * sigma - 3 * Double(lower * lower)
            - 12 * Double(lower) - 9) / (-4 * Double(lower) - 4)))
      var scratch = [Float](repeating: 0, count: pixels.count)
      for pass in 0..<3 {
        let boxRadius = ((pass < count ? lower : upper) - 1) / 2
        guard boxRadius > 0 else { continue }
        Self.blur(pixels, into: &scratch, width: w, height: h, radius: boxRadius, horizontal: true)
        Self.blur(scratch, into: &pixels, width: w, height: h, radius: boxRadius, horizontal: false)
      }
    }
    var out = [UInt8](repeating: 0, count: pixels.count)
    pixels.withUnsafeBufferPointer { src in
      out.withUnsafeMutableBufferPointer { dst in
        guard let sp = src.baseAddress, let dp = dst.baseAddress else { return }
        for i in 0..<src.count {
          let v = sp[i]
          dp[i] = v <= 0 ? 0 : (v >= 1 ? 255 : UInt8(v * 255 + 0.5))
        }
      }
    }
    self.alpha = out
  }

  private static func blur(
    _ input: [Float], into output: inout [Float],
    width: Int, height: Int, radius: Int, horizontal: Bool
  ) {
    let length = horizontal ? width : height
    let lines = horizontal ? height : width
    let stride = horizontal ? 1 : width
    let invDivisor: Float = 1.0 / Float(radius * 2 + 1)
    input.withUnsafeBufferPointer { src in
      output.withUnsafeMutableBufferPointer { dst in
        guard let sp = src.baseAddress, let dp = dst.baseAddress else { return }
        let initialEnd = min(length, radius + 1)
        for line in 0..<lines {
          let base = horizontal ? line * width : line
          var sum: Float = 0
          for i in 0..<initialEnd { sum += sp[base + i * stride] }
          for i in 0..<length {
            dp[base + i * stride] = sum * invDivisor
            if i >= radius { sum -= sp[base + (i - radius) * stride] }
            if i + radius + 1 < length { sum += sp[base + (i + radius + 1) * stride] }
          }
        }
      }
    }
  }
}
