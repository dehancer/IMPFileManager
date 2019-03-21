//
//  FileTreeItem.swift
//  DehancerUIKit
//
//  Created by denis svinarchuk on 27.09.17.
//

import Foundation

import Cocoa

extension URL {
    
    public var isHidden: Bool {
        get {
            return (try? resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
        }
        set {
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = newValue
            do {
                try setResourceValues(resourceValues)
            } catch {}
        }
    }
    
    public func utiMatched(types:[String]) -> Bool {
        do{
            
            let attr = try resourceValues(forKeys: [.typeIdentifierKey])
            let type = attr.typeIdentifier ?? ""
            var isI = false   
            for t in  types {
                if type.hasSuffix(t){   
                    isI = true
                    break
                }
            }        
            return isI 
        }
        catch {return false }
        
    }
    
    public var isDirectory:Bool {
        do{
            let attr = try resourceValues(forKeys: [.isDirectoryKey,.isApplicationKey,.isReadableKey,.isPackageKey])
            let isD = attr.isDirectory ?? false
            let isA = attr.isApplication ?? false
            let isR = attr.isReadable ?? false
            let isB = attr.isPackage ?? false
            return isD && !isA && isR && !isB 
        }
        catch{return false}  
    }
}

open class FileTreeItem: NSObject, NSCoding{
    
    public enum SortBy:Int {
        case none = 0
        case name = 1
        case creationDate = 2
        case modificationDate = 3
                
        public var name:String {            
            return SortBy.names[self.rawValue]
        }
        
        public static var list:[SortBy] {
            return [.none,.name,.creationDate,.modificationDate]
        }
        
        public static let names:[String] = [
            NSLocalizedString("Sort by ...", comment: ""),
            NSLocalizedString("Sort by Name", comment: ""), 
            NSLocalizedString("Sort by Creation Date", comment: ""),
            NSLocalizedString("Sort by Modification Date", comment: "") 
        ]
    }
    
    public enum SortOrder {
        case ascending
        case descending
    }
        
    public struct ImageType {
        public let type:String
        public let name:String
        public var enabled:Bool                
    }
    
    public static let defaultImageTypes = [
        ImageType(type: "raw-image", name: "RAW", enabled: true),
        ImageType(type: "jpeg", name: "JPEG", enabled: true),
        ImageType(type: "tiff", name: "TIFF", enabled: true),
        ImageType(type: "gif", name: "GIF", enabled: true),
        ImageType(type: "png", name: "PNG", enabled: true),
        ImageType(type: "psd", name: "Photoshop", enabled: true)
    ] 
    
    public var imageTypes:[ImageType] = [ImageType](defaultImageTypes) {
        didSet{
            _imageFilteredUrls = nil
        }
    }
    
    public typealias FileFilterType = ((_ item:FileTreeItem)->Bool)

    public struct  DHCDispatchSemaphore {
        let s = DispatchSemaphore(value: 1)
        init() {}
        func sync<R>(execute: () throws -> R) rethrows -> R {
            _ = s.wait(timeout: DispatchTime.distantFuture)
            defer { s.signal() }
            return try execute()
        }
    }
    
    public enum ItemType {
        case directory
        case image
    }
    
//    override var hashValue: Int {
//        return url.hashValue
//    }
    
    public static func == (lhs: FileTreeItem, rhs: FileTreeItem) -> Bool {
        return lhs.url.path == rhs.url.path
    }
    
    public required init?(coder aDecoder: NSCoder) {
        stateKey = aDecoder.decodeObject(forKey: "stateKey") as? String ?? "DHCFileTreeItem:Shared"
        level = aDecoder.decodeInteger(forKey: "depth")
        if let data = aDecoder.decodeObject(forKey: "parent") as? Data{  
            _parent = NSKeyedUnarchiver.unarchiveObject(with: data) as? FileTreeItem
        }
        _rootPath = (aDecoder.decodeObject(forKey: "rootPath") as? URL) ?? URL(fileURLWithPath: "/", isDirectory: true)
        _relativePath = aDecoder.decodeObject(forKey: "relativePath") as? String ?? ""
        super.init()
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(stateKey, forKey: "stateKey")
        aCoder.encode(level, forKey: "depth")
        if let p = _parent {
            aCoder.encode(NSKeyedArchiver.archivedData(withRootObject: p) , forKey: "parent")
        }
        aCoder.encode(_rootPath, forKey: "rootPath")
        aCoder.encode(_relativePath, forKey: "relativePath")
    }
    
