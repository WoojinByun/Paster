// SVG 를 정사각 PNG 로 렌더링한다. scripts/make-icon.sh 가 호출한다.
// 사용법: swift scripts/render-icon.swift <input.svg> <output-dir> <size> [<size> ...]
// 결과: <output-dir>/<size>.png
import AppKit

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write("usage: render-icon.swift <input.svg> <output-dir> <size>...\n".data(using: .utf8)!)
    exit(2)
}
let svgURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
guard let image = NSImage(contentsOf: svgURL) else {
    FileHandle.standardError.write("failed to load \(svgURL.path)\n".data(using: .utf8)!)
    exit(1)
}

for sizeArg in args[3...] {
    guard let size = Int(sizeArg), size > 0 else {
        FileHandle.standardError.write("bad size: \(sizeArg)\n".data(using: .utf8)!)
        exit(2)
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .sourceOver, fraction: 1.0)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: outDir.appendingPathComponent("\(size).png"))
}
