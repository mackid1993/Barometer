import Foundation
import OSLog
import SystemSources

/// Owns one location's scheduler and converts reconnect events into immediate refreshes.
public actor WeatherMonitoringSession {
    /// Weather updates emitted by the location monitor.
    public nonisolated let samples: AsyncStream<WeatherSample>

    private static let logger = Logger(subsystem: "com.barometer.app", category: "weather-refresh")

    private let scheduler: Scheduler<WeatherMonitor>
    private let networkChanges: AsyncStream<Bool>
    private let networkObserver: NetworkPathObserver?
    private var networkTask: Task<Void, Never>?

    /// Creates a production monitoring session using the system network path.
    public init(
        monitor: WeatherMonitor,
        networkObserver: NetworkPathObserver = NetworkPathObserver()
    ) {
        let scheduler = Scheduler(monitor: monitor)
        self.scheduler = scheduler
        samples = scheduler.samples
        networkChanges = networkObserver.changes
        self.networkObserver = networkObserver
    }

    init(monitor: WeatherMonitor, networkChanges: AsyncStream<Bool>) {
        let scheduler = Scheduler(monitor: monitor)
        self.scheduler = scheduler
        samples = scheduler.samples
        self.networkChanges = networkChanges
        networkObserver = nil
    }

    deinit {
        networkTask?.cancel()
    }

    /// Starts sampling and observing network transitions.
    public func start() async {
        guard networkTask == nil else {
            return
        }
        await scheduler.start()
        let changes = networkChanges
        networkTask = Task { [weak self] in
            var previousAvailability: Bool?
            for await isAvailable in changes {
                guard !Task.isCancelled else {
                    break
                }
                if isAvailable, previousAvailability == false {
                    Self.logger.info("Network reconnected; refreshing weather")
                    await self?.scheduler.refresh()
                }
                previousAvailability = isAvailable
            }
        }
    }

    /// Pauses requests while the display is asleep.
    public func pause() async {
        await scheduler.pause()
    }

    /// Resumes and immediately refreshes after wake.
    public func resume() async {
        await scheduler.resume()
        Self.logger.info("Display woke; refreshing weather")
    }

    /// Requests an immediate refresh, for example from a dropdown button.
    public func refresh() async {
        await scheduler.refresh()
    }

    /// Stops sampling and network observation permanently.
    public func stop() async {
        networkTask?.cancel()
        networkTask = nil
        await scheduler.stop()
    }
}
