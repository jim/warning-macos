import AppKit
import NIO

let socketPath = "/tmp/warning"

class WarningView: NSView {
    var borderWidth = CGFloat(10.0)
    var borderColor = NSColor.red
    
    override func viewWillDraw() {
        self.window?.level = .floating
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let path = NSBezierPath()
        let rect = NSMakeRect(0.0, 0.0, CGFloat(self.frame.size.width), CGFloat(self.frame.size.height));
        path.appendRect(rect)
        path.close()
        self.borderColor.setStroke()
        path.lineWidth = self.borderWidth
        path.stroke()
    }
}

let app = NSApplication.shared
let rect = NSScreen.main!.visibleFrame
var warningView: WarningView!

class AppDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: rect,
                          styleMask: [.borderless],//.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false,
        screen: nil)
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        window.ignoresMouseEvents = true
        window.alphaValue = 1.0
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        
        warningView = WarningView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(warningView)
    }
}

enum Command {
    case color (NSColor)
    case width (CGFloat)
}

let delegate = AppDelegate()
app.delegate = delegate

func hexColor(hex: String) -> NSColor? {
    var hexToScan = hex
    
    if hexToScan.count == 6 {
        hexToScan.append("ff")
    }
    
    if hexToScan.count == 8 {
        
        let scanner = Scanner(string: hexToScan)
        var hexNumber: UInt64 = 0
        
        if scanner.scanHexInt64(&hexNumber) {
            let r = CGFloat((hexNumber & 0xff000000) >> 24) / 255
            let g = CGFloat((hexNumber & 0x00ff0000) >> 16) / 255
            let b = CGFloat((hexNumber & 0x0000ff00) >> 8) / 255
            let a = CGFloat((hexNumber & 0x000000ff) >> 0) / 255
            
            return NSColor.init(red: r, green: g, blue: b, alpha: a)
        }
    }
    
    return nil
}

func parseCommand(text: String) -> Command? {
    let parts = text.split(separator: " ")
    
    let range = NSRange(location: 0, length: text.utf16.count)
    let regex = try! NSRegularExpression(pattern: "(\\w+)\\s+([a-f0-9]+)")
    let match = regex.firstMatch(in: text, options: [], range: range)
    
    if match != nil {
        switch parts[0] {
        case "color":
            let color = hexColor(hex: String(parts[1]))
            if color != nil {
                return Command.color(color!)
            }
            
        case "width":
            let float = Float(parts[1])
            if float != nil {
                return Command.width(CGFloat(float!))
            }
        default:
            print(text)
        }
    }
    return nil
}

private final class EchoHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var byteBuffer = self.unwrapInboundIn(data)
        
        if byteBuffer.readableBytes == 0 {
            print("nothing")
        } else {
            let string = byteBuffer.readString(length: byteBuffer.readableBytes)!
            let stripped = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            //            print("RECV '\(stripped)'")
            let command = parseCommand(text: stripped)
            if command != nil {
                switch command! {
                case .color(let color):
                    DispatchQueue.main.async {
                        warningView.borderColor = color
                        warningView.needsDisplay = true
                    }
                case .width(let width):
                    DispatchQueue.main.async {
                        warningView.borderWidth = width
                        warningView.needsDisplay = true
                    }
                }
            }
        }
        context.close(promise: nil)
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    public func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: ", error)
        context.close(promise: nil)
    }
}
let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let bootstrap = ServerBootstrap(group: group)
    // Specify backlog and enable SO_REUSEADDR for the server itself
    .serverChannelOption(ChannelOptions.backlog, value: 256)
    .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    
    // Set the handlers that are appled to the accepted Channels
    .childChannelInitializer { channel in
        // Ensure we don't read faster than we can write by adding the BackPressureHandler into the pipeline.
        channel.pipeline.addHandler(BackPressureHandler()).flatMap { v in
            channel.pipeline.addHandler(EchoHandler())
        }
    }
    
    // Enable SO_REUSEADDR for the accepted Channels
    .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

func shutdown() {
    try! group.syncShutdownGracefully()
    try! FileManager.default.removeItem(atPath: socketPath )
    print("Server closed")
    app.terminate(app)
}

signal(SIGINT) { s in
    shutdown()
}

// TODO if the socker file already exists, determine if there is another instance running before removing it
try! FileManager.default.removeItem(atPath: socketPath)
let channel = try bootstrap.bind(unixDomainSocketPath: socketPath).wait()

print("Server started and listening on \(channel.localAddress!)")

app.run()
try channel.closeFuture.wait()


