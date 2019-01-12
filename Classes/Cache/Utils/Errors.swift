//
//  Errors.swift
//  Dehancer Desktop
//
//  Created by denn on 08/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Cocoa

extension Never: Error {}

/// Represents all the errors which can happen in Kingfisher framework.
/// Kingfisher related methods always throw a `KingfisherError` or invoke the callback with `KingfisherError`
/// as its error type. To handle errors from Kingfisher, you switch over the error to get a reason catalog,
/// then switch over the reason to know error detail.
public enum DehancerError: Error {
    
    /// Represents the error reason during Kingfisher caching system.
    ///
    /// - fileEnumeratorCreationFailed: Cannot create a file enumerator for a certain disk URL. Code 3001.
    /// - invalidFileEnumeratorContent: Cannot get correct file contents from a file enumerator. Code 3002.
    /// - invalidURLResource: The file at target URL exists, but its URL resource is unavailable. Code 3003.
    /// - cannotLoadDataFromDisk: The file at target URL exists, but the data cannot be loaded from it. Code 3004.
    /// - cannotCreateDirectory: Cannot create a folder at a given path. Code 3005.
    /// - imageNotExisting: The requested image does not exist in cache. Code 3006.
    /// - cannotConvertToData: Cannot convert an object to data for storing. Code 3007.
    /// - cannotSerializeImage: Cannot serialize an image to data for storing. Code 3008.
    public enum CacheErrorReason {
        
        /// Cannot create a file enumerator for a certain disk URL. Code 3001.
        /// - url: The target disk URL from which the file enumerator should be created.
        case fileEnumeratorCreationFailed(url: URL)
        
        /// Cannot get correct file contents from a file enumerator. Code 3002.
        /// - url: The target disk URL from which the content of a file enumerator should be got.
        case invalidFileEnumeratorContent(url: URL)
        
        /// The file at target URL exists, but its URL resource is unavailable. Code 3003.
        /// - error: The underlying error thrown by file manager.
        /// - key: The key used to getting the resource from cache.
        /// - url: The disk URL where the target cached file exists.
        case invalidURLResource(error: Error, key: String, url: URL)
        
        /// The file at target URL exists, but the data cannot be loaded from it. Code 3004.
        /// - url: The disk URL where the target cached file exists.
        /// - error: The underlying error which describes why this error happens.
        case cannotLoadDataFromDisk(url: URL, error: Error)
        
        /// Cannot create a folder at a given path. Code 3005.
        /// - path: The disk path where the directory creating operation fails.
        /// - error: The underlying error which describes why this error happens.
        case cannotCreateDirectory(path: String, error: Error)
        
        /// The requested image does not exist in cache. Code 3006.
        /// - key: Key of the requested image in cache.
        case imageNotExisting(key: String)
        
        /// Cannot convert an object to data for storing. Code 3007.
        /// - object: The object which needs be convert to data.
        case cannotConvertToData(object: Any, error: Error)
        
        /// Cannot serialize an image to data for storing. Code 3008.
        /// - image: The input image needs to be serialized to cache.
        /// - original: The original image data, if exists.
        /// - serializer: The `CacheSerializer` used for the image serializing.
        case cannotSerializeImage(image: Any?, original: Any?)
    }
    
    
    // MARK: Member Cases
    
    /// Represents the error reason during Kingfisher caching system.
    case cacheError(reason: CacheErrorReason)
}


extension DehancerError.CacheErrorReason {
    
    var errorDescription: String? {
        switch self {
        case .fileEnumeratorCreationFailed(let url):
            return "Cannot create file enumerator for URL: \(url)."
        case .invalidFileEnumeratorContent(let url):
            return "Cannot get contents from the file enumerator at URL: \(url)."
        case .invalidURLResource(let error, let key, let url):
            return "Cannot get URL resource values or data for the given URL: \(url). " +
            "Cache key: \(key). Underlying error: \(error)"
        case .cannotLoadDataFromDisk(let url, let error):
            return "Cannot load data from disk at URL: \(url). Underlying error: \(error)"
        case .cannotCreateDirectory(let path, let error):
            return "Cannot create directory at given path: Path: \(path). Underlying error: \(error)"
        case .imageNotExisting(let key):
            return "The image is not in cache, but you requires it should only be " +
            "from cache by enabling the `.onlyFromCache` option. Key: \(key)."
        case .cannotConvertToData(let object, let error):
            return "Cannot convert the input object to a `Data` object when storing it to disk cache. " +
            "Object: \(object). Underlying error: \(error)"
        case .cannotSerializeImage(let image, let originalData):
            return "Cannot serialize an image due to the cache serializer returning `nil`. " +
            "Image: \(String(describing:image)), original data: \(String(describing: originalData))."
        }
    }
    
    var errorCode: Int {
        switch self {
        case .fileEnumeratorCreationFailed: return 3001
        case .invalidFileEnumeratorContent: return 3002
        case .invalidURLResource: return 3003
        case .cannotLoadDataFromDisk: return 3004
        case .cannotCreateDirectory: return 3005
        case .imageNotExisting: return 3006
        case .cannotConvertToData: return 3007
        case .cannotSerializeImage: return 3008
        }
    }
}
