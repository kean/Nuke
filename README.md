<br/>

<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="205">

# Image Loading System

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<img src="https://github.com/kean/Nuke/workflows/Nuke%20CI/badge.svg">
</p>

Nuke provides an efficient way to download and display images in your app. It's easy to learn and use. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

The framework is lean and compiles in under 2 seconds[¹](#footnote-1). Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for [performance](https://kean.blog/post/nuke-9).

> **Fast LRU memory and disk cache** · **SwiftUI** · **Smart background decompression** · **Image processing** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Prefetching** · **Rate limiting** · **Progressive JPEG, HEIF, WebP, SVG, GIF** · **Alamofire** · **Combine** · **Async/Await**

## Sponsors 💖

<a href="https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22"><img width="200px" src="https://user-images.githubusercontent.com/1567433/175186173-64eb53cb-b5d6-4ed4-aaca-87dbbb0834ab.png#gh-light-mode-only"></a><a href="https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22"><img width="200px" src="[https://user-images.githubusercontent.com/1567433/175186173-64eb53cb-b5d6-4ed4-aaca-87dbbb0834ab.png](https://user-images.githubusercontent.com/1567433/175560784-54c20f9e-4e43-49ff-860a-ccf411c85409.png)#gh-dark-mode-only"></a>

Nuke is proudly sponsored by [Stream](https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22), the leading provider in enterprise grade Feed & Chat APIs.

> [Support](https://github.com/sponsors/kean) Nuke on GitHub Sponsors.

## Documentation

Nuke is easy to learn and use thanks to [**Nuke Docs**](https://kean.blog/nuke/guides/welcome). Make sure to also check out [**Nuke Demo**](https://github.com/kean/NukeDemo).

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/10.0.0/Documentation/Migrations). Switching from another framework? Use a [**Switching Guide**](https://github.com/kean/Nuke/tree/master/Documentation/Switch).

<a href="https://kean.blog/nuke/guides/welcome">
<img src="https://user-images.githubusercontent.com/1567433/114312077-59259b80-9abf-11eb-93f9-29fb87eb025a.png">
</a>

<a name="h_plugins"></a>
## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**NukeUI**](https://github.com/kean/NukeUI)|Lazy image loading for SwiftUI|
|[**NukeBuilder**](https://github.com/kean/NukeBuilder)|A fun and convenient way to use Nuke|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|
|[**NukeWebP**](https://github.com/makleso6/NukeWebP)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Maxim Kolesnik](https://github.com/makleso6)|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**Gifu Plugin**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage Plugin**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|
|[**Xamarin NuGet**](https://github.com/roubachof/Xamarin.Forms.Nuke)| **Community**. Makes it possible to use Nuke from Xamarin|

<a name="h_contribute"></a>
## Contribution

[Nuke's roadmap](https://trello.com/b/Us4rHryT/nuke) is managed in Trello and is publicly available.

<a name="h_requirements"></a>
## Minimum Requirements

| Nuke          | Swift           | Xcode           | Platforms                                      |
|---------------|-----------------|-----------------|------------------------------------------------|
| Nuke 10.0     | Swift 5.3       | Xcode 12.0      | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0  |
| Nuke 9.0      | Swift 5.1       | Xcode 11.0      | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0  |

See [Installation Guide](https://kean.blog/nuke/guides/installation) for information about the older versions.

## License

Nuke is available under the MIT license. See the LICENSE file for more info.

----

> <a name="footnote-1">¹</a> Measured on MacBook Pro 14" 2021 (10-core M1 Pro)
