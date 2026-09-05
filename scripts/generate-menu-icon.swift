import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("usage: generate-menu-icon.swift output.pdf")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
var page = CGRect(x: 0, y: 0, width: 16, height: 16)
guard let context = CGContext(outputURL as CFURL, mediaBox: &page, nil) else {
    fatalError("unable to create menu icon PDF")
}

context.beginPDFPage(nil)
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.setFillColor(CGColor(gray: 0, alpha: 1))

// A solid badge with a transparent R, not a white-painted letter. AppKit tints
// the template's opaque pixels white on dark menu bars and black on light ones.
// InputMethodKit expects a native 16 pt menu image. An oversized 24 pt image
// was drawn low in the real menu even though its PDF artwork was centered.
// Keep the original path coordinates, but center them on a 16 pt canvas.
context.scaleBy(x: 2.0 / 3.0, y: 2.0 / 3.0)
context.translateBy(x: 0, y: -1)
let badge = CGPath(
    roundedRect: CGRect(x: 2, y: 3, width: 20, height: 20),
    cornerWidth: 4,
    cornerHeight: 4,
    transform: nil
)
context.addPath(badge)

// R silhouette (cut out using even-odd fill).
context.move(to: CGPoint(x: 7, y: 7))
context.addLine(to: CGPoint(x: 7, y: 19))
context.addLine(to: CGPoint(x: 12.5, y: 19))
context.addCurve(
    to: CGPoint(x: 17, y: 15.2),
    control1: CGPoint(x: 15.5, y: 19),
    control2: CGPoint(x: 17, y: 17.6)
)
context.addCurve(
    to: CGPoint(x: 14.3, y: 11.7),
    control1: CGPoint(x: 17, y: 13.5),
    control2: CGPoint(x: 16, y: 12.2)
)
context.addLine(to: CGPoint(x: 18, y: 7))
context.addLine(to: CGPoint(x: 14.4, y: 7))
context.addLine(to: CGPoint(x: 11.2, y: 11.3))
context.addLine(to: CGPoint(x: 10, y: 11.3))
context.addLine(to: CGPoint(x: 10, y: 7))
context.closePath()

// The bowl's counter is an opaque island inside the transparent letter.
context.move(to: CGPoint(x: 10, y: 16.5))
context.addLine(to: CGPoint(x: 12.4, y: 16.5))
context.addCurve(
    to: CGPoint(x: 12.4, y: 13.8),
    control1: CGPoint(x: 14.6, y: 16.5),
    control2: CGPoint(x: 14.6, y: 13.8)
)
context.addLine(to: CGPoint(x: 10, y: 13.8))
context.closePath()
context.drawPath(using: .eoFill)
context.endPDFPage()
context.closePDF()
