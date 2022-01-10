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
    platforms: [ .iOS(.v13), .tvOS(.v13), .watchOS(.v7), .macOS(.v11) ],
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
            from: "5.5.0"
        ),
        .package(
            name: "SwiftSoup",
            url: "https://github.com/scinfu/SwiftSoup.git",
            from: "2.3.6"
        ),
        .package(
            name: "Kingfisher",
            url: "https://github.com/onevcat/Kingfisher.git",
            from: "7.1.2"
        ),
        .package(
            name: "OpenCastSwift",
            url: "https://github.com/SuperMarcus/OpenCastSwift.git",
            .revision("0cb71ddaabd1128f5745ff5f37f6af26bea82d36")
        )
    ],
    targets: [
        .target(
            name: "NineAnimatorCommon",
            dependencies: [
                "Alamofire",
                "SwiftSoup",
                "Kingfisher",
                "OpenCastSwift"
            ],
            exclude: [
                "Utilities/DictionaryCoding/LICENSE.md",
                "Utilities/DictionaryCoding/README.md"
            ]
        ),
        .testTarget(
            name: "NineAnimatorCommonTests",
            dependencies: [ "NineAnimatorCommon" ]
        )
    ]
)
