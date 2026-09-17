// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Darwin
import os

/// How much memory the app takes, read from the kernel whenever
/// ``sample()`` is called.
///
/// A value: keep one per thing that measures, with its own peak.
///
/// ```swift
/// var footprint = DemoFootprint()
/// footprint.sample() // on a timer
/// print(footprint.current, footprint.peak)
/// ```
struct DemoFootprint: Sendable, Equatable {
    /// `phys_footprint` from `task_vm_info`: the memory the system charges
    /// the app for, and the figure it terminates the app over. `nil` until
    /// the first sample, or if the kernel didn't answer.
    var current: Int?
    /// The highest ``current`` sampled since the last reset. A spike between
    /// two samples is missed; ``lifetimePeak`` isn't.
    var peak = 0
    /// `ledger_phys_footprint_peak`: the kernel's own peak since the app
    /// launched, which misses nothing and can't be reset.
    var lifetimePeak: Int?
    /// `os_proc_available_memory()`: how much more the app can take before
    /// the system terminates it. `nil` where there is no such limit, which
    /// includes the simulator.
    var available: Int?

    /// Reads the figures now and folds them into the peak. A call into the
    /// kernel: cheap enough for ten times a second.
    mutating func sample() {
        guard let figures = Self.read() else { return }
        current = figures.footprint
        lifetimePeak = figures.lifetimePeak
        peak = max(peak, figures.footprint)
        available = Self.readAvailable()
    }

    /// Starts the peak over from the last sample.
    mutating func reset() {
        peak = current ?? 0
    }

    /// `phys_footprint` and `ledger_phys_footprint_peak` of this process.
    static func read() -> (footprint: Int, lifetimePeak: Int)? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (Int(info.phys_footprint), Int(info.ledger_phys_footprint_peak))
    }

    private static func readAvailable() -> Int? {
        #if os(macOS)
        return nil
        #else
        let available = os_proc_available_memory()
        return available > 0 ? available : nil
        #endif
    }
}