    public override init() { 
        stateKey = "DHCFileTreeItem:Shared"
        level = 0
        super.init()         
    }        
    
    public convenience init(with path:String, parent aParent:FileTreeItem? = nil, state key:String? = nil, level depth:Int? = nil) {
        self.init(with: URL(fileURLWithPath: path, isDirectory: true), parent: aParent, state: key, level: depth)
    }
    
    public init(with url:URL,
                parent aParent:FileTreeItem? = nil,
                state key:String? = nil,
                level depth:Int? = nil,
                sortBy: FileTreeItem.SortBy? = nil) {
        
        stateKey = key ?? "DHCFileTreeItem:Shared"
        
        _realParent = aParent
        
        if let s = sortBy {
            _sortBy = s
        }
        else if let p = _realParent {
            _sortBy = p.sortBy
        }
        
        if let d = depth {
            level = d
            _parent = nil
        }
        else{
            _parent = _realParent
            if _parent == nil {
                level = 0
            }
            else {
                var p = _parent
                var i = 0
                while p != nil {
                    i += 1
                    p = p?._parent
                }
                level = i
            }
        }
        
        _rootPath = url
        _relativePath =  _rootPath.lastPathComponent
        super.init()
    }
    
    private var mutex = DHCDispatchSemaphore()
    
    private static var synchronizationQueue:DispatchQueue = {
        let name = String(format: "org.dehancer.fileitemcache-%08x%08x", arc4random(), arc4random())
        return DispatchQueue(label: name, qos: .utility, attributes: .concurrent)
    }()
    
    public func setCache(key: String, object:Any?, id:String?=nil) {
        FileTreeItem.synchronizationQueue.async(flags: [.barrier]) { [weak self] in
            let k = key + (id ?? "")

            if let o = object {
                FileTreeItem._cache[k] = object!
            }
            else {
                FileTreeItem._cache.removeValue(forKey: k)
            }
        }
    }
    
    public func getCache(key:String, id:String?=nil) -> Any? {
        var obj:Any?
        FileTreeItem.synchronizationQueue.sync { [unowned self] in
            let k = key + (id ?? "")
            obj = FileTreeItem._cache[k]
        }
        return obj
    }
    
    public func invalidateCache() {
         FileTreeItem.synchronizationQueue.sync {
            FileTreeItem._cache.removeAll()
        }
    }
    
    public var userData:Any?
    
    public let stateKey:String
    public let level:Int
    public var icon:NSImage { return NSWorkspace.shared.icon(forFile: url.path) }

    public var uti:String {
        do {
            return try url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier ?? ""
        }
        catch {
            return ""
        }
    }    
    
    public var labelNumber:Int?{        
        set{
            do {
                var resourceValues = URLResourceValues()
                resourceValues.labelNumber = newValue
                var _url = url
                try _url.setResourceValues(resourceValues)
            } catch _{}
        }
        get {
            do{
                return try url.resourceValues(forKeys: [.labelNumberKey]).labelNumber
            }
            catch{return nil}
        }        
    }

    public var labelColor:NSColor?{                
        get {
            do{
                return try url.resourceValues(forKeys: [.labelColorKey]).labelColor
            }
            catch{return nil}
        }
    }
    
    public var creationDate:Date {
        do{
            let d = try url.resourceValues(forKeys: [.creationDateKey]).creationDate
            return d ?? Date()
        }
        catch {
            return Date()
        }
    }

