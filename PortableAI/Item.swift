//
//  Item.swift
//  PortableAI
//
//  Created by kim monzon on 08/09/2026.
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
