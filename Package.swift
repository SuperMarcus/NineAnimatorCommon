// swift-tools-version:5.3
//
//  This file is part of the NineAnimator project.
//
//  Copyright © 2018-2020 Marcus Zhou. All rights reserved.
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
import PackageDescription

/// Use binary XCframework for MSAppCenter instead of building from source
let useBinaryAppCenterPackage = false

let package = Package(
    name: "NineAnimatorCommon",
    platforms: [ .iOS(.v12), .tvOS(.v13), .watchOS(.v7), .macOS(.v11) ],
    products: [
        .library(
            name: "NineAnimatorCommon",
            type: .dynamic,
            targets: [ "NineAnimatorCommon" ]
        )
    ],
    dependencies: [
        .package(
            name: "Alamofire",
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.4.3"
        ),
        .package(
            name: "SwiftSoup",
            url: "https://github.com/scinfu/SwiftSoup.git",
            from: "2.3.2"
        ),
        .package(
            name: "Kingfisher",
            url: "https://github.com/onevcat/Kingfisher.git",
            from: "6.3.0"
        ),
        .package(
            name: "OpenCastSwift",
            url: "https://github.com/SuperMarcus/OpenCastSwift.git",
            .revision("5f0328feb73b811180a88b60cc6ed36bfb76bf03")
        )
    ],
    targets: [
        .target(
            name: "NineAnimatorCommon",
            dependencies: [
                "Alamofire",
                "SwiftSoup",
                "Kingfisher",
                "OpenCastSwift"//,
//                useBinaryAppCenterPackage ? "AppCenterCrashes" : .product(name: "AppCenterCrashes", package: "AppCenter"),
//                useBinaryAppCenterPackage ? "AppCenterAnalytics" : .product(name: "AppCenterAnalytics", package: "AppCenter")
            ],
            exclude: [
                "Utilities/DictionaryCoding/LICENSE.md",
                "Utilities/DictionaryCoding/README.md"
            ]
        )
    ]
)

// Add binary dependencies of MSAppCenter
//if useBinaryAppCenterPackage {
//    // Inject AppCenter base libs as dependency
//    package.targets.first!.dependencies.append("AppCenter")
//
//    // Add the AppCenter, AppCenterCrashes, and AppCenterAnalytics packages
//    package.targets.append(.binaryTarget(
//        name: "AppCenter",
//        url: "https://supermarcus.github.io/NineAnimatorCommon/pkg/app-center/4.2.0/AppCenter.xcframework.zip",
//        checksum: "5764c0ddde2ac6a8c89bd833a842fde98fde904b0a3c0cedd1c0a7b288809f89"
//    ))
//    package.targets.append(.binaryTarget(
//        name: "AppCenterCrashes",
//        url: "https://supermarcus.github.io/NineAnimatorCommon/pkg/app-center/4.2.0/AppCenterCrashes.xcframework.zip",
//        checksum: "9579f4050945a8c9514144437ddd56b6053e40a631203069d090b365ddf734e8"
//    ))
//    package.targets.append(.binaryTarget(
//        name: "AppCenterAnalytics",
//        url: "https://supermarcus.github.io/NineAnimatorCommon/pkg/app-center/4.2.0/AppCenterAnalytics.xcframework.zip",
//        checksum: "3694476713e145f4f6edbe32420da2342b1d5900461645b2b38b22e474013203"
//    ))
//} else {
//    // Inject AppCenter as dependency
//    package.dependencies.append(.package(
//        name: "AppCenter",
//        url: "https://github.com/microsoft/appcenter-sdk-apple.git",
//        from: "4.1.1"
//    ))
//}
