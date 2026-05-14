import Darwin
import VibelslandFreeCore
import Foundation

final class BridgeServer: @unchecked Sendable {
    typealias Handler = (Data, @escaping (String?) -> Void) -> Void

    private let maxPayloadBytes = 2 * 1024 * 1024
    private let logger: AppLogger
    private let acceptQueue = DispatchQueue(label: "free.vibelsland.bridge-server.accept")
    private let clientQueue = DispatchQueue(label: "free.vibelsland.bridge-server.client", attributes: .concurrent)
    private var socketFD: Int32 = -1
    private var isRunning = false
    private var socketPath = ""
    private var handler: Handler?

    init(logger: AppLogger = .shared) {
        self.logger = logger
    }

    func start(path: String, handler: @escaping Handler) throws {
        stop()
        self.handler = handler
        socketPath = path

        try AppPaths.ensureRuntimeDirectories()
        try removeExistingSocket(at: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw POSIXError(.EIO)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        #if os(macOS)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif

        let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxPathLength else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }

        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { pathPointer in
                path.withCString { source in
                    strncpy(pathPointer, source, maxPathLength - 1)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            let error = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }

        guard listen(fd, 32) == 0 else {
            let error = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }

        socketFD = fd
        guard chmod(path, 0o600) == 0 else {
            let error = errno
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EIO)
        }
        try validateSocketPermissions(at: path)
        isRunning = true
        logger.info("bridge.start", detail: path)

        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        guard socketFD >= 0 else { return }
        isRunning = false
        close(socketFD)
        socketFD = -1
        if !socketPath.isEmpty {
            unlink(socketPath)
        }
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            if clientFD < 0 {
                if isRunning {
                    logger.error("bridge.accept.failed", detail: String(errno))
                }
                continue
            }
            clientQueue.async { [weak self] in
                self?.handle(clientFD: clientFD)
            }
        }
    }

    private func handle(clientFD: Int32) {
        guard validatePeer(clientFD: clientFD) else {
            logger.error("bridge.peer.rejected")
            close(clientFD)
            return
        }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while true {
            let count = recv(clientFD, &buffer, buffer.count, 0)
            if count > 0 {
                if data.count + count > maxPayloadBytes {
                    logger.error("bridge.payload.too_large", detail: "\(data.count + count)")
                    close(clientFD)
                    return
                }
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        guard !data.isEmpty else {
            close(clientFD)
            return
        }

        handler?(data) { response in
            if let response, let responseData = (response + "\n").data(using: .utf8) {
                responseData.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return }
                    _ = send(clientFD, baseAddress, responseData.count, 0)
                }
            }
            close(clientFD)
        }
    }

    private func removeExistingSocket(at path: String) throws {
        var statBuffer = stat()
        guard lstat(path, &statBuffer) == 0 else {
            if errno == ENOENT { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let fileType = statBuffer.st_mode & S_IFMT
        guard fileType == S_IFSOCK else {
            throw POSIXError(.EEXIST)
        }
        unlink(path)
    }

    private func validatePeer(clientFD: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(clientFD, &uid, &gid) == 0 else {
            return false
        }
        return uid == getuid()
    }

    private func validateSocketPermissions(at path: String) throws {
        var statBuffer = stat()
        guard stat(path, &statBuffer) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard statBuffer.st_uid == getuid(),
              (statBuffer.st_mode & 0o777) == 0o600 else {
            throw POSIXError(.EACCES)
        }
    }
}
