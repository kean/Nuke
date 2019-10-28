//
//  SpeedManager.swift
//  Nuke
//
//  Created by AbdallahNh on 10/28/19.
//  Copyright © 2019 Alexander Grebenyuk. All rights reserved.
//

import Foundation
/// Provides Last downloaded speed.
public final class SpeedManager{
    var startTime: CFAbsoluteTime!
    var stopTime: CFAbsoluteTime!
    var bytesReceived: Int!
    public static var downloadSpeed = 100.0 // start with heighest speed
    init(){
        startTime = CFAbsoluteTimeGetCurrent()
        stopTime = startTime
        bytesReceived = 0
    }
    /// - parameter data: Downloaded data
    /// - parameter didCompleteWithError: Catch error in downloading data
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
