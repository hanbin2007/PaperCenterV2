//
//  OCRSettings.swift
//  PaperCenterV2
//
//  Created by Claude on 2025-11-09.
//

import Foundation
import SwiftUI

/// OCR Language options
enum OCRLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .chinese:
            return "Chinese"
        }
    }
}

/// Settings manager for OCR extraction
@Observable
final class OCRSettings {

    // MARK: - Shared Instance

    static let shared = OCRSettings()

    // MARK: - Settings Keys

    private enum Keys {
        static let visionOCREnabled = "visionOCREnabled"
        static let ocrLanguage = "ocrLanguage"
    }

    // MARK: - Properties

    /// Whether to use Vision framework OCR (true) or only embedded text extraction (false)
    var isVisionOCREnabled: Bool {
        didSet {
            UserDefaults.standard.set(isVisionOCREnabled, forKey: Keys.visionOCREnabled)
        }
    }

    /// Selected OCR language
    var ocrLanguage: OCRLanguage {
        didSet {
            UserDefaults.standard.set(ocrLanguage.rawValue, forKey: Keys.ocrLanguage)
        }
    }

    // MARK: - Initialization

    private init() {
        // Default to true (Vision OCR enabled)
        self.isVisionOCREnabled = UserDefaults.standard.object(forKey: Keys.visionOCREnabled) as? Bool ?? true

        // Default to English
        if let languageString = UserDefaults.standard.string(forKey: Keys.ocrLanguage),
           let language = OCRLanguage(rawValue: languageString) {
            self.ocrLanguage = language
        } else {
            self.ocrLanguage = .english
        }
    }

    // MARK: - Methods

    /// Reset all settings to defaults
    func resetToDefaults() {
        isVisionOCREnabled = true
        ocrLanguage = .english
    }
}
