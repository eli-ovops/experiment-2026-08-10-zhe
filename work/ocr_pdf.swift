import Foundation
import PDFKit
import Vision
import AppKit

guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 5 else {
    fputs("Usage: ocr_pdf INPUT.pdf OUTPUT.txt [START_PAGE END_PAGE]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let document = PDFDocument(url: inputURL) else {
    fputs("Unable to open input PDF.\\n", stderr)
    exit(1)
}

let startPage = CommandLine.arguments.count == 5 ? (Int(CommandLine.arguments[3]) ?? 1) : 1
let endPage = CommandLine.arguments.count == 5 ? (Int(CommandLine.arguments[4]) ?? document.pageCount) : document.pageCount
let pageRange = max(1, startPage)...min(document.pageCount, endPage)

FileManager.default.createFile(atPath: outputURL.path, contents: nil)
let outputHandle = try FileHandle(forWritingTo: outputURL)
defer { try? outputHandle.close() }

for pageNumber in pageRange {
    autoreleasepool {
        let index = pageNumber - 1
        guard let page = document.page(at: index) else { return }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        guard let cgImage = context.makeImage() else { return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .right, options: [:])
        do {
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let pageOutput = "\n\n===== PDF page \(index + 1) =====\n" + lines.joined(separator: "\n") + "\n"
            try outputHandle.write(contentsOf: Data(pageOutput.utf8))
            fputs("OCR \(index + 1)/\(document.pageCount)\n", stderr)
        } catch {
            fputs("OCR failed on page \(index + 1): \(error)\n", stderr)
        }
    }
}
