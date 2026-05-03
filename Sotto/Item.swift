//
//  Item.swift
//  Sotto
//
//  Created by Evert Junior on 03/05/26.
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
