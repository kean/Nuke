# FAQ

## Q1. How to send an authorization header (or other HTTP headers fields) in the request?

**Option 1**. Provide a header when creating a request.

```swift
var urlRequest = URLRequest(url: <#url#>)
urlRequest.allHTTPHeaderFields["authorization"] = <#credentials#>
let request = ImageRequest(urlRequest: urlRequest)
```

**Option 2**. Create a data loader with a `URLSessionConfiguration` which desired headers.

```swift
let pipeline = ImagePipeline {
    let configuration = DataLoader.defaultConfiguration
   configuration.httpAdditionalHeaders["authorization"] = <#auth#>
   $0.dataLoader = DataLoader(configuration: configuration)
}
```
