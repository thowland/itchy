#!/usr/bin/env swift
import AppKit

// Renders the cat.fill SF Symbol into an AppIcon asset catalogue.
//
// The icon is generated rather than drawn so that it has one definition, the
// same way project.yml owns the project and the Info.plist (D-12). Re-run with
// `make icon` after changing the symbol or the palette.

let symbolName = "cat.fill"
let output = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : "App/Assets.xcassets/AppIcon.appiconset"

// macOS icons sit on a rounded-rectangle plate with a generous margin, which is
// what makes a generated icon look deliberate rather than stretched.
let plateInset: CGFloat = 0.10
/// Fraction of the plate the symbol may occupy, preserving its aspect ratio.
let symbolFill: CGFloat = 0.62

func render(size: Int) -> Data? {
  let dimension = CGFloat(size)

  // Drawn into a bitmap rep directly rather than through `lockFocus`, which
  // fails to produce a TIFF at the smaller icon sizes.
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size, pixelsHigh: size,
      bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0)
  else { return nil }
  bitmap.size = NSSize(width: dimension, height: dimension)

  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context

  let inset = dimension * plateInset
  let plate = NSRect(
    x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
  let radius = plate.width * 0.2237

  let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.29, green: 0.33, blue: 0.41, alpha: 1),
    ending: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.24, alpha: 1))
  gradient?.draw(in: NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius), angle: -90)

  if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Itchy") {
    let configuration = NSImage.SymbolConfiguration(
      pointSize: dimension, weight: .regular
    ).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let configured = symbol.withSymbolConfiguration(configuration) ?? symbol

    // Scale to fit inside the plate rather than to a fixed point size: cat.fill
    // is wider than it is tall, so a point size chosen for height overflows the
    // plate horizontally.
    let available = plate.width * symbolFill
    let natural = configured.size
    let scale = min(available / natural.width, available / natural.height)
    let drawn = NSSize(width: natural.width * scale, height: natural.height * scale)
    let target = NSRect(
      x: (plate.midX - drawn.width / 2).rounded(),
      y: (plate.midY - drawn.height / 2).rounded(),
      width: drawn.width.rounded(),
      height: drawn.height.rounded())
    configured.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1.0)
  }

  NSGraphicsContext.restoreGraphicsState()
  return bitmap.representation(using: .png, properties: [:])
}

struct Entry {
  let idiom = "mac"
  let size: Int
  let scale: Int
  var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
  var pixels: Int { size * scale }
}

let entries = [16, 32, 128, 256, 512].flatMap { [Entry(size: $0, scale: 1), Entry(size: $0, scale: 2)] }

try? FileManager.default.createDirectory(
  atPath: output, withIntermediateDirectories: true)

var images: [String] = []
for entry in entries {
  guard let data = render(size: entry.pixels) else {
    FileHandle.standardError.write(Data("failed to render \(entry.filename)\n".utf8))
    exit(1)
  }
  try? data.write(to: URL(fileURLWithPath: "\(output)/\(entry.filename)"))
  images.append("""
        {
          "filename" : "\(entry.filename)",
          "idiom" : "mac",
          "scale" : "\(entry.scale)x",
          "size" : "\(entry.size)x\(entry.size)"
        }
    """)
}

let contents = """
  {
    "images" : [
  \(images.joined(separator: ",\n"))
    ],
    "info" : {
      "author" : "xcode",
      "version" : 1
    }
  }

  """
try? contents.write(toFile: "\(output)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(entries.count) images to \(output)")
