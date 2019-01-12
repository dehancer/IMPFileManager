//
//  DHCFSWatch.swift
//  DehancerUIKit
//
//  Created by denis svinarchuk on 28.09.17.
//

import Foundation

//
// Sources: https://github.com/soh335/FileWatch
//

@available(OSX 10.10, *) 
public class FSWatch {
    
    public var excludes:[String] = ["/private", "/tmp", "/var", "/Library", "/System", "/Network", "/Applications"]
    
    // wrap FSEventStreamEventFlags as  OptionSetType
    public struct EventFlag: OptionSet {
        
        public let rawValue:    FSEventStreamEventFlags
        public var description: String
                
        public init(rawValue: FSEventStreamEventFlags) {
            self.rawValue = rawValue
            self.description =  "Unknown event"
        }
        
        public init(rawValue: FSEventStreamEventFlags, description:String) {
            self.rawValue = rawValue
            self.description = description
        }
        
        public static let none = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagNone), description:"None event")        
        public static let mustScanSubDirs = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs), description:"Must Scan SubDirs")        
        public static let userDropped = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped), description:"User Dropped")        
        public static let kernelDropped = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped), description:"Kernel Dropped")        
        public static let idsWrapped = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped), description:"Must Scan SubDirs")        
        public static let historyDone = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone), description:"History Done")        
        public static let rootChanged = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged), description:"Root Changed")        
        public static let mount = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagMount), description:"Mount")        
        public static let unmount = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount), description:"Unmount")        
        public static let itemCreated = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated), description:"Item Created")        
        public static let itemRemoved = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved), description:"Item Removed")        
        public static let itemInodeMetaMod = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemInodeMetaMod), description:"Item Metadata Modified")        
        public static let itemRenamed = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed), description:"Item Renamed")        
        public static let itemModified = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified), description:"Item Modified")        
        public static let itemFinderInfoMod = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemFinderInfoMod), description:"Item Finder Info Modified")        
        public static let itemChangeOwner = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemChangeOwner), description:"Item Change Owner")        
        public static let itemXattrMod = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemXattrMod), description:"Item Xattr Modified")
        public static let itemIsFile = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile), description:"Item is File")        
        public static let itemIsDir = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir), description:"Item is Directory")        
        public static let itemIsSymlink = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsSymlink), description:"Item is Symlink")        
        public static let ownEvent = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagOwnEvent), description:"Own Event")        
        public static let itemIsHardlink = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsHardlink), description:"Item is Hard Link")        
        public static let itemIsLastHardlink = EventFlag(rawValue: FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsLastHardlink), description:"Item is Last Hard link")   
        
        public static let list:[EventFlag] = [.mustScanSubDirs, .userDropped, .kernelDropped, .idsWrapped, .historyDone,
                                             .rootChanged, .mount, .unmount, .itemCreated, .itemRemoved, .itemInodeMetaMod, 
                                             .itemRenamed, .itemModified,
                                             .itemFinderInfoMod, .itemChangeOwner, .itemXattrMod, .itemIsFile, .itemIsDir, 
                                             .itemIsSymlink, .ownEvent, .itemIsHardlink, .itemIsLastHardlink]
    }
    
    // wrap FSEventStreamCreateFlags as OptionSetType
    public struct CreateFlag: OptionSet {
        public let rawValue: FSEventStreamCreateFlags
        public init(rawValue: FSEventStreamCreateFlags) {
            self.rawValue = rawValue
        }
        
        public static let None = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        public static let UseCFTypes = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes))
        public static let NoDefer = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer))
        public static let WatchRoot = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot))        
        public static let IgnoreSelf = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagIgnoreSelf))        
        public static let FileEvents = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))        
        public static let MarkSelf = CreateFlag(rawValue: FSEventStreamCreateFlags(kFSEventStreamCreateFlagMarkSelf))        
    }
    
    public struct Event {
        public let path: String
        public let flag:  EventFlag
        public var description:String {        
            return flag.description
        }
        public let eventID: FSEventStreamEventId
        
        public init(path: String, flag: FSWatch.EventFlag, eventID: FSEventStreamEventId){
            self.path = path
            self.flag = EventFlag(rawValue: flag.rawValue, description: Event.getDescription(flag: flag))
            self.eventID = eventID 
        }
        
        private static func getDescription(flag:EventFlag) -> String {
            var desc = ""
            var index = 0
            for f in EventFlag.list {
                if flag.contains(f) {
                    if index > 0 { desc += "|" }
                    desc += f.description
                    index += 1
                }
            }
            return desc            
        }
    }
    
    public enum Error: Swift.Error {
        case startFailed
        case streamCreateFailed
        case notContainUseCFTypes
    }
    
    public typealias EventHandler = ([Event]) -> Void
    
    public let eventHandler: EventHandler
    private var eventStream: FSEventStreamRef?
    
    public init(paths: [String], 
                latency: CFTimeInterval = 1, 
                createFlag: CreateFlag = [.UseCFTypes, .FileEvents], 
                runLoop: RunLoop = .current, 
                eventHandler: @escaping EventHandler) throws {
        
        self.eventHandler = eventHandler
        
        var ctx = FSEventStreamContext(version: 0, info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), retain: nil, release: nil, copyDescription: nil)
        
        if !createFlag.contains(.UseCFTypes) {
            throw Error.notContainUseCFTypes
        }  
        guard let eventStream = FSEventStreamCreate(kCFAllocatorDefault, 
                                                    streamCallback, 
                                                    &ctx, 
                                                    paths as CFArray, 
                                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 
                                                    latency, 
                                                    createFlag.rawValue) else {
                                                        throw Error.streamCreateFailed
        }
        
        FSEventStreamScheduleWithRunLoop(eventStream, runLoop.getCFRunLoop(), CFRunLoopMode.defaultMode.rawValue)
        
        if !FSEventStreamStart(eventStream) { throw Error.startFailed }
        
        self.eventStream = eventStream        
    }
    
    private func stop() {
        guard let eventStream = self.eventStream else {
            return
        }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }
    
    deinit {
        stop()
    }
}

