import Foundation
import Observation

/// Everything the UI needs: the latest sample of each metric plus rolling histories.
public struct MonitorSnapshot: Equatable, Sendable {
    public var time: Date
    public var cpu: CPUSample?
    public var memory: MemorySample?
    public var gpu: GPUSample?
    public var network: NetworkSample?
    public var disk: DiskSample?
    public var battery: BatterySample?
    public var processes: ProcessSample?

    public init(time: Date = Date(), cpu: CPUSample? = nil, memory: MemorySample? = nil, gpu: GPUSample? = nil,
                network: NetworkSample? = nil, disk: DiskSample? = nil, battery: BatterySample? = nil, processes: ProcessSample? = nil) {
        self.time = time
        self.cpu = cpu
        self.memory = memory
        self.gpu = gpu
        self.network = network
        self.disk = disk
        self.battery = battery
        self.processes = processes
    }
}

public struct Histories: Equatable, Sendable {
    public var cpuTotal = History()
    /// One series per CPU performance level, in `CPUTopology` order.
    public var cpuLevels: [History] = []
    public var memoryPressure = History()
    public var memoryUsed = History()
    public var swapUsed = History()
    public var gpu = History()
    public var networkDown = History()
    public var networkUp = History()
    public var diskRead = History()
    public var diskWrite = History()
    public var systemPower = History()
    public var batteryCharge = History()

    public init() {}
}

/// Samples all readers on a background timer and publishes results on the main actor.
@MainActor
@Observable
public final class Monitor {
    public private(set) var snapshot = MonitorSnapshot()
    public private(set) var histories = Histories()
    public let topology: CPUTopology
    public var isRunning: Bool { timer != nil }

    /// Process enumeration is the costliest reader and only feeds the panel, so it's skipped
    /// while the panel is closed.
    public var includeProcesses = false {
        didSet { sampler.includeProcesses = includeProcesses }
    }

    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private let queue = DispatchQueue(label: "vitals.sampler", qos: .utility)
    @ObservationIgnored private let sampler: Sampler
    @ObservationIgnored private var interval: TimeInterval

    public init(interval: TimeInterval = 1, includeProcesses: Bool = false) {
        self.interval = interval
        self.includeProcesses = includeProcesses
        sampler = Sampler()
        sampler.includeProcesses = includeProcesses
        topology = sampler.cpu.topology
        histories.cpuLevels = topology.levels.map { _ in History() }
    }

    public func start() {
        guard timer == nil else { return }
        schedule()
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func setInterval(_ newInterval: TimeInterval) {
        guard newInterval != interval else { return }
        interval = newInterval
        if timer != nil {
            stop()
            schedule()
        }
    }

    /// Takes one sample synchronously on the calling thread. Useful for tests and the first paint.
    /// Not safe to mix with `start()`: the readers keep per-call state and expect one caller.
    public func sampleNow() {
        apply(sampler.sample())
    }

    /// Schedules an extra sample on the sampling queue, ahead of the next timer tick. Used when
    /// the panel opens so delta-based readers (processes) prime without waiting a full interval.
    public func kick() {
        queue.async { [sampler, weak self] in
            let result = sampler.sample()
            Task { @MainActor in self?.apply(result) }
        }
    }

    private func schedule() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // A generous leeway lets the kernel coalesce our wakeups with others, which keeps the
        // monitor cheap without visibly affecting a 1 s refresh.
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [sampler, weak self] in
            let result = sampler.sample()
            Task { @MainActor in self?.apply(result) }
        }
        timer.resume()
        self.timer = timer
    }

    private func apply(_ new: MonitorSnapshot) {
        let t = new.time
        if let cpu = new.cpu {
            histories.cpuTotal.append(cpu.total, at: t)
            for (i, level) in cpu.levels.enumerated() where i < histories.cpuLevels.count {
                histories.cpuLevels[i].append(level.load, at: t)
            }
        }
        if let mem = new.memory {
            histories.memoryPressure.append(mem.pressure, at: t)
            histories.memoryUsed.append(mem.usedFraction, at: t)
            histories.swapUsed.append(Double(mem.swapUsedBytes), at: t)
        }
        if let gpu = new.gpu { histories.gpu.append(gpu.utilization, at: t) }
        if let net = new.network {
            histories.networkDown.append(net.downloadRate, at: t)
            histories.networkUp.append(net.uploadRate, at: t)
        }
        if let disk = new.disk {
            histories.diskRead.append(disk.readRate, at: t)
            histories.diskWrite.append(disk.writeRate, at: t)
        }
        if let bat = new.battery {
            histories.systemPower.append(bat.systemPowerWatts, at: t)
            histories.batteryCharge.append(bat.charge, at: t)
        }
        // Keep the last good value for readers that return nil on a given tick.
        var merged = new
        merged.cpu = new.cpu ?? snapshot.cpu
        merged.network = new.network ?? snapshot.network
        merged.disk = new.disk ?? snapshot.disk
        merged.processes = new.processes ?? snapshot.processes
        snapshot = merged
    }
}

/// Owns the stateful readers; `sample()` must only run on the sampling queue.
final class Sampler: @unchecked Sendable {
    let cpu = CPUReader()
    let memory = MemoryReader()
    let gpu = GPUReader()
    let network = NetworkReader()
    let disk = DiskReader()
    let battery = BatteryReader()
    let processes = ProcessReader(limit: 5)
    /// Read on the sampling queue, written from the main actor; a stale read only delays the
    /// process list by one tick.
    var includeProcesses = false

    func sample() -> MonitorSnapshot {
        let now = Date()
        return MonitorSnapshot(
            time: now,
            cpu: cpu.sample(),
            memory: memory.sample(),
            gpu: gpu.sample(),
            network: network.sample(now: now),
            disk: disk.sample(now: now),
            battery: battery.sample(),
            processes: includeProcesses ? processes.sample(now: now) : nil
        )
    }
}
