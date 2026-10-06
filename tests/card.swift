import AppKit
// Uso: card out.png "testo"  → scheda nera 640x360 con testo bianco grande (per provare l'OCR)
let a = CommandLine.arguments; let img = NSImage(size: NSSize(width: 640, height: 360))
img.lockFocus(); NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 640, height: 360).fill()
(a[2] as NSString).draw(at: NSPoint(x: 40, y: 150), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 44), .foregroundColor: NSColor.white])
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!; try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[1]))