    public var modificationDate:Date {
        do{
            let d = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return d ?? Date()
        }
        catch {
            return Date()
        }
    }

    
    public var displayName:String { 
        return fileManager.displayName(atPath: url.path)            
    }
    
    public var subPaths:[String] {
        if !isDirectory { return [] }
        do {
            return try fileManager.subpathsOfDirectory(atPath: url.path)
        }
        catch {
            return []
        }
    }
    
    private var _isDirectory:Bool? 
    public var isDirectory:Bool {
        if let isd = _isDirectory { return isd }
        _isDirectory = url.isDirectory
        return _isDirectory!
//        do{
//            if let isd = _isDirectory { return isd }
//            let attr = try url.resourceValues(forKeys: [.isDirectoryKey,.isApplicationKey,.isReadableKey,.isPackageKey])
//            let isD = attr.isDirectory ?? false
//            let isA = attr.isApplication ?? false
//            let isR = attr.isReadable ?? false
//            let isB = attr.isPackage ?? false
//            _isDirectory = isD && !isA && isR && !isB  
//            return _isDirectory! 
//        }
//        catch{return false}  
    }
    
    public var recipients:[AnyObject]? {
        guard url.isFileURL else {return nil}
        return MDItemCopyAttribute(mdi, kMDItemRecipients) as? [AnyObject]
    }
    
    public static let ratingKey = "com.apple.metadata:" + String(kMDItemStarRating)
    private var _rating:Int?
    public var rating:Int {
        get {                  
            if let r = FileAttributes(path: url.path).value(forAttribute: FileTreeItem.ratingKey) {
                _rating = Int(r) ?? 0
                return _rating!
            }
            return 0
        }
        set {
            _rating = newValue
            FileAttributes(path: url.path).setValue("\(newValue)", forAttribute: FileTreeItem.ratingKey)
        }
    }
    
    public var lastOpened:Date? {
        guard url.isFileURL else {return nil}
        return MDItemCopyAttribute(mdi, kMDItemLastUsedDate) as? Date
    }
    
    public var mdi:MDItem? {
        return MDItemCreate(kCFAllocatorDefault, url.path as CFString)        
    }
        
    public var relativePath:String { return _relativePath }
    public var parent:FileTreeItem? { return _parent ?? _realParent }
       
    public var url:URL {
        //if var p = parent?.url {
       //     p.appendPathComponent(_relativePath)
       //     return p
       // }
        return _rootPath
    }    
    
    open var isExpanded:Bool {
        set{
            if isDirectory{
                let key = stateKey+":isExpanded:"+url.path
                UserDefaults.standard.set(newValue, forKey: key)
            }
        }
        get {
            if isDirectory{
                let key = stateKey+":isExpanded:"+url.path
                return UserDefaults.standard.bool(forKey: key)
            }
            return false
        }
    }
    
    public var itemsFilter:FileFilterType? {
        didSet{
            invalidateDirectoryCache()
        }
    }
    
    public static func fileno(by url:URL) -> UInt32 {
        return FileTreeItem.fileno(by:url.path)
    }
    
    public static func fileno(by path:String) -> UInt32 {
        do {
            return try (FileManager.default.attributesOfItem(atPath: path)[FileAttributeKey.systemFileNumber] as! NSNumber).uint32Value
        }
        catch _ {
            return UINT32_MAX
        }        
    }

    public static func deviceno(by path:String) -> UInt32 {
        do {
            return try (FileManager.default.attributesOfItem(atPath: path)[FileAttributeKey.deviceIdentifier] as! NSNumber).uint32Value
        }
        catch _ {
            return UINT32_MAX
        }        
    }

    private var _fileno:UInt32 = UINT32_MAX
    public var fileno:UInt32 {
        if _fileno < UINT32_MAX { return _fileno}
        _fileno =  FileTreeItem.fileno(by:url)
        return _fileno
    }
    
    public var sortBy:SortBy { return _sortBy }
    public var sortOrder:SortOrder { return _sortOrder }

