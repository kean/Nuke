# ``Nuke/ImagePipeline/Configuration-swift.struct``

## Topics

### Initializers

- ``init(dataLoader:)``

### Predefined Configurations

To learn more about caching and built-in configuration, see <doc:cache-configuration>.

- ``withDataCache``
- ``withDataCache(sizeLimit:)``
- ``withURLCache``

### Dependencies

- ``dataLoader``
- ``dataCache``
- ``imageCache``
- ``makeImageDecoder``
- ``makeImageEncoder``

### Options

- ``isDecompressionEnabled``
- ``dataCachePolicy-swift.property``
- ``DataCachePolicy-swift.enum``
- ``isTaskCoalescingEnabled``
- ``isRateLimiterEnabled``
- ``isProgressiveDecodingEnabled``
- ``isStoringPreviewsInMemoryCache``
- ``isResumableDataEnabled``
- ``callbackQueue``

### Global Options

- ``isSignpostLoggingEnabled``

### Operation Queues

- ``dataLoadingQueue``
- ``dataCachingQueue``
- ``imageProcessingQueue``
- ``imageDecompressingQueue``
- ``imageDecodingQueue``
- ``imageEncodingQueue``
