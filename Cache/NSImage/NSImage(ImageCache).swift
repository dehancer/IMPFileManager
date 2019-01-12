//
//  NSImage(ImageCache).swift
//  Dehancer Desktop
//
//  Created by denn on 09/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Cocoa

/// NSImage cache
public class NSImageCache: Cache<NSImage,Data> {
    // MARK: Singleton
    /// The default `ImageCache` object. Dehancer will use this cache for its related methods if there is no
    /// other cache specified. The `name` of this default cache is "default", and you should not use this name
    /// for any of your customize cache.
    public static let `default` = NSImageCache(id: "default")
}