    public func setSort(by:SortBy, order:SortOrder) {        
        if by != .none {
            _sortBy = by
            _sortOrder = order
            do {
                _imageFilteredUrls = try _imageFilteredUrls?.sorted(by: { (url1, url2) -> Bool in                    
                    return try self.doSortBy(url1, url2)
                })
                
                _subDirectoryUrls = try _subDirectoryUrls?.sorted(by: { (url1, url2) -> Bool in                    
                    return try self.doSortBy(url1, url2)
                })
            }                
            catch let error {
                NSLog("DHCFileTreeItem setSort error: \(error)")    
            }
        }
        else {
            if _sortBy != by {
                invalidateDirectoryCache()
            }
            _sortBy = by
            _sortOrder = order
        }
    }
    
    typealias UrlsCacheType = [Int : FileTreeItem]
    
    private var _sortBy:SortBy = .none
    private var _sortOrder:SortOrder = .ascending
    
    fileprivate let fileManager = FileManager.`default`

    private var _relativePath:String = ""
    private var _parent:FileTreeItem? = nil
    private var _realParent:FileTreeItem? = nil
    
    private var _rootPath:URL = URL(fileURLWithPath: "/", isDirectory: true)
    private var _modifiedDate:Date?
    
    private lazy var attributes:FileAttributes = FileAttributes(path: self.url.path)
    private static var _cache:[String:Any] = [String:Any]() 
    
    private var _subDirectoryUrls:[URL]?
    private var _subDirectoryItemsCache = UrlsCacheType()
    private var _subDirectoryItemsCacheIsPrefetched = false

    private var _imageAllUrls:[URL]?
    private var _imageFilteredUrls:[URL]?
    private var _imageItemsCache = UrlsCacheType()
    private var _imageItemsCacheIsPrefetched = false
}

public extension FileTreeItem{
    
    public func findDirectory(by surl:URL) -> FileTreeItem? {        
        if surl == url { return self } 
                        
        for i in 0..<subDirectoryNumber() {
            guard let d = subDirectory(at: i) else { continue }
            if surl.path.hasPrefix(d.url.path) {
                if surl.path == d.url.path { return d }
                if let c = d.findDirectory(by: surl) {
                    return c
                }
            }
        }        
        return nil
    }        
}

// MARK: - Children update
public extension FileTreeItem {
    
    public func subDirectoryNumber() -> Int {
        
        if let s = mutex.sync(execute: { () -> [URL]? in  return _subDirectoryUrls  })  {
            return s.count
        } 
        
        var isDir:ObjCBool = true
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) == true else {return 0 }
                
        do {            
            var urls  = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles,.skipsPackageDescendants,.skipsSubdirectoryDescendants])
            
            urls = urls.filter({ (url) -> Bool in
                do {
                    let isD = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
                    let isA = try url.resourceValues(forKeys: [.isApplicationKey]).isApplication ?? false
                    let isR = try url.resourceValues(forKeys: [.isReadableKey]).isReadable ?? false
                    let isB = try url.resourceValues(forKeys: [.isPackageKey]).isPackage ?? false
                    return isD && !isA && isR && !isB 
                }
                catch {
                    return false
                }
            })
            
            if _sortBy != .none {
                urls = try urls.sorted(by: { (url1, url2) -> Bool in                    
                    return try self.doSortBy(url1, url2)
                })
            }            
            
