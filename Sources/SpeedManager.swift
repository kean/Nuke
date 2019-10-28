//
//  SpeedManager.swift
//  Nuke
//
//  Created by AbdallahNh on 10/28/19.
//  Copyright © 2019 Alexander Grebenyuk. All rights reserved.
//

import Foundation
public final class SpeedManager{
    var startTime: CFAbsoluteTime!
    var stopTime: CFAbsoluteTime!
    var bytesReceived: Int!
    public static var downloadSpeed = 100.0
    init(){
        startTime = CFAbsoluteTimeGetCurrent()
        stopTime = startTime
        bytesReceived = 0
    }

    func update(with data: Data?, didCompleteWithError error: Error? ){
        if let data = data{
            bytesReceived! += data.count
            stopTime = CFAbsoluteTimeGetCurrent()
            return
        }
        let elapsed = stopTime - startTime

        if let aTempError = error as NSError?, aTempError.domain != NSURLErrorDomain && aTempError.code != NSURLErrorTimedOut && elapsed == 0  {
            return
        }
        SpeedManager.downloadSpeed = elapsed != 0 ? Double(bytesReceived) / elapsed / 1024.0 / 1024.0 : -1
    }
}
