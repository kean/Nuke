# ``Nuke/ImagePipeline/Delegate-swift.protocol``

## Overview

Every method declares its isolation in its own signature. The methods that return a customization are `nonisolated`; the ones that report to the delegate run on ``ImagePipelineActor``. See <doc:where-work-runs> for the full table and what it means for a `@MainActor` delegate.

## Topics

### Data Loading

- ``dataLoader(for:pipeline:)``
- ``willLoadData(for:urlRequest:pipeline:)``

### Decoding and Encoding

- ``imageDecoder(for:pipeline:)``
- ``imageEncoder(for:pipeline:)``
- ``previewPolicy(for:pipeline:)``

### Caching

- ``imageCache(for:pipeline:)``
- ``dataCache(for:pipeline:)``
- ``cacheKey(for:pipeline:)``
- ``willCache(data:image:for:pipeline:)``

### Decompression

- ``shouldDecompress(response:for:pipeline:)``
- ``decompress(response:request:pipeline:)``

### Observing Tasks

- ``imageTaskCreated(_:pipeline:)``
- ``imageTaskDidStart(_:pipeline:)``
- ``imageTask(_:didReceiveEvent:pipeline:)``
