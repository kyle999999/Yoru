// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import WasmInterpreter

enum ModernNativeHTTP {
    static func perform(_ input: [String: Any]) -> [String: Any] {
        do {
            guard let address = input["url"] as? String, let url = URL(string: address) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = input["method"] as? String ?? "GET"
            for (key, values) in input["headers"] as? [String: [String]] ?? [:] { request.setValue(values.joined(separator: ", "), forHTTPHeaderField: key) }
            if let encoded = input["body"] as? String { request.httpBody = Data(base64Encoded: encoded) }
            // Reuse the tested isolated Foundation/WebKit challenge transport; this empty
            // legacy VM is only its context holder and never executes a source module.
            let vm = try WasmInterpreter(module: [0, 97, 115, 109, 1, 0, 0, 0])
            let network = WasmNet(globalStore: WasmGlobalStore(id: "modern-network", vm: vm))
            guard let response = network.performRequest(request) else { throw URLError(.badServerResponse) }
            if let error = response.error { throw error }
            var headers: [String: [String]] = [:]
            for (key, value) in (response.response as? HTTPURLResponse)?.allHeaderFields ?? [:] { headers[String(describing: key)] = [String(describing: value)] }
            return ["status": response.statusCode ?? 0, "headers": headers,
                    "body": (response.data ?? Data()).base64EncodedString(), "url": response.response?.url?.absoluteString ?? address]
        } catch { return ["error": error.localizedDescription] }
    }
}
