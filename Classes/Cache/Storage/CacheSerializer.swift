//
//  CacheSerializer.swift
//  Dehancer Desktop
//
//  Created by denn on 08/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Cocoa

/// An `CacheSerializer` is used to convert some data to an image object after
/// retrieving it from disk storage, and vice versa, to convert an image to data object
/// for storing to the disk storage.
public protocol CacheSerializer: CacheCostCalculable {
    
    associatedtype Image
    associatedtype ImageData

    /// Gets the serialized data from a provided image
    /// and optional original data for caching to disk.
    ///
    /// - Parameters:
    ///   - image: The image needed to be serialized.
    ///   - original: The original data which is just downloaded.
    ///               If the image is retrieved from cache instead of
    ///               downloaded, it will be `nil`.
    /// - Returns: The data object for storing to disk, or `nil` when no valid
    ///            data could be serialized.
    static func data<Image,ImageData>(with image: Image, original: ImageData?) -> ImageData?
    
    /// Gets an image from provided serialized data.
    ///
    /// - Parameters:
    ///   - data: The data from which an image should be deserialized.
    /// - Returns: An image deserialized or `nil` when no valid image
    ///            could be deserialized.
    static func image<Image,ImageData>(with data: ImageData) -> Image?
}
