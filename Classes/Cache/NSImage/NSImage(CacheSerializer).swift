//
//  NSImage(CacheSerializer).swift
//  Dehancer Desktop
//
//  Created by denn on 09/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Cocoa

extension NSImage: CacheCostCalculable {
    /// Cost of an image
    public var cacheCost: Int { return cost }
    
    // Bitmap memory cost with bytes.
    var cost: Int {
        let pixel = Int(size.width * size.height)
        guard let cgImage = cgImage else {
            return pixel * 4
        }
        return pixel * cgImage.bitsPerPixel / 8
    }
    
    var cgImage: CGImage? {
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    func jpegRepresentation(compression: Float) -> Data? {
        guard let cgImage = cgImage else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using:.jpeg, properties: [.compressionFactor: compression])
    }
}

/// Represents a basic and default `CacheSerializer` used in Dehancer disk cache system.
extension NSImage: CacheSerializer {
    
    public typealias Image = NSImage
    public typealias ImageData = Data

    /// - Parameters:
    ///   - image: The image needed to be serialized.
    ///   - original: The original data which is just downloaded.
    ///               If the image is retrieved from cache instead of
    ///               downloaded, it will be `nil`.
    /// - Returns: The data object for storing to disk, or `nil` when no valid
    ///            data could be serialized.
    ///
    /// - Note:
    /// Only when `original` contains valid PNG, JPEG and GIF format data, the `image` will be
    /// converted to the corresponding data type. Otherwise, if the `original` is provided but it is not
    /// a valid format, the `original` data will be used for cache.
    ///
    /// If `original` is `nil`, the input `image` will be encoded as PNG data.
    static public func data<Image,ImageData>(with image: Image, original: ImageData?) -> ImageData? {
        return ((original as? Data) ?? (image as? NSImage)?.jpegRepresentation(compression: 1)) as? ImageData
    }
    
    /// Gets an image deserialized from provided data.
    ///
    /// - Parameters:
    ///   - data: The data from which an image should be deserialized.
    ///   - options: Options for deserialization.
    /// - Returns: An image deserialized or `nil` when no valid image
    ///            could be deserialized.
    static public func image<Image,ImageData>(with data: ImageData) -> Image? {
        return NSImage(data: data as! Data) as? Image
    }
}
