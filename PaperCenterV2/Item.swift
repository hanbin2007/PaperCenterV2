//
//  Item.swift
//  PaperCenterV2
//
//  Created by zhb on 2025/11/9.
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
