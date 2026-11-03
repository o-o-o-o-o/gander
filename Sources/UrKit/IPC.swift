import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Wire format: the client writes one JSON `Request` followed by "\n"; the server writes one JSON
// `Response` followed by "\n" and closes. One request per connection keeps both sides trivial.
//
// Why a Unix socket and not DistributedNotificationCenter (Gander's original transport):
// notifications are fire-and-forget, so the CLI could never get an answer ("which sites do you
// have?"), could not report errors from the app, and had to sleep 150 ms hoping the OS had
// delivered the message. A socket gives request/reply, real exit codes, and liveness detection
// (`connect` succeeds ⇔ the pot is running).

enum UnixSocket {
    static let maxMessage = 4 * 1024 * 1024

    static func address(for path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < capacity else {
            throw UrError("socket path is too long (\(bytes.count) bytes, limit \(capacity - 1)): \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        #if os(macOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        return addr
    }

    static func connect(path: String) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UrError("socket() failed: \(String(cString: strerror(errno)))") }
        var addr = try address(for: path)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let err = errno
            Darwin.close(fd)
            throw UrError("connect failed: \(String(cString: strerror(err)))")
        }
        noSigPipe(fd)
        return fd
    }

    static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setTimeout(_ fd: Int32, seconds: TimeInterval) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let n = bytes[offset...].withUnsafeBufferPointer { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n < 0 { if errno == EINTR { continue }; return false }
            if n == 0 { return false }
            offset += n
        }
        return true
    }

    /// Reads until the first "\n" (excluded) or EOF. Nil on error, timeout, or oversize.
    static func readLine(_ fd: Int32) -> Data? {
        var result = Data()
        var buf = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buf.withUnsafeMutableBufferPointer { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 { if errno == EINTR { continue }; return nil }
            if n == 0 { return result.isEmpty ? nil : result }
            if let nl = buf[0..<n].firstIndex(of: 0x0A) {
                result.append(contentsOf: buf[0..<nl])
                return result
            }
            result.append(contentsOf: buf[0..<n])
            if result.count > maxMessage { return nil }
        }
    }
}

public enum IPCClient {
    /// True when something accepts connections on `socketURL` (i.e. the pot is running).
    public static func isListening(_ socketURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: socketURL.path),
              let fd = try? UnixSocket.connect(path: socketURL.path) else { return false }
        Darwin.close(fd)
        return true
    }

    public static func send(_ request: Request, to socketURL: URL, timeout: TimeInterval = 10) throws -> Response {
        let fd = try UnixSocket.connect(path: socketURL.path)
        defer { Darwin.close(fd) }
        UnixSocket.setTimeout(fd, seconds: timeout)
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        guard UnixSocket.writeAll(fd, payload) else { throw UrError("could not send request to \(socketURL.path)") }
        guard let line = UnixSocket.readLine(fd) else { throw UrError("no reply from \(socketURL.path)") }
        do {
            return try JSONDecoder().decode(Response.self, from: line)
        } catch {
            throw UrError("unreadable reply: \(error)")
        }
    }
}

/// Listens on a pot's socket and hands each `Request` to `handler` on the main queue.
/// The handler calls `reply` exactly once (it may do so later, e.g. after async WebKit work).
public final class IPCServer {
    public typealias Handler = (Request, @escaping (Response) -> Void) -> Void

    public let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "ur.ipc.server", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var signalSources: [DispatchSourceSignal] = []

    public init(socketURL: URL, handler: @escaping Handler) {
        self.socketURL = socketURL
        self.handler = handler
    }

    /// Binds the socket. Throws if another live process already serves this pot — callers
    /// should treat that as "this pot is already running" and exit.
    public func start() throws {
        let path = socketURL.path
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            if IPCClient.isListening(socketURL) {
                throw UrError("pot is already running (socket \(path) is live)")
            }
            unlink(path)  // stale socket from a crash
        }
        try fm.createDirectory(at: socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UrError("socket() failed: \(String(cString: strerror(errno)))") }
        var addr = try UnixSocket.address(for: path)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let err = errno
            Darwin.close(fd)
            throw UrError("bind(\(path)) failed: \(String(cString: strerror(err)))")
        }
        chmod(path, 0o600)
        guard Darwin.listen(fd, 16) == 0 else {
            let err = errno
            Darwin.close(fd)
            unlink(path)
            throw UrError("listen failed: \(String(cString: strerror(err)))")
        }
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source

        // SIGTERM (launchctl, `kill`, smoke-test cleanup) skips applicationWillTerminate, so
        // remove the socket here too; otherwise the next launch sees a stale socket file.
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler { [weak self] in
                self?.stop()
                exit(0)
            }
            s.resume()
            signalSources.append(s)
        }
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
            unlink(socketURL.path)
        }
    }

    private func acceptOne() {
        let client = Darwin.accept(listenFD, nil, nil)
        guard client >= 0 else { return }
        UnixSocket.noSigPipe(client)
        UnixSocket.setTimeout(client, seconds: 10)
        queue.async { [weak self] in self?.serve(client) }
    }

    private func serve(_ client: Int32) {
        let finish: (Response) -> Void = { response in
            var out = (try? JSONEncoder().encode(response)) ?? Data(#"{"ok":false,"error":"encode failed"}"#.utf8)
            out.append(0x0A)
            _ = UnixSocket.writeAll(client, out)
            Darwin.close(client)
        }
        guard let line = UnixSocket.readLine(client) else {
            finish(.failure("empty or unreadable request"))
            return
        }
        guard let request = try? JSONDecoder().decode(Request.self, from: line) else {
            finish(.failure("malformed request"))
            return
        }
        DispatchQueue.main.async { [handler = self.handler, queue = self.queue] in
            var replied = false
            handler(request) { response in
                guard !replied else { return }
                replied = true
                queue.async { finish(response) }
            }
        }
    }
}
