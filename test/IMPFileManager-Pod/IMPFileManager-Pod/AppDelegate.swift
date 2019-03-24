//
//  AppDelegate.swift
//  IMPFileManager-Pod
//
//  Created by denn on 12/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Cocoa
import IMPFileManager

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!

    let cache = NSImageCache(id: "test-cache")

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        
        let image = NSImage(named: "image")!
        
        let date = cache.modificationAt(forKey: "1", id: "thumb")

        debugPrint(" ### date: ", date, cache.isCached(forKey: "1", id: "thumb"))
        
        cache.store(image, forKey: "1", id: "thumb") { result in
            switch result.memoryCacheResult {
            case .failure(let error):
                debugPrint(" ... error memory: ", error)
            default:
                break
            }
            
            switch result.diskCacheResult {
            case .failure(let error):
                debugPrint(" ... error memory: ", error)
            default:
                break
            }
        }
        
        debugPrint(" ### date after: ", cache.modificationAt(forKey: "1", id: "thumb"))

        
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}

