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

/// A ServiceDescriptor is an object fetched from NineAnimatorCloud to support the various services and bring updates to the parsers
public struct ServiceDescriptor: Codable {
    public var releaseDate: Date
    
    public var sourcesInformation: [RemoteSourceInformation]
}

/// A RemoteSourceInformation object details the serviceability of a particular source. This can be used to remotely mark a source as unservicable in the future.
public struct RemoteSourceInformation: Codable {
    /// Name of the source
    public var name: String
    
    /// State of usability
    public var isUsable: Bool
    
    /// Notes about the servicability of the source
    public var usabilityNotes: String?
}