            mutex.sync(execute: { () -> Void in
                _subDirectoryUrls = urls
            })
        }
        catch let error {
            NSLog("DHCFileTreeItem error: \(error)")
        }     
        
        return mutex.sync(execute: { () -> Int in
            if _subDirectoryUrls == nil {
                _subDirectoryUrls = [URL]() 
            }
            return _subDirectoryUrls!.count 
        })
        
        //return _subDirectoryUrls!.count 
    } 
    
    public func subDirectory(at index:Int, withLevel level: Int? = nil) -> FileTreeItem? {
        if index>=0 && index<subDirectoryNumber() {
            return mutex.sync(execute: { () -> FileTreeItem? in
                return getItemFrom(urls: _subDirectoryUrls, cache: &_subDirectoryItemsCache, at: index, withLevel: level)    
            })
            
        }        
        return nil
    }

    private func getItemFrom(url: URL, cache: inout UrlsCacheType, withLevel level: Int? = nil) -> FileTreeItem? {
        let hash = url.path.hashValue //DHCFileTreeItem.fileno(by: url)
        //let hash = Int(DHCFileTreeItem.fileno(by: url))
        if var item = cache[hash] {
            if item.url != url {
                item = FileTreeItem(with: url, parent: self, state: stateKey, level: level)
                cache[hash] = item
            }
            return item     
        }
        cache[hash] = FileTreeItem(with: url, parent: self, state: stateKey, level: level)
        return cache[hash]
    }
    
    private func getItemFrom(urls: [URL]?, cache: inout UrlsCacheType, at index: Int, withLevel level: Int? = nil) -> FileTreeItem? {
        guard let urls = urls, index < urls.count else { return nil }
        let u = urls[index]
        return getItemFrom(url: u, cache: &cache, withLevel: level)
    }
    
    public func prefetchExpanded(willPrefetch:((_ prefetching:Bool)->Void)? = nil, complete:((_ items:[FileTreeItem])->Void)) {
        
        willPrefetch?(!_subDirectoryItemsCacheIsPrefetched)
        
        var items = [FileTreeItem]()
        for i in 0..<subDirectoryNumber() {
            if let item = subDirectory(at: i) {
                for _ in 0..<item.subDirectoryNumber() {/*_ = item.subDirectory(at: j)*/}
                if item.isExpanded {
                    items.append(item)
                }
            }
        }
        
        _subDirectoryItemsCacheIsPrefetched = true
        
        complete(items)
    } 
    
    public func invalidateDirectoryCache() {
        mutex.sync(execute: { () -> Void in
            
            _imageItemsCacheIsPrefetched = false
            _imageFilteredUrls = nil
            _imageAllUrls = nil
            _imageItemsCache = UrlsCacheType()
            
            _subDirectoryUrls = nil
            _subDirectoryItemsCache = UrlsCacheType()
            _subDirectoryItemsCacheIsPrefetched = false
        })
    }
    
    public func utiMatched(types:[String]) -> Bool {
        let type =  uti 
        var isI = false   
        for t in  types {
            if type.hasSuffix(t){   
                isI = true
                break
            }
        }
        return isI
    }
    
    public func prefetchImages(willPrefetch:((_ prefetching:Bool)->Void)? = nil,
                               filter:((_ item:FileTreeItem)->Bool)? = nil, 
                               complete:((_ items:[FileTreeItem])->Void)) {
        
        willPrefetch?(!_imageItemsCacheIsPrefetched)
        
        var items = [FileTreeItem]()
        
        let types = imageTypes.filter{ $0.enabled }.map{ $0.type }

        for i in 0..<imageNumber(ignoreFilter:true) {
            if let item = image(at: i, ignoreFilter:true) {
                               
                if !utiMatched(types:types) { continue }

                var isValid = true
                                
                if let ft = filter {
                    isValid = ft(item)
                }
                
                if isValid {
                    items.append(item)
                }
            }
        }
        
        _imageItemsCacheIsPrefetched = true
        
        complete(items)
    } 
    
