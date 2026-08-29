# ``Nuke/ImagePipeline/Configuration-swift.struct``

## Topics

### Initializers

- ``init(dataLoader:)``

### Predefined Configurations

To learn more about caching, see <doc:caching>.

- ``withDataCache``
- ``withDataCache(name:sizeLimit:)``
- ``withURLCache``

### Dependencies

- ``dataLoader``
- ``dataCache``
- ``imageCache``
- ``makeImageDecoder``
- ``makeImageEncoder``

### Caching Options

- ``dataCachePolicy``
- ``ImagePipeline/DataCachePolicy``
- ``isStoringPreviewsInMemoryCache``

### Other Options

- ``isDecompressionEnabled``
- ``isTaskCoalescingEnabled``
- ``isRateLimiterEnabled``
- ``isProgressiveDecodingEnabled``
- ``progressiveDecodingInterval``
- ``isResumableDataEnabled``

### Global Options

- ``isSignpostLoggingEnabled``

### Operation Queues

``TaskQueue`` is a class, so copies of a configuration share the same queues. Changing a queue obtained from `ImagePipeline.shared.configuration` also changes it for the shared pipeline.

- ``dataLoadingQueue``
- ``imageProcessingQueue``
- ``imageDecompressingQueue``
- ``imageDecodingQueue``
- ``imageEncodingQueue``
