// SPDX-License-Identifier: GPL-3.0-only
import Foundation
@main struct SourceTransportChecks {
    static func main() throws {
        let url = URL(string: "https://example.invalid/search?q=A%26B%2BC%2520&signature=x%2Fy%3D")!
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        assert(parts.queryItems?.first?.value == "A&B+C%20")
        assert(parts.queryItems?.count == 2)
        let success = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try SourceHTTPValidation.validate(success)
        for status in [401, 403, 404, 429, 500, 503] {
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            do { try SourceHTTPValidation.validate(response); fatalError("HTTP error accepted") }
            catch let error as SourceHTTPValidation.HTTPError {
                assert(error.status == status)
                assert(!error.localizedDescription.contains("signature"))
            }
        }
        print("PASS: encoded query integrity, successful response, six HTTP failures and credential-safe error messages")
    }
}
