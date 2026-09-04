import Dispatch
import Network

/// Reports network reachability changes without requiring a polling loop.
public final class NetworkPathObserver: Sendable {
    /// Emits the initial and subsequent network availability states.
    public let changes: AsyncStream<Bool>

    private let monitor: NWPathMonitor
    private let continuation: AsyncStream<Bool>.Continuation

    /// Starts observing the system's default network path.
    public init() {
        let stream = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        changes = stream.stream
        continuation = stream.continuation
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            stream.continuation.yield(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "com.barometer.app.network-path"))
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
