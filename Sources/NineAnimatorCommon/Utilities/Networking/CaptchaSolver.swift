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

import Alamofire
import Foundation

public class CaptchaSolver {
    public init() { }
    
    private static let RECAPTCHA_API_JS = "https://www.google.com/recaptcha/api.js"

    private static let vTokenRegex = try! NSRegularExpression(
        pattern: #"releases/([^/&?#]+)"#,
        options: .caseInsensitive
    )
    private static let recaptchaTokenRegex =  try! NSRegularExpression(
        pattern: #"recaptcha-token.+?=\"(.+?)\""#,
        options: .caseInsensitive
    )
    private static let tokenRegex =  try! NSRegularExpression(
        pattern: #"rresp\",\"(.+?)\""#,
        options: .caseInsensitive
    )
    
    /// Solve Google invisible captcha
    public func getTokenRecaptcha(with session: Session, recaptchaSiteKey: String, url: URL) -> NineAnimatorPromise<String> {
        NineAnimatorPromise {
            callback in session.request(
                CaptchaSolver.RECAPTCHA_API_JS,
                parameters: [ "render": recaptchaSiteKey ],
                headers: [ "referer": url.absoluteString ]
            ).responseString {
                callback($0.value, $0.error)
            }
        } .thenPromise {
            recaptchaOut in
            
            let vToken = try (
                CaptchaSolver.vTokenRegex.firstMatch(in: recaptchaOut)?.firstMatchingGroup
            ).tryUnwrap()
            let domain = "https://\(url.host!):443".data(using: .utf8)?.base64EncodedString().replacingOccurrences(of: "=", with: "") ?? ""
            
            return NineAnimatorPromise {
                callback in session.request(
                    "https://www.google.com/recaptcha/api2/anchor",
                    parameters: [
                        "ar": 1,
                        "k": recaptchaSiteKey,
                        "co": domain,
                        "hi": "en",
                        "v": vToken,
                        "size": "invisible",
                        "cb": 123456789
                    ]
                ) .responseString {
                    callback($0.value, $0.error)
                }
            } .thenPromise {
                anchorOut in
                            
                let recaptchaToken = try (
                    CaptchaSolver.recaptchaTokenRegex.firstMatch(in: anchorOut)?.firstMatchingGroup
                ).tryUnwrap()
                
                return NineAnimatorPromise {
                    callback in session.request(
                        "https://www.google.com/recaptcha/api2/reload?k=\(recaptchaSiteKey)",
                        method: .post,
                        parameters: [
                            "v": vToken,
                            "reason": "q",
                            "k": recaptchaSiteKey,
                            "c": recaptchaToken,
                            "sa": "",
                            "co": domain
                        ],
                        headers: [ "referer": "https://www.google.com/recaptcha/api2" ]
                    ).responseString {
                        callback($0.value, $0.error)
                    }
                } .then {
                    tokenOut in
                    
                    let token = try (
                        CaptchaSolver.tokenRegex.firstMatch(in: tokenOut)?.firstMatchingGroup
                    ).tryUnwrap()
                    
                    return token
                }
            }
        }
    }
}
