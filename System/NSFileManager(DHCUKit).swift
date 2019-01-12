//
//  NSFileManager(DHCUKit).swift
//  DehancerUIKit
//
//  Created by denis svinarchuk on 19.11.2017.
//

import Foundation

public extension FileManager {
    public static var documentsDir:String {
        var paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true) as [String]
        return paths[0]
    }
    
    public static var cachesDir:String {
        var paths = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true) as [String]
        return paths[0]
    }
    
    public class func cacheFileName(path: String, `extension`:String?=nil) -> String {
        if let ext = `extension` {
            return (path.md5 as NSString).appendingPathExtension(ext)!
        }
        return path.md5
    }
}
