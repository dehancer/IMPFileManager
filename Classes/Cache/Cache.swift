//
//  Cache.swift
//  Dehancer Desktop
//
//  Created by denn on 08/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//
//  Based on Kingfisher
//  Created by Wei Wang on 15/4/6.
//  Copyright (c) 2019 Wei Wang <onevcat@gmail.com>
//

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Notification.Name {
    /// This notification will be sent when the disk cache got cleaned either there are cached files expired or the
    /// total size exceeding the max allowed size. The manually invoking of `clearDiskCache` method will not trigger
    /// this notification.
    ///
    /// The `object` of this notification is the `Cache` object which sends the notification.
    /// A list of removed hashes (files) could be retrieved by accessing the array under
    /// `DiskCacheCleanedHashKey` key in `userInfo` of the notification object you received.
    /// By checking the array, you could know the hash codes of files are removed.
    public static let DidCleanDiskCache =
        Notification.Name("com.dehancer.desktop.DidCleanDiskCache")
}

/// Key for array of cleaned hashes in `userInfo` of `DidCleanDiskCacheNotification`.
public let DiskCacheCleanedHashKey = "com.dehancer.desktop.cleanedHash"

/// Cache type of a cached image.
/// - none: The image is not cached yet when retrieving it.
/// - memory: The image is cached in memory.
/// - disk: The image is cached in disk.
public enum CacheType {
    /// The image is not cached yet when retrieving it.
    case none
    /// The image is cached in memory.
    case memory
    /// The image is cached in disk.
    case disk
    
    /// Whether the cache type represents the image is already cached or not.
    public var cached: Bool {
        switch self {
        case .memory, .disk: return true
        case .none: return false
        }
    }
}

/// Represents types which cost in memory can be calculated.
public protocol CacheCostCalculable {
    var cacheCost: Int { get }
}

/// Represents the caching operation result.
public struct CacheStoreResult {
    /// The cache result for memory cache. Caching an image to memory will never fail.
    public let memoryCacheResult: Result<(), Never>
    
    /// The cache result for disk cache. If an error happens during caching operation,
    /// you can get it from `.failure` case of this `diskCacheResult`.
    public let diskCacheResult: Result<(), DehancerError>
}

/// Represents the getting image operation from the cache.
///
/// - disk: The object can be retrieved from disk cache.
/// - memory: The object can be retrieved memory cache.
/// - none: The object does not exist in the cache.
public enum CacheResult<Object> {
    
    /// The image can be retrieved from disk cache.
    case disk(Object)
    
    /// The image can be retrieved memory cache.
    case memory(Object)
    
    /// The image does not exist in the cache.
    case none
    
    /// Extracts the image from cache result. It returns the associated `Image` value for
    /// `.disk` and `.memory` case. For `.none` case, `nil` is returned.
    public var image: Object? {
        switch self {
        case .disk(let image): return image
        case .memory(let image): return image
        case .none: return nil
        }
    }
    
    /// Returns the corresponding `CacheType` value based on the result type of `self`.
    public var cacheType: CacheType {
        switch self {
        case .disk: return .disk
        case .memory: return .memory
        case .none: return .none
        }
    }
}

/// Represents a hybrid caching system which is composed by a `MemoryStorage.Backend` and a `DiskStorage.Backend`.
/// `Cache` is a high level abstract for storing an object as well as its data to disk memory and disk, and
/// retrieving them back.
///
/// While a default object cache object will be used if you prefer the extension methods of Dehancer, you can create
/// your own cache object and configure its storages as your need. This class also provide an interface for you to set
/// the memory and disk storage config.
open class Cache<Object:CacheSerializer,ObjectData:DataTransformable> {
    
    // MARK: Singleton
    /// The default `Cache` object. Dehancer will use this cache for its related methods if there is no
    /// other cache specified. The `name` of this default cache is "default", and you should not use this name
    /// for any of your customize cache.
    //public static let `default` = Cache<NSImage,Data>(id: "default")
    
