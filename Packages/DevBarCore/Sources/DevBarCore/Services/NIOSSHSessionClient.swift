import Foundation
import NIOCore
import NIOPosix
import NIOSSH

public final class NIOSSHSessionClient: TerminalSessionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var group: MultiThreadedEventLoopGroup?
    private var parentChannel: Channel?
    private var sessionChannel: Channel?
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?

    public init() {}

    public func outputStream() async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.lock.withLock {
                self.continuation = continuation
            }
        }
    }

    public func connect(configuration: TerminalConnectionConfiguration) async throws {
        await disconnect()

        let authDelegate = try NIOSSHFixedAuthenticationDelegate(
            username: configuration.username,
            authentication: configuration.authentication
        )

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.lock.withLock {
            self.group = group
        }

        let bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.eventLoop.makeCompletedFuture {
                    let sshHandler = NIOSSHHandler(
                        role: .client(.init(
                            userAuthDelegate: authDelegate,
                            serverAuthDelegate: NIOSSHAcceptAllHostKeysDelegate()
                        )),
                        allocator: channel.allocator,
                        inboundChildChannelInitializer: nil
                    )

                    let sync = channel.pipeline.syncOperations
                    try sync.addHandler(sshHandler)
                    try sync.addHandler(NIOSSHErrorClosingHandler { [weak self] error in
                        self?.finish(error)
                    })
                }
            }
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

        let parent = try await bootstrap.connect(host: configuration.host, port: configuration.port).get()
        self.lock.withLock {
            self.parentChannel = parent
        }

        let session = try await parent.pipeline.handler(type: NIOSSHHandler.self).flatMap { [weak self] sshHandler in
            let sessionPromise = parent.eventLoop.makePromise(of: Channel.self)
            sshHandler.createChannel(sessionPromise) { childChannel, channelType in
                guard channelType == .session else {
                    return childChannel.eventLoop.makeFailedFuture(TerminalSessionClientError.invalidChannelType)
                }

                return childChannel.eventLoop.makeCompletedFuture {
                    try childChannel.pipeline.syncOperations.addHandler(NIOSSHInteractiveShellHandler { [weak self] chunk in
                        self?.yield(chunk)
                    })
                    try childChannel.pipeline.syncOperations.addHandler(NIOSSHErrorClosingHandler { [weak self] error in
                        self?.finish(error)
                    })
                }
            }
            return sessionPromise.futureResult
        }.get()
        try await session.setOption(ChannelOptions.allowRemoteHalfClosure, value: true).get()

        let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: configuration.columns,
            terminalRowHeight: configuration.rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([.VERASE: 0x7F])
        )
        try await session.triggerUserOutboundEvent(ptyRequest).get()
        try await session.triggerUserOutboundEvent(SSHChannelRequestEvent.ShellRequest(wantReply: true)).get()

        self.lock.withLock {
            self.sessionChannel = session
        }
        try await send(Data(TerminalPromptSetup.command.utf8))
    }

    public func send(_ data: Data) async throws {
        let channel = lock.withLock { sessionChannel }
        guard let channel, channel.isActive else {
            throw TerminalSessionClientError.notConnected
        }

        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        try await channel.writeAndFlush(SSHChannelData(type: .channel, data: .byteBuffer(buffer))).get()
    }

    public func disconnect() async {
        let values = lock.withLock {
            let values = (sessionChannel, parentChannel, group)
            sessionChannel = nil
            parentChannel = nil
            group = nil
            continuation?.finish()
            continuation = nil
            return values
        }

        try? await values.0?.close().get()
        try? await values.1?.close().get()
        if let group = values.2 {
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                group.shutdownGracefully { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func yield(_ chunk: String) {
        lock.withLock {
            _ = continuation?.yield(chunk)
        }
    }

    private func finish(_ error: Error?) {
        lock.withLock {
            sessionChannel = nil
            if let error {
                continuation?.finish(throwing: error)
            } else {
                continuation?.finish()
            }
        }
    }
}

public final class NIOSSHCommandClient: @unchecked Sendable {
    public init() {}

    public func run(command: String, configuration: TerminalConnectionConfiguration) async throws -> String {
        let authDelegate = try NIOSSHFixedAuthenticationDelegate(
            username: configuration.username,
            authentication: configuration.authentication
        )
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        var parentChannel: Channel?
        var sessionChannel: Channel?

        do {
            let bootstrap = ClientBootstrap(group: group)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        let sshHandler = NIOSSHHandler(
                            role: .client(.init(
                                userAuthDelegate: authDelegate,
                                serverAuthDelegate: NIOSSHAcceptAllHostKeysDelegate()
                            )),
                            allocator: channel.allocator,
                            inboundChildChannelInitializer: nil
                        )

                        let sync = channel.pipeline.syncOperations
                        try sync.addHandler(sshHandler)
                        try sync.addHandler(NIOSSHErrorClosingHandler { _ in })
                    }
                }
                .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)

            let parent = try await bootstrap.connect(host: configuration.host, port: configuration.port).get()
            parentChannel = parent

            let outputPromise = parent.eventLoop.makePromise(of: String.self)
            let session = try await parent.pipeline.handler(type: NIOSSHHandler.self).flatMap { sshHandler in
                let sessionPromise = parent.eventLoop.makePromise(of: Channel.self)
                sshHandler.createChannel(sessionPromise) { childChannel, channelType in
                    guard channelType == .session else {
                        return childChannel.eventLoop.makeFailedFuture(TerminalSessionClientError.invalidChannelType)
                    }

                    return childChannel.eventLoop.makeCompletedFuture {
                        try childChannel.pipeline.syncOperations.addHandler(NIOSSHCommandOutputHandler(outputPromise: outputPromise))
                        try childChannel.pipeline.syncOperations.addHandler(NIOSSHErrorClosingHandler { error in
                            if let error {
                                outputPromise.fail(error)
                            }
                        })
                    }
                }
                return sessionPromise.futureResult
            }.get()
            sessionChannel = session

            try await session.triggerUserOutboundEvent(SSHChannelRequestEvent.ExecRequest(
                command: command,
                wantReply: true
            )).get()

            let output = try await outputPromise.futureResult.get()
            await close(sessionChannel: sessionChannel, parentChannel: parentChannel, group: group)
            return output
        } catch {
            await close(sessionChannel: sessionChannel, parentChannel: parentChannel, group: group)
            throw error
        }
    }

    private func close(sessionChannel: Channel?, parentChannel: Channel?, group: MultiThreadedEventLoopGroup) async {
        try? await sessionChannel?.close().get()
        try? await parentChannel?.close().get()
        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

private final class NIOSSHAcceptAllHostKeysDelegate: NIOSSHClientServerAuthenticationDelegate, Sendable {
    func validateHostKey(hostKey _: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        validationCompletePromise.succeed(())
    }
}

private final class NIOSSHFixedAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, Sendable {
    private let username: String
    private let authentication: TerminalConnectionAuthentication
    private let privateKey: NIOSSHPrivateKey?

    init(username: String, authentication: TerminalConnectionAuthentication) throws {
        self.username = username
        self.authentication = authentication
        switch authentication {
        case .password:
            self.privateKey = nil
        case let .privateKey(pem, passphrase):
            self.privateKey = try TerminalPrivateKeyParser.parse(pem, passphrase: passphrase)
        }
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        switch authentication {
        case let .password(password):
            guard availableMethods.contains(.password) else {
                nextChallengePromise.fail(TerminalSessionClientError.passwordAuthenticationNotSupported)
                return
            }
            nextChallengePromise.succeed(.init(
                username: username,
                serviceName: "ssh-connection",
                offer: .password(.init(password: password))
            ))
        case .privateKey:
            guard availableMethods.contains(.publicKey), let privateKey else {
                nextChallengePromise.fail(TerminalSessionClientError.publicKeyAuthenticationNotSupported)
                return
            }
            nextChallengePromise.succeed(.init(
                username: username,
                serviceName: "ssh-connection",
                offer: .privateKey(.init(privateKey: privateKey))
            ))
        }
    }
}

private final class NIOSSHInteractiveShellHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let onOutput: @Sendable (String) -> Void

    init(onOutput: @escaping @Sendable (String) -> Void) {
        self.onOutput = onOutput
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case var .byteBuffer(buffer) = channelData.data else { return }

        if let text = buffer.readString(length: buffer.readableBytes), !text.isEmpty {
            onOutput(text)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelEvent {
            context.close(promise: nil)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }
}

private final class NIOSSHCommandOutputHandler: ChannelInboundHandler {
    typealias InboundIn = SSHChannelData

    private let outputPromise: EventLoopPromise<String>
    private var output = ""
    private var completed = false

    init(outputPromise: EventLoopPromise<String>) {
        self.outputPromise = outputPromise
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let channelData = unwrapInboundIn(data)
        guard case var .byteBuffer(buffer) = channelData.data else { return }

        if let text = buffer.readString(length: buffer.readableBytes), !text.isEmpty {
            output.append(text)
        }
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if event is ChannelEvent {
            complete()
            context.close(promise: nil)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }

    func channelInactive(context: ChannelHandlerContext) {
        complete()
        context.fireChannelInactive()
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        outputPromise.succeed(output)
    }
}

private final class NIOSSHErrorClosingHandler: ChannelInboundHandler {
    typealias InboundIn = Any

    private let onError: @Sendable (Error?) -> Void

    init(onError: @escaping @Sendable (Error?) -> Void) {
        self.onError = onError
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if error.isExpectedChannelClosure {
            onError(nil)
        } else {
            onError(error)
        }
        context.close(promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        onError(nil)
        context.fireChannelInactive()
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension Error {
    var isExpectedChannelClosure: Bool {
        guard let channelError = self as? ChannelError else { return false }
        switch channelError {
        case .ioOnClosedChannel, .alreadyClosed, .outputClosed, .inputClosed, .eof:
            return true
        default:
            return false
        }
    }
}
