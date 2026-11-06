// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum SourceHTTPValidation {
    struct HTTPError: LocalizedError {
        let status: Int
        let host: String
        var errorDescription: String? { "HTTP \(status) from \(host)" }
    }
    static func validate(_ response: URLResponse) throws {
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw HTTPError(status: response.statusCode, host: response.url?.host ?? "unknown")
        }
    }
}
