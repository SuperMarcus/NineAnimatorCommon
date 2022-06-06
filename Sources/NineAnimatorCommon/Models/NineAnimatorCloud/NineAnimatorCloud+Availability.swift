//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2021 Marcus Zhou. All rights reserved.
//
//  NineAnimator is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  NineAnimator is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with NineAnimator.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

public extension NineAnimatorCloud {
    /// Check to ensure that availablility data has been loaded into memory
    func isAvailabilityDataCached() -> Bool {
        _cachedAvailabilityData != nil
    }
}

// MARK: - Type Definitions
public extension NineAnimatorCloud {
    static var availablilityDataRenewInterval: TimeInterval {
        60 * 60 // 1hr update interval
    }
    
    /// Availability data returned from NineAnimatorCloud.
    struct VersionedAppAvailabilityData: Codable {
        /// Binary version that this piece of data is meant for
        public var version: NineAnimatorCloudBinaryVersion
        
        /// Date that this availability data was last updated
        public var lastUpdate: Date
        
        /// Specific availability data for each source
        public var sources: [SourceAvailabilityData]
    }
    
    /// NineAnimatorCloud's version structure, containing a `version` semvar string and a `build` integer build number.
    struct NineAnimatorCloudBinaryVersion: Codable, CustomStringConvertible {
        /// Wrapped NineAnimatorVersion
        public var version: NineAnimatorVersion {
            .init(semvar: _versionSemvar, build: _buildNumber) ?? .zero
        }
        
        /// Release tag representation of the app version
        public var description: String {
            version.releaseTagRepresentation
        }
        
        fileprivate var _versionSemvar: String
        fileprivate var _buildNumber: Int
        
        public enum CodingKeys: String, CodingKey {
            case _versionSemvar = "version"
            case _buildNumber = "build"
        }
    }
    
    /// Possible status of a source.
    enum SourceStatusLabel: String, Codable {
        /// A `normal` status indicates that the source is functional or is operating under degraded performance.
        case normal
        
        /// An `experimental` state indicates the source may be available for experimenting, but should be hidden due to reliability or other reasons.
        case experimental
        
        /// A `disabled` state indicates that the source is malfunctional. Recovery from this state is impossible without an app or descriptor update.
        case disabled
    }
    
    /// Detailed status information of a source.
    struct SourceStatusEntry: Codable {
        /// Status label of the source.
        public var status: SourceStatusLabel
        
        /// A description of why the source transitioned to this status.
        public var statusDescription: String
        
        /// Date at which the source was assigned with this status.
        public var updateDate: Date
    }
    
    /// Availability and status data for a source
    struct SourceAvailabilityData: Codable {
        /// Name of the source. This must match the name registered in the source registry.
        public var name: String
        
        /// Latest status of the source
        public var status: SourceStatusEntry
        
        /// History of statuses of the source
        public var history: [SourceStatusEntry]
    }
}
