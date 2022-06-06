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

// import AppCenter
// import AppCenterAnalytics
// import AppCenterCrashes
import Foundation

public class NineAnimatorCloud {
    public static let baseUrl: URL = {
        let apiBaseRequestEndpoint = URL(string: "https://9ani.app/api")!
        let currentAppVersion = NineAnimatorVersion.current
        return apiBaseRequestEndpoint
            .appendingPathComponent("app")
            .appendingPathComponent(currentAppVersion.releaseTagRepresentation, isDirectory: true)
    }()
    
    // Placeholder URL
    public static var placeholderArtworkURL: URL {
        baseUrl.appendingPathComponent("static/resources/artwork_not_available.jpg")
    }
    
    public private(set) lazy var requestManager = NACloudRequestManager(parent: self)
    
    /// Build identifier used to communicate and identify the build with NineAnimator cloud services
    ///
    /// Build identifier is calculated by mixing and hashing the states of various supported sources and server parsers.
    public var buildIdentifier: String {
        var runtimeId = NineAnimator.default.user.runtimeUuid.uuid
        _ = withUnsafeMutablePointer(to: &runtimeId.0) {
            ptr in serviceSalt.enumerated().reduce(ptr.advanced(by: 4)) {
                current, value in
                current.pointee = (value.offset % 2) == 0 ? ~value.element : value.element
                return current.advanced(by: 1)
            }
        }
        return UUID(uuid: runtimeId).uuidString
    }
    
    /// Salt used to calculate various parameters used for connecting to the cloud services
    public var serviceSalt: [UInt8] {
        [ 234, 123, 183, 79, 91, 185 ]
    }
    
    public var serviceOffset: UInt64 {
        UInt64(2101151363300)
    }
    
    public func dummy() { }
    
    public func setup() {
        // Setup analytical service
//        Crashes.delegate = appCenterCrashesDelegate
//        AppCenter.start(withAppSecret: buildIdentifier, services: [
//            Crashes.self,
//            Analytics.self
//        ])
//        Analytics.enabled = !NineAnimator.default.user.optOutAnalytics
    }
    
    // MARK: Internal Variables
    
    internal var _cachedAvailabilityData: VersionedAppAvailabilityData?
    internal var _cachedAvailabilityDataLastUpdate: Date?
    internal var _availabilityDataRenewTask: NineAnimatorAsyncTask?
    internal var _requestProcessingQueue = DispatchQueue(
        label: "com.marcuszhou.nineanimator.NineAnimatorCloud.requestDispatch",
        qos: .default
    )
}
