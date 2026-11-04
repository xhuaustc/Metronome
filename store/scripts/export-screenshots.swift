import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 保留原生像素尺寸，去掉模拟器截图的 alpha 通道，供 App Store 上传。
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
for file in files {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let context = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("无法处理截图：\(file.lastPathComponent)") }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "截图导出失败")
    print("\(file.lastPathComponent): \(image.width)×\(image.height), RGB")
}
