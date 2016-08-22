// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    private func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        return true
    }
}

private let host = "https://cloud.githubusercontent.com/assets"
let demoPhotosURLs = [
    URL(string: "\(host)/1567433/9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997.jpg")!,
    URL(string: "\(host)/1567433/9781832/0719dd5e-57a1-11e5-9324-9764de25ed47.jpg")!,
    URL(string: "\(host)/1567433/9781833/09021316-57a1-11e5-817b-85b57a2a8a77.jpg")!,
    URL(string: "\(host)/1567433/9781834/0931ad74-57a1-11e5-9080-c8f6ecea19ce.jpg")!,
    URL(string: "\(host)/1567433/9781838/0e6274f4-57a1-11e5-82fd-872e735eea73.jpg")!,
    URL(string: "\(host)/1567433/9781839/0e63ad92-57a1-11e5-8841-bd3c5ea1bb9c.jpg")!,
    URL(string: "\(host)/1567433/9781843/0f4064b2-57a1-11e5-9fb7-f258e81a4214.jpg")!,
    URL(string: "\(host)/1567433/9781840/0e95f978-57a1-11e5-8179-36dfed72f985.jpg")!,
    URL(string: "\(host)/1567433/9781841/0e96b5fc-57a1-11e5-82ae-699b113bb85a.jpg")!,
    URL(string: "\(host)/1567433/9781894/839cf99c-57a1-11e5-9602-d56d99a31abc.jpg")!,
    URL(string: "\(host)/1567433/9781896/83c5e1f4-57a1-11e5-9961-97730da2a7ad.jpg")!,
    URL(string: "\(host)/1567433/9781897/83c622cc-57a1-11e5-98dd-3a7d54b60170.jpg")!,
    URL(string: "\(host)/1567433/9781900/83cbc934-57a1-11e5-8152-e9ecab92db75.jpg")!,
    URL(string: "\(host)/1567433/9781899/83cb13a4-57a1-11e5-88c4-48feb134a9f0.jpg")!,
    URL(string: "\(host)/1567433/9781898/83c85ba0-57a1-11e5-8569-778689bff1ed.jpg")!,
    URL(string: "\(host)/1567433/9781895/83b7f3fa-57a1-11e5-8579-e2fd6098052d.jpg")!,
    URL(string: "\(host)/1567433/9781901/83d5d500-57a1-11e5-9894-78467657874c.jpg")!,
    URL(string: "\(host)/1567433/9781902/83df3b72-57a1-11e5-82b0-e6eb08915402.jpg")!,
    URL(string: "\(host)/1567433/9781903/83e400bc-57a1-11e5-881d-c0ed2c5136f6.jpg")!,
    URL(string: "\(host)/1567433/9781964/f4553bea-57a1-11e5-9abf-f23470a5efc1.jpg")!,
    URL(string: "\(host)/1567433/9781955/f3b2ed18-57a1-11e5-8fc7-0579e44de0b0.jpg")!,
    URL(string: "\(host)/1567433/9781959/f3b7e624-57a1-11e5-8982-8017f53a4898.jpg")!,
    URL(string: "\(host)/1567433/9781957/f3b52e98-57a1-11e5-9f1a-8741acddb12d.jpg")!,
    URL(string: "\(host)/1567433/9781958/f3b5544a-57a1-11e5-880a-478507b2e189.jpg")!,
    URL(string: "\(host)/1567433/9781956/f3b35082-57a1-11e5-9d2f-2c364e3f9b68.jpg")!,
    URL(string: "\(host)/1567433/9781963/f3da11b8-57a1-11e5-838e-c75e6b00f33e.jpg")!,
    URL(string: "\(host)/1567433/9781961/f3d865de-57a1-11e5-87fd-bb8f28515a16.jpg")!,
    URL(string: "\(host)/1567433/9781960/f3d7f306-57a1-11e5-833f-f3802344619e.jpg")!,
    URL(string: "\(host)/1567433/9781962/f3d98c20-57a1-11e5-838e-10f9d20fbc9b.jpg")!,
    URL(string: "\(host)/1567433/9781982/2b67875a-57a2-11e5-91b2-ec4ca2a65674.jpg")!,
    URL(string: "\(host)/1567433/9781985/2b92e576-57a2-11e5-955f-73889423b552.jpg")!,
    URL(string: "\(host)/1567433/9781986/2b94c288-57a2-11e5-8ebd-4cc107444e70.jpg")!,
    URL(string: "\(host)/1567433/9781987/2b94ba72-57a2-11e5-8259-8d4b5fce1f6c.jpg")!,
    URL(string: "\(host)/1567433/9781984/2b9244ea-57a2-11e5-89b1-edc6922d1909.jpg")!,
    URL(string: "\(host)/1567433/9781988/2b94f32a-57a2-11e5-94f6-2c68c15f711f.jpg")!,
    URL(string: "\(host)/1567433/9781983/2b80e9ca-57a2-11e5-9a90-54884428affe.jpg")!,
    URL(string: "\(host)/1567433/9781989/2b9d462e-57a2-11e5-8c5c-d005e79e0070.jpg")!,
    URL(string: "\(host)/1567433/9781990/2babeeae-57a2-11e5-828d-6c050683274d.jpg")!,
    URL(string: "\(host)/1567433/9781991/2bb13a94-57a2-11e5-8a70-1d7e519c1631.jpg")!,
    URL(string: "\(host)/1567433/9781992/2bb2161c-57a2-11e5-8715-9b7d2df58708.jpg")!,
    URL(string: "\(host)/1567433/9781993/2bb397a8-57a2-11e5-853d-4d4f1854d1fe.jpg")!,
    URL(string: "\(host)/1567433/9781994/2bb61e88-57a2-11e5-8e45-bc2ed096cf97.jpg")!,
    URL(string: "\(host)/1567433/9781995/2bbdf73e-57a2-11e5-8847-afb709e28495.jpg")!,
    URL(string: "\(host)/1567433/9781996/2bc90a66-57a2-11e5-9154-6cc3a08a3e93.jpg")!,
    URL(string: "\(host)/1567433/9782000/2bd232a8-57a2-11e5-8617-eaff327b927f.jpg")!,
    URL(string: "\(host)/1567433/9781997/2bced964-57a2-11e5-9021-970f1f92608e.jpg")!,
    URL(string: "\(host)/1567433/9781998/2bd0def8-57a2-11e5-850f-e60701db4f62.jpg")!,
    URL(string: "\(host)/1567433/9781999/2bd2551c-57a2-11e5-82e3-54bb80f7c114.jpg")!,
    URL(string: "\(host)/1567433/9782001/2bdb5bb2-57a2-11e5-8a18-05fe673e2315.jpg")!,
    URL(string: "\(host)/1567433/9782002/2be52ed0-57a2-11e5-8e12-2f6e17787553.jpg")!,
    URL(string: "\(host)/1567433/9782003/2bed36de-57a2-11e5-9d4f-7c214e828fe6.jpg")!,
    URL(string: "\(host)/1567433/9782004/2bef8ed4-57a2-11e5-8949-26e1b80a0ebb.jpg")!,
    URL(string: "\(host)/1567433/9782005/2bf08622-57a2-11e5-86e2-c5d71ef615e9.jpg")!,
    URL(string: "\(host)/1567433/9782006/2bf2d968-57a2-11e5-8f44-3cd169219e78.jpg")!,
    URL(string: "\(host)/1567433/9782007/2bf5e95a-57a2-11e5-9b7a-96f355a5334b.jpg")!,
    URL(string: "\(host)/1567433/9782008/2c04b458-57a2-11e5-9381-feb4ae365a1d.jpg")!,
    URL(string: "\(host)/1567433/9782011/2c0e4054-57a2-11e5-89f0-7c91bb0e01a2.jpg")!,
    URL(string: "\(host)/1567433/9782009/2c0c4254-57a2-11e5-984d-0e44cc762219.jpg")!,
    URL(string: "\(host)/1567433/9782010/2c0ca730-57a2-11e5-834c-79153b496d44.jpg")!,
    URL(string: "\(host)/1567433/9782012/2c1277e6-57a2-11e5-862a-ec0c8fad727a.jpg")!,
    URL(string: "\(host)/1567433/9782122/543bc690-57a3-11e5-83eb-156108681377.jpg")!,
    URL(string: "\(host)/1567433/9782128/546af1f4-57a3-11e5-8ad6-78527accf642.jpg")!,
    URL(string: "\(host)/1567433/9782127/546ae2cc-57a3-11e5-9ad5-f0c7157eda5b.jpg")!,
    URL(string: "\(host)/1567433/9782124/5468528c-57a3-11e5-9cf9-89f763b473b4.jpg")!,
    URL(string: "\(host)/1567433/9782126/5468cf50-57a3-11e5-9d97-c8fc94e7b9a4.jpg")!,
    URL(string: "\(host)/1567433/9782125/54687d66-57a3-11e5-860f-c66597fd212c.jpg")!,
    URL(string: "\(host)/1567433/9782123/545728cc-57a3-11e5-83ab-51462737c19d.jpg")!,
    URL(string: "\(host)/1567433/9782129/54737694-57a3-11e5-9e1e-b626db67e625.jpg")!,
    URL(string: "\(host)/1567433/9782130/5483fee2-57a3-11e5-8928-e7706c765016.jpg")!,
    URL(string: "\(host)/1567433/9782133/54dd0c62-57a3-11e5-85ee-a02c1b9dd223.jpg")!,
    URL(string: "\(host)/1567433/9782131/54872b30-57a3-11e5-8903-db1f81ea1abb.jpg")!,
    URL(string: "\(host)/1567433/9782132/548a3b9a-57a3-11e5-8228-8ee523e7809e.jpg")!
]