func convert<T>(length: Int, data: UnsafePointer<FSEventStreamEventFlags>, _: T.Type) -> [T] {
    let numItems = length/MemoryLayout<T>.stride
    let buffer = data.withMemoryRebound(to: T.self, capacity: numItems) {
        UnsafeBufferPointer(start: $0, count: numItems)
    }
    return Array(buffer) 
}

fileprivate func streamCallback(streamRef: ConstFSEventStreamRef, 
                                clientCallBackInfo: UnsafeMutableRawPointer?, 
                                numEvents: Int, 
                                eventPaths: UnsafeMutableRawPointer, 
                                eventFlags: UnsafePointer<FSEventStreamEventFlags>, 
                                eventIds: UnsafePointer<FSEventStreamEventId>) -> Void {
    
    let `self` = unsafeBitCast(clientCallBackInfo, to: FSWatch.self)
    
    guard let eventPathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
        return
    }
         
    
    var events = [FSWatch.Event]()
    for i in 0..<numEvents {
        let path = eventPathArray[i]
        let flag = eventFlags[i] 

//        let url = URL(fileURLWithPath:path)
//        
//        do {
//            let attributes = try url.resourceValues(forKeys: [.isHiddenKey, 
//                                                              .isApplicationKey, 
//                                                              .isReadableKey, 
//                                                              .isPackageKey])
//            let cont = (attributes.isHidden ?? true) || (attributes.isApplication ?? true) || !(attributes.isReadable ?? false) || (attributes.isPackage ?? true )            
//            
//            if cont { continue }
//            
//        }
//        catch let error {}
        
//        var cont = true
//        for e in self.excludes {
//            if path.hasPrefix(e) {
//                cont = false
//                break
//            }
//        }
//        
//        if !cont {
//            return
//        }
//        
//        if path.hasSuffix(".DS_Store") {
//            return
//        }
        
        let eventID = eventIds[i] 
        let event = FSWatch.Event(path: path, flag: FSWatch.EventFlag(rawValue: flag), eventID: eventID)
        events.append(event)
    }
    //if events.count>0{
        `self`.eventHandler(events)
    //}
}