//    public func imageNumber(ignoreFilter:Bool = false) -> Int {
//        //return mutex.sync(execute: { () -> Int in
//            return self._imageNumber(ignoreFilter:ignoreFilter)
//        //})
//    }
    
    public func imageNumber(ignoreFilter:Bool = false) -> Int {
        
        if let s = ignoreFilter ? _imageAllUrls : _imageFilteredUrls {
            return s.count
        } 
        
        var isDir:ObjCBool = true
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) == true else { return 0 }
        
        do {            
            var urls = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles,.skipsPackageDescendants,.skipsSubdirectoryDescendants])
            
            let types = imageTypes.filter{ $0.enabled }.map{ $0.type }
            
            urls = urls.filter({ (url) -> Bool in
                do {
                    let isF = url.isFileURL 
                    let attr = try url.resourceValues(forKeys: [.isApplicationKey,.isReadableKey,.isReadableKey,.isPackageKey,.typeIdentifierKey])
                    let isA = attr.isApplication ?? false
                    let isR = attr.isReadable ?? false
                    let isB = attr.isPackage ?? false
                    
                    let type = attr.typeIdentifier ?? ""
                    var isI = false   
                    for t in  types {
                        if type.hasSuffix(t){   
                            isI = true
                            break
                        }
                    }
                    var isValid = true
                    
                    if !ignoreFilter {
                        if let ft = self.itemsFilter {
                            if let it = mutex.sync(execute: { () -> FileTreeItem? in
                                return self.getItemFrom(url: url, cache: &_imageItemsCache, withLevel: nil)
                            }){
                                isValid = ft(it)
                            }
                        }
                    }
                    
                    return isF && !isA && isR && !isB && isI && isValid
                }
                catch {
                    return false
                }
            }) 

            if !ignoreFilter {
                if _sortBy != .none {
                    urls = try urls.sorted(by: { (url1, url2) -> Bool in                    
                        return try self.doSortBy(url1, url2)
                    })
                }
            }
            
            mutex.sync(execute: { () -> Void in
                if ignoreFilter {            
                    _imageAllUrls = urls              
                }
                else {
                    _imageFilteredUrls = urls
                }
            })
        }
        catch let error {
            return 0
        }
        
        
        return mutex.sync(execute: { () -> Int in
            if ignoreFilter {            
                if _imageAllUrls == nil {
                    _imageAllUrls = [URL]() 
                }                                    
            }
            else {
                if _imageFilteredUrls == nil {
                    _imageFilteredUrls = [URL]() 
                }                        
            }
            return ignoreFilter ? _imageAllUrls!.count : _imageFilteredUrls!.count
        })        
        //return ignoreFilter ? _imageAllUrls!.count : _imageFilteredUrls!.count 
    }
    
    fileprivate func doSortBy(_ url1:URL, _ url2:URL) throws -> Bool {
        if _sortBy == .creationDate {
            guard let c1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false } 
            guard let c2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate else { return false } 
            return compare(c1,c2)
        }
        else if _sortBy == .modificationDate {
            guard let c1 = try url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false } 
            guard let c2 = try url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false } 
            return compare(c1,c2)            
        }
        else if _sortBy == .name {
            return compare(url1.lastPathComponent, url2.lastPathComponent)
        }        
        return false
    }
    
    fileprivate func compare<T:Comparable>(_ c1:T, _ c2:T) -> Bool {
        if self._sortOrder == .ascending {
            return c1 < c2
        }
        else {
            return c2 < c1
        }
    }

    public func image(by url:URL, withLevel level: Int? = nil) -> FileTreeItem? {
        let dir = url.deletingLastPathComponent()
        guard dir.path.hasPrefix(self.url.path) else { return nil } 
        return mutex.sync(execute: { () -> FileTreeItem? in
            return getItemFrom(url: url, cache: &_imageItemsCache, withLevel: level)
        })
    }
    
    public func image(by path:String, withLevel level: Int? = nil) -> FileTreeItem? {
        return image(by: URL(fileURLWithPath:path), withLevel: level)
    }
    
    public func image(at index:Int, ignoreFilter:Bool = false, withLevel level: Int? = nil) -> FileTreeItem? {
        if index>=0 && index<imageNumber(ignoreFilter:ignoreFilter){
            return mutex.sync(execute: { () -> FileTreeItem? in
                return getItemFrom(urls: (ignoreFilter ? _imageAllUrls : _imageFilteredUrls), cache: &_imageItemsCache, at: index, withLevel: level)                
            })
        }        
        return nil            
        
    }
}
