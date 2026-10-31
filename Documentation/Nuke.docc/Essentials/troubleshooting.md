# Troubleshooting

Find out why an image doesn't show up, or takes too long.

## Read the Log

Launch the app with the `NUKE_DIAGNOSTICS_LOG` environment variable set to `1`, and the pipeline logs a line for every task that finishes, with no changes to the app. Set it in the scheme, or in the code with ``ImagePipeline/Configuration-swift.struct/isDiagnosticsLoggingEnabled``.

The lines show up in the Xcode console, and they can be read from a terminal:

```bash
# A Mac app
NUKE_DIAGNOSTICS_LOG=1 ./MyApp
log stream --predicate 'subsystem == "com.github.kean.Nuke.ImagePipeline"'

# An app on a simulator
SIMCTL_CHILD_NUKE_DIAGNOSTICS_LOG=1 xcrun simctl launch booted com.example.app
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.Nuke.ImagePipeline"'
```

Here is what a server that sends an error page, a missing image, and a server that can't be reached look like:

```
ImageTask #1 · success · 78.5 ms · from network · https://example.com/a.png · 1200×800 · png · 3.7 MB in memory · 70 KB
ImageTask #2 · failure · 2.4 ms · decodingFailed · Failed to decode image data using decoder Nuke.ImageDecoders.Default. Received 60 bytes of text/html (HTTP 200) from https://example.com/b.jpg?…, starting with "<!DOCTYPE html><html><body>Sign".
ImageTask #3 · failure · 1.1 ms · https://example.com/c.jpg · dataLoadingFailed · Failed to load image data. Underlying error: Response status code was unacceptable: 404.
ImageTask #4 · failure · 1.5 ms · https://example.com/d.jpg?… · dataLoadingFailed · NSURLErrorDomain -1004
```

The URLs in the lines have no query, which can carry a token. ``ImageTask/Metrics/summary`` gives you the same line in code.

| The line says | What happened | What to do |
|---|---|---|
| `decodingFailed`, and the data is text | The server answered with a page instead of an image, usually a login or an error page | Fix the request. If it needs a token, add it in ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)`` |
| `decodingFailed`, and the data is an image | The file is corrupted, or the system can't decode the format | See <doc:supported-image-formats>, and register a decoder |
| `decoderNotRegistered` | The pipeline has a custom ``ImagePipeline/Configuration-swift.struct/makeImageDecoder`` that returned `nil` | Fall back to ``ImageDecoders/Default`` |
| `Response status code was unacceptable` | The server answered with an error | Check the URL. ``DataLoader`` rejects everything but `2xx` |
| `NSURLErrorDomain` and a code | `URLSession` failed. `-1009` is no connection, `-1004` is a refused connection, `-1022` is App Transport Security, and `-1001` is a timeout | See `URLError.Code` |
| `dataMissingInCache` | The request has ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad``, and the image isn't cached | Expected, unless you meant to load it |
| `cancelled` | The view went away, or something called `cancel()`. A cell that scrolls off the screen does it | Expected. To keep the download going when a `LazyImage` disappears, use `onDisappear(.lowerPriority)` |
| `success`, and the view is blank | The image loaded. The problem is in the view | `LazyImage(url:)` shows the image at its natural size. Check its frame, and call `resizable()` in the `content` closure |
| Nothing at all | The pipeline never got a task | The URL is `nil`, or another pipeline loaded the image, one with logging off. A hit in the memory cache that a view finds on its own creates no task either |

## Inspect a Running Pipeline

A line is logged when a task finishes, so it can't tell you why one hasn't. For that, ask the pipeline. It works with diagnostics off, and it can be done from the debugger, where you can't `await`:

```
(lldb) po ImagePipeline.shared.diagnostics
ImagePipeline 7F36CD14 · 3 tasks
  dataLoadingQueue         3/6 running
  imageDecodingQueue       0/2 running
  imageEncodingQueue       0/1 running
  imageProcessingQueue     0/2 running
  imageDecompressingQueue  0/2 running
memory cache: 120 images · 84 MB of 805.3 MB
disk cache: none
  #6 · normal · http://example.com/slow-1.jpg?…
  #7 · normal · http://example.com/slow-2.jpg?…
  #8 · normal · http://example.com/slow-3.jpg?…
```

From code, use ``ImagePipeline/Diagnostics-swift.struct/snapshot()``:

```swift
print(await ImagePipeline.shared.diagnostics.snapshot())
```

A queue at its limit with work pending means the pipeline is busy, and a task waits for a slot. A queue marked `suspended` starts nothing until ``TaskQueue/isSuspended`` is set back. A queue with free slots and a task that doesn't finish means the task is waiting on the server.

## Read the Whole Record

To see where the time of a slow task went, print its record. It needs ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``, and it's described in <doc:performance-guide>, along with what to check before a record leaves the device: it has the full URLs, with their query strings.

```swift
let task = pipeline.imageTask(with: url)
_ = try await task.image
print(task.metrics!)
```

## An Image Is Loaded Twice

A task is coalesced with another only if they ask for the same thing, and a cache entry is found only under the same key. The key includes the processors and the thumbnail options, so a prefetcher and a view that disagree about them load the image twice. Use the same ``ImageRequest`` in both.

`ImagePipeline.shared` has no ``DataCache``. It relies on the `URLCache` of ``DataLoader``, which follows the `cache-control` headers of the server, so a response that says `no-store` isn't kept. To cache everything on disk, use ``ImagePipeline/Configuration-swift.struct/withDataCache``.
