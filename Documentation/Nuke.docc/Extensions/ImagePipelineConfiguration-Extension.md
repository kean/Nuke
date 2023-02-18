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
