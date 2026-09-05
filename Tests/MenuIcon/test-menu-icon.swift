import CoreGraphics
import Foundation

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("menu icon check failed: \(message)\n".utf8))
    exit(EXIT_FAILURE)
}

guard CommandLine.arguments.count == 2 else {
    fail("usage: test-menu-icon.swift icon.pdf")
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let document = CGPDFDocument(url as CFURL),
      let page = document.page(at: 1) else {
    fail("unable to open PDF")
}

let size = 240
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("unable to create bitmap")
}

let target = CGRect(x: 0, y: 0, width: size, height: size)
context.clear(target)
// Explicitly magnify the native 16 pt artwork to measure sub-point padding.
context.scaleBy(x: CGFloat(size) / 16, y: CGFloat(size) / 16)
context.drawPDFPage(page)
guard let data = context.data else { fail("bitmap has no pixel storage") }
let pixels = data.assumingMemoryBound(to: UInt8.self)

let mediaBox = page.getBoxRect(.mediaBox)
guard mediaBox.width == 16, mediaBox.height == 16 else {
    fail("expected a native 16 × 16 pt template canvas")
}

var minY = size
var maxY = -1
var minX = size
var maxX = -1
for y in 0..<size {
    for x in 0..<size where pixels[(y * size + x) * 4 + 3] > 16 {
        minY = min(minY, y)
        maxY = max(maxY, y)
        minX = min(minX, x)
        maxX = max(maxX, x)
    }
}

guard maxY >= minY else { fail("rendered mark is blank") }
let centerY = Double(minY + maxY) / 2
let canvasCenter = Double(size - 1) / 2
// Bitmap rows run top to bottom, opposite PDF coordinates.
if abs(centerY - canvasCenter) > 1 {
    fail("badge must be centered on the native canvas: got \(centerY)")
}
if abs(Double(minX + maxX) / 2 - canvasCenter) > 1 {
    fail("badge is not horizontally centered")
}
if minY < 6 || maxY >= size - 6 {
    fail("rendered mark is clipped or lacks vertical padding: y=\(minY)...\(maxY)")
}
func alpha(x: Double, y: Double) -> UInt8 {
    // Samples use the original path coordinates (scaled 2/3, shifted -1 y).
    pixels[((size - 1 - Int((y - 1) * 10)) * size + Int(x * 10)) * 4 + 3]
}
for point in [(5.0, 13.0), (12.0, 21.0), (12.0, 15.0)] {
    guard alpha(x: point.0, y: point.1) > 250 else {
        fail("badge body or R counter is not opaque at \(point)")
    }
}
for point in [(8.5, 13.0), (15.5, 8.0), (0.5, 12.0)] {
    guard alpha(x: point.0, y: point.1) < 5 else {
        fail("R cutout or outer margin is not transparent at \(point)")
    }
}
print("menu icon solid badge, R cutout and alignment passed: bbox y=\(minY)...\(maxY)")
