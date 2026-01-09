//
//  Item.swift
//  Haesslon
//
//  Created by Daniel Arndt on 09.01.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
