# ``Nuke/ImagePipeline/Delegate-swift.protocol``

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
- ``willCache(data:image:for:pipeline:completion:)``

### Decompression

- ``shouldDecompress(response:for:pipeline:)``
- ``decompress(response:request:pipeline:)``