    // MARK: Public Properties
    /// The `MemoryStorage.Backend` object used in this cache. This storage holds loaded images in memory with a
    /// reasonable expire duration and a maximum memory usage. To modify the configuration of a storage, just set
    /// the storage `config` and its properties.
    public let memoryStorage: MemoryStorage.Backend<Object>
    
    /// The `DiskStorage.Backend` object used in this cache. This storage stores loaded objects in disk with a
    /// reasonable expire duration and a maximum disk usage. To modify the configuration of a storage, just set
    /// the storage `config` and its properties.
    public let diskStorage: DiskStorage.Backend<ObjectData>
    
    private let ioQueue: DispatchQueue
        
    // MARK: Initializers
    
    /// Creates an `Cache` from a customized `MemoryStorage` and `DiskStorage`.
    ///
    /// - Parameters:
    ///   - memoryStorage: The `MemoryStorage.Backend` object to use in the object cache.
    ///   - diskStorage: The `DiskStorage.Backend` object to use in the object cache.
    public init(
        memoryStorage: MemoryStorage.Backend<Object>,
        diskStorage: DiskStorage.Backend<ObjectData>)
    {
        self.memoryStorage = memoryStorage
        self.diskStorage = diskStorage
        let ioQueueName = "com.dehancer.desktop.objectCache.ioQueue.\(UUID().uuidString)"
        ioQueue = DispatchQueue(label: ioQueueName)
        
        #if !os(macOS) && !os(watchOS)
        #if swift(>=4.2)
        let notifications: [(Notification.Name, Selector)] = [
            (UIApplication.didReceiveMemoryWarningNotification, #selector(clearMemoryCache)),
            (UIApplication.willTerminateNotification, #selector(cleanExpiredDiskCache)),
            (UIApplication.didEnterBackgroundNotification, #selector(backgroundCleanExpiredDiskCache))
        ]
        #else
        let notifications: [(Notification.Name, Selector)] = [
        (NSNotification.Name.UIApplicationDidReceiveMemoryWarning, #selector(clearMemoryCache)),
        (NSNotification.Name.UIApplicationWillTerminate, #selector(cleanExpiredDiskCache)),
        (NSNotification.Name.UIApplicationDidEnterBackground, #selector(backgroundCleanExpiredDiskCache))
        ]
        #endif
        notifications.forEach {
            NotificationCenter.default.addObserver(self, selector: $0.1, name: $0.0, object: nil)
        }
        #endif
    }
    
    /// Creates an `Cache` with a given `name`. Both `MemoryStorage` and `DiskStorage` will be created
    /// with a default config based on the `name`.
    ///
    /// - Parameter id: The name of cache object. It is used to setup disk cache directories and IO queue.
    ///                   You should not use the same `name` for different caches, otherwise, the disk storage would
    ///                   be conflicting to each other. The `name` should not be an empty string.
    public convenience init(id: String) {
        try! self.init(id: id, path: nil)
    }
    
    /// Creates an `Cache` with a given `name`, cache directory `path`
    /// and a closure to modify the cache directory.
    ///
    /// - Parameters:
    ///   - name: The name of cache object. It is used to setup disk cache directories and IO queue.
    ///           You should not use the same `name` for different caches, otherwise, the disk storage would
    ///           be conflicting to each other.
    ///   - path: Location of cache path on disk. It will be internally pass to the initializer of `DiskStorage` as the
    ///           disk cache directory.
    /// - Throws: An error that happens during image cache creating, such as unable to create a directory at the given
    ///           path.
    public convenience init(
        id: String,
        path: String? = nil) throws
    {
        
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let costLimit = totalMemory / 8
        let memoryStorage = MemoryStorage.Backend<Object>(config:
            .init(totalCostLimit: (costLimit > Int.max) ? Int.max : Int(costLimit)))
        
        let diskConfig = DiskStorage.Config(
            id: id,
            sizeLimit: 0,
            directory: (path != nil) ? URL(fileURLWithPath: path!, isDirectory: true) : nil)
        
        let diskStorage = try DiskStorage.Backend<ObjectData>(config: diskConfig)
        
        self.init(memoryStorage: memoryStorage, diskStorage: diskStorage)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Storing Images
    
    /// Store image to cache
    ///
    /// - Parameters:
    ///   - image: NSImage object
    ///   - original: keep Data instead of the image
    ///   - key: storage key
    ///   - id:image id for the key
    ///   - toDisk: save image to disk cache
    ///   - callbackQueue: current queue context
    ///   - completionHandler: handle completition
    open func store(_ image: Object,
                    original: ObjectData? = nil,
                    forKey key: String,
                    id: String,
                    toDisk: Bool = true,
                    callbackQueue: CallbackQueue = .mainCurrentOrAsync,
                    completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        let identifier = id
        
        let computedKey = key.computedKey(with: identifier)
        // Memory storage should not throw.
        memoryStorage.storeNoThrow(value: image, forKey: computedKey)
        
        guard toDisk else {
            if let completionHandler = completionHandler {
                let result = CacheStoreResult(memoryCacheResult: .success(()), diskCacheResult: .success(()))
                callbackQueue.execute { completionHandler(result) }
            }
            return
        }
        
        ioQueue.async {
            
            if let data = Object.data(with: image, original: original) {
                self.syncStoreToDisk(
                    data,
                    forKey: key,
                    id: identifier,
                    callbackQueue: callbackQueue,
                    expiration: nil,
                    completionHandler: completionHandler)
            } else {
                guard let completionHandler = completionHandler else { return }
                
                let diskError = DehancerError.cacheError(
                    reason: .cannotSerializeImage(image: image, original: original))
                
                let result = CacheStoreResult(
                    memoryCacheResult: .success(()),
                    diskCacheResult: .failure(diskError))
                callbackQueue.execute { completionHandler(result) }
            }
        }
    }
    
    
    /// Store image to cache
    ///
    /// - Parameters:
    ///   - image: NSImage object
    ///   - key: storage key
    ///   - id: image id for the key
    ///   - completionHandler: handle completition
    open func store(_ image: Object,
                    forKey key: String,
                    id: String,
                    completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        store(image, original: nil,
              forKey: key, id: id,
              toDisk: true, callbackQueue: CallbackQueue.untouch,
              completionHandler: completionHandler)
    }
    
    private func storeToDisk(
        _ data: ObjectData,
        forKey key: String,
        processorIdentifier identifier: String = "",
        expiration: StorageExpiration? = nil,
        callbackQueue: CallbackQueue = .untouch,
        completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        ioQueue.async {
            self.syncStoreToDisk(
                data,
                forKey: key,
                id: identifier,
                callbackQueue: callbackQueue,
                expiration: expiration,
                completionHandler: completionHandler)
        }
    }
    
    private func syncStoreToDisk(
        _ data: ObjectData,
        forKey key: String,
        id identifier: String = "",
        callbackQueue: CallbackQueue = .untouch,
        expiration: StorageExpiration? = nil,
        completionHandler: ((CacheStoreResult) -> Void)? = nil)
    {
        let computedKey = key.computedKey(with: identifier)
        let result: CacheStoreResult
        do {
            try self.diskStorage.store(value: data, forKey: computedKey, expiration: expiration)
            result = CacheStoreResult(memoryCacheResult: .success(()), diskCacheResult: .success(()))
        } catch {
            let diskError: DehancerError
            if let error = error as? DehancerError {
                diskError = error
            } else {
                diskError = .cacheError(reason: .cannotConvertToData(object: data, error: error))
            }
            
            result = CacheStoreResult(
                memoryCacheResult: .success(()),
                diskCacheResult: .failure(diskError)
            )
        }
        if let completionHandler = completionHandler {
            callbackQueue.execute { completionHandler(result) }
        }
    }
    
    // MARK: Removing Images
    
    /// Removes the image for the given key from the cache.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: The identifier of processor being used for caching. If you are using a processor for the
    ///                 image, pass the identifier of processor to this parameter.
    ///   - fromMemory: Whether this image should be removed from memory storage or not.
    ///                 If `false`, the image won't be removed from the memory storage. Default is `true`.
    ///   - fromDisk: Whether this image should be removed from disk storage or not.
    ///               If `false`, the image won't be removed from the disk storage. Default is `true`.
    ///   - callbackQueue: The callback queue on which `completionHandler` is invoked. Default is `.untouch`.
    ///   - completionHandler: A closure which is invoked when the cache removing operation finishes.
    open func remove(forKey key: String,
                     id identifier: String,
                     fromMemory: Bool = true,
                     fromDisk: Bool = true,
                     callbackQueue: CallbackQueue = .untouch,
                     completionHandler: (() -> Void)? = nil)
    {
        let computedKey = key.computedKey(with: identifier)
        
        if fromMemory {
            try? memoryStorage.remove(forKey: computedKey)
        }
        
        if fromDisk {
            ioQueue.async{
                try? self.diskStorage.remove(forKey: computedKey)
                if let completionHandler = completionHandler {
                    callbackQueue.execute { completionHandler() }
                }
            }
        } else {
            if let completionHandler = completionHandler {
                callbackQueue.execute { completionHandler() }
            }
        }
    }
    
    open func modificationAt(forKey key: String, id identifier: String) -> Date? {       
        return createdAtMemoryCache(forKey: key, id: identifier) ?? modificationDateInDiskCache(forKey: key, id: identifier)
    }
    
    open func retrieve(forKey key: String,
                       id identifier: String,
                       callbackQueue: CallbackQueue = .untouch,
                       completionHandler: ((Result<CacheResult<Object>, DehancerError>) -> Void)?)
    {
        // No completion handler. No need to start working and early return.
        guard let completionHandler = completionHandler else { return }
        
        // Try to check the image from memory cache first.
        if let image = retrieveImageInMemoryCache(forKey: key, id: identifier) {
            callbackQueue.execute { completionHandler(.success(.memory(image))) }
        }
        else {
            // Begin to disk search.
            self.retrieveImageInDiskCache(forKey: key, id: identifier, callbackQueue: callbackQueue) {
                result in
                // The callback queue is already correct in this closure.
                switch result {
                case .success(let image):
                    
                    guard let image = image else {
                        // No image found in disk storage.
                        completionHandler(.success(.none))
                        return
                    }
                    
                    let finalImage = image
                    // Cache the disk image to memory.
                    // We are passing `false` to `toDisk`, the memory cache does not change
                    // callback queue, we can call `completionHandler` without another dispatch.
                    self.store(
                        finalImage,
                        forKey: key,
                        id: identifier,
                        toDisk: false,
                        callbackQueue: .untouch)
                    {
                        _ in
                        completionHandler(.success(.disk(finalImage)))
                    }
                case .failure(let error):
                    completionHandler(.failure(error))
                }
            }
        }
    }
    
    // MARK: Getting Images
    
    private func createdAtMemoryCache( forKey key: String, id identifier: String = "") -> Date?
    {
        do {
            return try memoryStorage.createdAt(forKey: key.computedKey(with: identifier))
        }
        catch { return nil }
    }

    private func modificationDateInDiskCache(forKey key: String, id identifier: String = "")  -> Date?
    {
        do {
            return try self.diskStorage.modificationDate(forKey:  key.computedKey(with: identifier))
        }
        catch {return nil}
    }
    
    private func retrieveImageInMemoryCache( forKey key: String, id identifier: String = "") -> Object?
    {
        let computedKey = key.computedKey(with: identifier)
        do {
            return try memoryStorage.value(forKey: computedKey)
        } catch {
            return nil
        }
    }
    
    private func retrieveImageInDiskCache(
        forKey key: String,
        id identifier: String = "",
        callbackQueue: CallbackQueue = .untouch,
        completionHandler: @escaping (Result<Object?, DehancerError>) -> Void)
    {
        let computedKey = key.computedKey(with: identifier)
        let loadingQueue: CallbackQueue = .dispatch(ioQueue)
        loadingQueue.execute {
            do {
                var image: Object? = nil
                if let data = try self.diskStorage.value(forKey: computedKey) {
                    image = Object.image(with: try data.toData())
                }
                callbackQueue.execute { completionHandler(.success(image)) }
            } catch {
                if let error = error as? DehancerError {
                    callbackQueue.execute { completionHandler(.failure(error)) }
                } else {
                    assertionFailure("The internal thrown error should be a `DehancerError`.")
                }
            }
        }
    }
    
    
    // MARK: Cleaning
    /// Clears the memory storage of this cache.
    @objc public func clearMemoryCache() {
        try? memoryStorage.removeAll()
    }
    
    /// Clears the disk storage of this cache. This is an async operation.
    ///
    /// - Parameter handler: A closure which is invoked when the cache clearing operation finishes.
    ///                      This `handler` will be called from the main queue.
    open func clearDiskCache(completion handler: (()->())? = nil) {
        ioQueue.async {
            do {
                try self.diskStorage.removeAll()
            } catch _ { }
            if let handler = handler {
                DispatchQueue.main.async { handler() }
            }
        }
    }
    
    /// Clears the expired images from disk storage. This is an async operation.
    open func cleanExpiredMemoryCache() {
        memoryStorage.removeExpired()
    }
    
    /// Clears the expired images from disk storage. This is an async operation.
    @objc private func cleanExpiredDiskCache() {
        cleanExpiredDiskCache(completion: nil)
    }
    
    /// Clears the expired images from disk storage. This is an async operation.
    ///
    /// - Parameter handler: A closure which is invoked when the cache clearing operation finishes.
    ///                      This `handler` will be called from the main queue.
    open func cleanExpiredDiskCache(completion handler: (() -> Void)? = nil) {
        ioQueue.async {
            do {
                var removed: [URL] = []
                let removedExpired = try self.diskStorage.removeExpiredValues()
                removed.append(contentsOf: removedExpired)
                
                let removedSizeExceeded = try self.diskStorage.removeSizeExceededValues()
                removed.append(contentsOf: removedSizeExceeded)
                
                if !removed.isEmpty {
                    DispatchQueue.main.async {
                        let cleanedHashes = removed.map { $0.lastPathComponent }
                        NotificationCenter.default.post(
                            name: .DidCleanDiskCache,
                            object: self,
                            userInfo: [DiskCacheCleanedHashKey: cleanedHashes])
                    }
                }
                
                if let handler = handler {
                    DispatchQueue.main.async { handler() }
                }
            } catch {}
        }
    }
    
    #if !os(macOS) && !os(watchOS)
    /// Clears the expired images from disk storage when app is in background. This is an async operation.
    /// In most cases, you should not call this method explicitly.
    /// It will be called automatically when `UIApplicationDidEnterBackgroundNotification` received.
    @objc public func backgroundCleanExpiredDiskCache() {
        // if 'sharedApplication()' is unavailable, then return
        guard let sharedApplication = UIApplication.shared else { return }
        
        func endBackgroundTask(_ task: inout UIBackgroundTaskIdentifier) {
            sharedApplication.endBackgroundTask(task)
            #if swift(>=4.2)
            task = UIBackgroundTaskIdentifier.invalid
            #else
            task = UIBackgroundTaskInvalid
            #endif
        }
        
        var backgroundTask: UIBackgroundTaskIdentifier!
        backgroundTask = sharedApplication.beginBackgroundTask {
            endBackgroundTask(&backgroundTask!)
        }
        
        cleanExpiredDiskCache {
            endBackgroundTask(&backgroundTask!)
        }
    }
    #endif
    
    // MARK: Image Cache State
    
    /// Returns the cache type for a given `key` and `identifier` combination.
    /// This method is used for checking whether an image is cached in current cache.
    /// It also provides information on which kind of cache can it be found in the return value.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: A `CacheType` instance which indicates the cache status.
    ///            `.none` means the image is not in cache or it is already expired.
    open func cachedType(
        forKey key: String,
        id identifier: String = "") -> CacheType
    {
        let computedKey = key.computedKey(with: identifier)
        if memoryStorage.isCached(forKey: computedKey) { return .memory }
        if diskStorage.isCached(forKey: computedKey) { return .disk }
        return .none
    }
    
    /// Returns whether the file exists in cache for a given `key` and `identifier` combination.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: A `Bool` which indicates whether a cache could match the given `key` and `identifier` combination.
    ///
    /// - Note:
    /// The return value does not contain information about from which kind of storage the cache matches.
    /// To get the information about cache type according `CacheType`,
    /// use `cachedType(forKey:processorIdentifier:)` instead.
    public func isCached( forKey key: String, id identifier: String = "") -> Bool
    {
        return cachedType(forKey: key, id: identifier).cached
    }
    
    /// Gets the hash used as cache file name for the key.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: The hash which is used as the cache file name.
    ///
    /// - Note:
    /// By default, for a given combination of `key` and `identifier`, `Cache` will use the value
    /// returned by this method as the cache file name. You can use this value to check and match cache file
    /// if you need.
    open func hash( forKey key: String, id identifier: String = "") -> String
    {
        let computedKey = key.computedKey(with: identifier)
        return diskStorage.cacheFileName(forKey: computedKey)
    }
    
    /// Calculates the size taken by the disk storage.
    /// It is the total file size of all cached files in the `diskStorage` on disk in bytes.
    ///
    /// - Parameter handler: Called with the size calculating finishes. This closure is invoked from the main queue.
    open func calculateDiskStorageSize(completion handler: @escaping ((Result<UInt, DehancerError>) -> Void)) {
        ioQueue.async {
            do {
                let size = try self.diskStorage.totalSize()
                DispatchQueue.main.async { handler(.success(size)) }
            } catch {
                if let error = error as? DehancerError {
                    DispatchQueue.main.async { handler(.failure(error)) }
                } else {
                    assertionFailure("The internal thrown error should be a `DehancerError`.")
                }
                
            }
        }
    }
    
    /// Gets the cache path for the key.
    /// It is useful for projects with web view or anyone that needs access to the local file path.
    ///
    /// i.e. Replacing the `<img src='path_for_key'>` tag in your HTML.
    ///
    /// - Parameters:
    ///   - key: The key used for caching the image.
    ///   - identifier: Processor identifier which used for this image. Default is the `identifier` of
    ///                 `DefaultImageProcessor.default`.
    /// - Returns: The disk path of cached image under the given `key` and `identifier`.
    ///
    /// - Note:
    /// This method does not guarantee there is an image already cached in the returned path. It just gives your
    /// the path that the image should be, if it exists in disk storage.
    ///
    /// You could use `isCached(forKey:)` method to check whether the image is cached under that key in disk.
    open func cachePath( forKey key: String, id identifier: String = "") -> String
    {
        let computedKey = key.computedKey(with: identifier)
        return diskStorage.cacheFileURL(forKey: computedKey).path
    }
}

extension Dictionary {
    func keysSortedByValue(_ isOrderedBefore: (Value, Value) -> Bool) -> [Key] {
        return Array(self).sorted{ isOrderedBefore($0.1, $1.1) }.map{ $0.0 }
    }
}

extension String {
    func computedKey(with identifier: String) -> String {
        if identifier.isEmpty {
            return self
        } else {
            return appending("@\(identifier)")
        }
    }
}
