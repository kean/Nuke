# ``Nuke/ImagePipeline``

@Metadata {
    @DocumentationExtension(mergeBehavior: override)
}

``ImagePipeline`` is the primary way to load images.

## Overview

The pipeline is fully customizable. You can change its configuration using ``ImagePipeline/Configuration-swift.struct`` by setting custom data loader and cache, configure image encoders and decoders, etc. You can also set an ``ImagePipelineDelegate`` to get even more granular control on a per-request basis.

``ImagePipeline`` is fully thread-safe.

## Topics

### Initializers

- ``init(configuration:delegate:)``
- ``init(delegate:_:)``
- ``shared``

### Configuration

- ``configuration-swift.property``
- ``Configuration-swift.struct``

### Loading Images (Async/Await)

- ``image(for:delegate:)``

### Loading Image (Closures)

- ``loadImage(with:completion:)``
- ``loadImage(with:queue:progress:completion:)``

### Loading Images (Combine)

- ``imagePublisher(with:)``

### Loading Data (Async/Await)

- ``data(for:)``

### Loading Data (Closures)

- ``loadData(with:completion:)``
- ``loadData(with:queue:progress:completion:)``

### Accessing Cached Images

- ``cache-swift.property``
- ``Cache-swift.struct``

### Invalidation

- ``invalidate()``

### Error Handling

- ``Error``
