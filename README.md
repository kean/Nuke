<br/>

<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="220">

# Powerful Image Loading System

<p align="left">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<img src="https://github.com/kean/Nuke/workflows/Nuke%20CI/badge.svg">
</p>

Nuke provides a simple and efficient way to download and display images in your app.

Behind Nuke's clear and concise API is an advanced architecture that enables its unique features and offers virtually unlimited possibilities for customization. Despite the number of features, the framework is lean and compiles in under 2 seconds. Nuke's primary feature is [performance](https://kean.blog/post/nuke-9).

> **Fast LRU memory and disk cache** · **SwiftUI** · **Smart background decompression** · **Image processing** · **Elegant builder API** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Prefetching** · **Rate limiting** · **Progressive JPEG, HEIF, WebP, SVG, GIF** · **Alamofire** · **Combine** · **Reactive extensions**

## Sponsors
[![Stream](https://i.imgur.com/oU7XYkk.png)](https://getstream.io/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship)

Nuke is proudly sponsored by [Stream](https://getstream.io/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship), the leading provider in enterprise grade [Feed](https://getstream.io/activity-feeds/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship) & [Chat](https://getstream.io/chat/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship) APIs. [Try the iOS Chat Tutorial](https://getstream.io/tutorials/ios-chat/?utm_source=github&utm_medium=nuke&utm_campaign=sponsorship).

## Documentation

Nuke is easy to learn and use thanks to beautiful [**Nuke Docs**](https://kean.blog/nuke/guides/welcome). Make sure to also check out [**Nuke Demo**](https://github.com/kean/NukeDemo).

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/9.6.0/Documentation/Migrations).

<a href="https://kean.blog/nuke/guides/welcome">
<img src="https://user-images.githubusercontent.com/1567433/114312077-59259b80-9abf-11eb-93f9-29fb87eb025a.png">
</a>

<a name="h_plugins"></a>
## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**FetchImage**](https://github.com/kean/FetchImage)|SwiftUI integration|
|[**ImagePublisher**](https://github.com/kean/ImagePublisher)|Combine publishers for Nuke|
|[**ImageTaskBuilder**](https://github.com/kean/ImageTaskBuilder)|A fun and convenient way to use Nuke|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**Gifu Plugin**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage Plugin**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|
|[**Xamarin NuGet**](https://github.com/roubachof/Xamarin.Forms.Nuke)| **Community**. Makes it possible to use Nuke from Xamarin|

<a name="h_contribute"></a>
## Contribution

[Nuke's roadmap](https://trello.com/b/Us4rHryT/nuke) is managed in Trello and is publicly available.

<a name="h_requirements"></a>
## Minimum Requirements

| Nuke          | Swift           | Xcode           | Platforms                                         |
|---------------|-----------------|-----------------|---------------------------------------------------|
| Nuke 9.0      | Swift 5.1       | Xcode 11.0      | iOS 11.0 / watchOS 4.0 / macOS 10.13 / tvOS 11.0  |
| Nuke 8.0      | Swift 5.0       | Xcode 10.2      | iOS 10.0 / watchOS 3.0 / macOS 10.12 / tvOS 10.0  |

See [Installation Guide](https://github.com/kean/Nuke/blob/9.6.0/Documentation/Guides/installation-guide.md#h_requirements) for information about the older versions.

## License

Nuke is available under the MIT license. See the LICENSE file for more info.
