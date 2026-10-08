import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original Presentation-Viewer artwork. Opaque RGB square, with antialiased vector shapes.
let output = CommandLine.arguments[1]
let size = 1024
let ctx = CGContext(data:nil, width:size, height:size, bitsPerComponent:8, bytesPerRow:0,
    space:CGColorSpace(name:CGColorSpace.sRGB)!, bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx, flipped:false)
ctx.setShouldAntialias(true)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: NSRect(x:x,y:y,width:w,height:h), xRadius:radius,yRadius:radius).fill()
}
func line(_ points: [CGPoint], _ width: CGFloat, _ fill: NSColor) {
    ctx.setStrokeColor(fill.cgColor); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.beginPath(); ctx.move(to:points[0]); for point in points.dropFirst() { ctx.addLine(to:point) }; ctx.strokePath()
}
// A presentation slide and a rising chart; deliberately different from a photo frame.
rect(0,0,1024,1024,0,color(61,64,148))
let gradient = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),
    colors:[color(84,105,190).cgColor,color(54,45,117).cgColor] as CFArray, locations:[0,1])!
ctx.drawLinearGradient(gradient,start:CGPoint(x:130,y:1024),end:CGPoint(x:850,y:0),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
line([CGPoint(x:512,y:294),CGPoint(x:512,y:192)],28,color(231,234,255))
line([CGPoint(x:426,y:182),CGPoint(x:598,y:182)],28,color(231,234,255))
rect(170,300,684,484,52,color(248,249,255))
rect(150,759,724,40,20,color(197,209,255))
rect(225,677,215,28,14,color(74,80,150))
rect(225,620,140,17,8,color(176,188,223))
rect(225,582,174,17,8,color(176,188,223))
rect(225,544,119,17,8,color(176,188,223))
rect(471,393,72,106,13,color(169,185,241))
rect(575,393,72,176,13,color(112,139,223))
rect(679,393,72,256,13,color(230,152,107))
line([CGPoint(x:456,y:371),CGPoint(x:773,y:371)],14,color(207,213,234))
NSGraphicsContext.restoreGraphicsState()
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath:output) as CFURL,
    UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
