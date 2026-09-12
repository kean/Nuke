// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import NukeUI

extension DemoPipelineDiagnostics {
    /// What the caches hold, sampled apart from the counters with
    /// ``DemoPipelineProbe/sampleCaches(for:)``: the size of a disk cache is
    /// read off the disk.
    ///
    /// A cache that several pipelines share is counted once; the figures of
    /// distinct caches are added up, limits included.
    struct Caches: Sendable {
        /// `ImageCache.totalCost`: the memory the decoded images take, in bytes.
        var imageCacheCost = 0
        /// `ImageCache.costLimit`.
        var imageCacheCostLimit = 0
        /// `ImageCache.totalCount`.
        var imageCacheCount = 0

        /// `DataCache.totalSize`, in bytes. `nil` without a `DataCache`.
        ///
        /// A write waits in the cache's staging area for about a second before
        /// it reaches the disk, and only then does it count here.
        var dataCacheSize: Int?
        /// `DataCache.totalCount`.
        var dataCacheCount: Int?
        /// `DataCache.sizeLimit`, which the cache enforces when it sweeps, not
        /// on every write.
        var dataCacheSizeLimit: Int?

        /// `URLCache.currentDiskUsage` of the sessions of the pipelines'
        /// `DataLoader`s, in bytes. `nil` if none of them has a `URLCache`. A
        /// custom loader's session isn't visible.
        var urlCacheDiskUsage: Int?
        /// `URLCache.diskCapacity`.
        var urlCacheDiskCapacity: Int?

        /// `AnimatedImageFramePool.shared.totalCost`: the decoded frames of every
        /// animation playing, whichever pipeline loaded it, in bytes.
        var framePoolCost = 0
        /// `AnimatedImageFramePool.shared.costLimit`.
        var framePoolCostLimit = 0
    }
}

extension DemoPipelineProbe {
    /// Samples what the caches of `pipeline` hold, or of every pipeline alive.
    ///
    /// The disk caches are read off the main thread: `DataCache` lists its
    /// directory to add up the files. Sample it every few seconds, or when
    /// asked, rather than with the counters. The memory caches and the frame
    /// pool are read on the main actor, where the pool lives.
    @MainActor
    static func sampleCaches(for pipeline: ImagePipeline? = nil) async -> DemoPipelineDiagnostics.Caches {
        let probes = if let pipeline { probe(for: pipeline).map { [$0] } ?? [] } else { liveProbes }

        var caches = DemoPipelineDiagnostics.Caches()
        var seen = Set<ObjectIdentifier>()
        var dataCaches: [DataCache] = []
        var urlCaches: [URLCache] = []
        for probe in probes {
            let configuration = probe.configuration
            if let cache = configuration.imageCache as? ImageCache, seen.insert(ObjectIdentifier(cache)).inserted {
                caches.imageCacheCost += cache.totalCost
                caches.imageCacheCostLimit += cache.costLimit
                caches.imageCacheCount += cache.totalCount
            }
            if let cache = configuration.dataCache as? DataCache, seen.insert(ObjectIdentifier(cache)).inserted {
                dataCaches.append(cache)
            }
            if let dataLoader = configuration.dataLoader as? DataLoader,
               let cache = dataLoader.session.configuration.urlCache,
               seen.insert(ObjectIdentifier(cache)).inserted {
                urlCaches.append(cache)
            }
        }

        let pool = AnimatedImageFramePool.shared
        caches.framePoolCost = pool.totalCost
        caches.framePoolCostLimit = pool.costLimit

        if !dataCaches.isEmpty {
            caches.dataCacheSizeLimit = dataCaches.reduce(0) { $0 + $1.sizeLimit }
        }
        if !urlCaches.isEmpty {
            caches.urlCacheDiskCapacity = urlCaches.reduce(0) { $0 + $1.diskCapacity }
        }
        let disk = await Task.detached(priority: .utility) { [dataCaches, urlCaches] in
            (
                dataCacheSize: dataCaches.reduce(0) { $0 + $1.totalSize },
                dataCacheCount: dataCaches.reduce(0) { $0 + $1.totalCount },
                urlCacheDiskUsage: urlCaches.reduce(0) { $0 + $1.currentDiskUsage }
            )
        }.value
        if !dataCaches.isEmpty {
            caches.dataCacheSize = disk.dataCacheSize
            caches.dataCacheCount = disk.dataCacheCount
        }
        if !urlCaches.isEmpty {
            caches.urlCacheDiskUsage = disk.urlCacheDiskUsage
        }
        return caches
    }
}
