//
//  VariableType.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation

/// Defines the data type of a Variable
enum VariableType: String, Codable, CaseIterable {
    case int = "int"      // Integer value
    case list = "list"    // Single choice from predefined options
}
