//
//  Date(tenses).swift
//  Dehancer Desktop
//
//  Created by denn on 08/01/2019.
//  Copyright © 2019 Dehancer. All rights reserved.
//

import Foundation

extension Date {
    var isPast: Bool {
        return isPast(referenceDate: Date())
    }
    
    var isFuture: Bool {
        return !isPast
    }
    
    func isPast(referenceDate: Date) -> Bool {
        return timeIntervalSince(referenceDate) <= 0
    }
    
    func isFuture(referenceDate: Date) -> Bool {
        return !isPast(referenceDate: referenceDate)
    }
       
    var fileAttributeDate: Date {
        return Date(timeIntervalSince1970: ceil(timeIntervalSince1970))
    }
}
