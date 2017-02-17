# CocoaPods

[CocoaPods](http://cocoapods.org) is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

> CocoaPods 1.1.0+ is required to build Nuke 4.0+.

To integrate Nuke into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '10.0'
use_frameworks!

target '<Your Target Name>' do
    pod 'Nuke', '~> 5.0'
end
```

Then, run the following command:

```bash
$ pod install
```

# Carthage

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks.

You can install Carthage with [Homebrew](http://brew.sh/) using the following command:

```bash
$ brew update
$ brew install carthage
```

To integrate Nuke into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "kean/Nuke" ~> 5.0
```

Run `carthage update` to build the framework and drag the built `Nuke.framework` into your Xcode project.

# Manually

If you prefer not to use either of the aforementioned dependency managers, you can integrate Nuke into your project manually.

## Embedded Framework

- Open up Terminal, `cd` into your top-level project directory, and run the following command "if" your project is not initialized as a git repository:

```bash
$ git init
```

- Add Nuke as a git [submodule](http://git-scm.com/docs/git-submodule) by running the following command:

```bash
$ git submodule add https://github.com/kean/Nuke.git
```

- Open the new `Nuke` folder, and drag the `Nuke.xcodeproj` into the Project Navigator of your application's Xcode project.

> It should appear nested underneath your application's blue project icon. Whether it is above or below all the other Xcode groups does not matter.

- Select the `Nuke.xcodeproj` in the Project Navigator and verify the deployment target matches that of your application target.
- Next, select your application project in the Project Navigator (blue project icon) to navigate to the target configuration window and select the application target under the "Targets" heading in the sidebar.
- In the tab bar at the top of that window, open the "General" panel.
- Click on the `+` button under the "Embedded Binaries" section.
- You will see two different `Nuke.xcodeproj` folders each with two different versions of the `Nuke.framework` nested inside a `Products` folder.

> It does not matter which `Products` folder you choose from, but it does matter whether you choose the top or bottom `Nuke.framework`.

- Select the top `Nuke.framework` for iOS and the bottom one for OS X.

> You can verify which one you selected by inspecting the build log for your project. The build target for `Nuke` will be listed as either `Nuke iOS`, `Nuke macOS`, `Nuke tvOS` or `Nuke watchOS`.

- And that's it!

> The `Nuke.framework` is automagically added as a target dependency, linked framework and embedded framework in a copy files build phase which is all you need to build on the simulator and a device.
