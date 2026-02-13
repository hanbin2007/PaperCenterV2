//
//  MetadataNotifications.swift
//  PaperCenterV2
//
//  Defines shared notifications for metadata changes so dependent views can refresh.
//

import Foundation

extension Notification.Name {
    nonisolated static let metadataCatalogDidChange = Notification.Name("MetadataCatalogDidChange")
}
