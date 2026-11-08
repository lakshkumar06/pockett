import Foundation
import CoreFoundation

/// A separate ephemeral session: no Pocket auth, shared cookies, cache or credentials.
final class ExperienceData: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let protocolClasses: [AnyClass]?
    init(protocolClasses: [AnyClass]? = nil) { self.protocolClasses = protocolClasses; super.init() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func fetch(_ source: Experience.Source) async throws -> [String: String] {
        guard Experience.validEndpoint(source.url) else { throw Experience.invalid("Invalid endpoint") }
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = Double(source.timeoutMs) / 1000
        configuration.timeoutIntervalForResource = Double(source.timeoutMs) / 1000
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: source.url)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType == "application/json", response.expectedContentLength <= source.maxResponseBytes else { throw Experience.invalid("Expected a bounded JSON response") }
        var data = Data()
        let deadline = Date().addingTimeInterval(Double(source.timeoutMs) / 1000)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < source.maxResponseBytes, Date() < deadline else { throw Experience.invalid("Data source limit exceeded") }
            data.append(byte)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Experience.invalid("Expected a JSON object") }
        try Experience.bounded(object)
        var result: [String: String] = [:]
        for field in source.response.fields {
            var value: Any = object
            for key in field.path {
                guard !["__proto__", "constructor", "prototype"].contains(key), let child = (value as? [String: Any])?[key] else { throw Experience.invalid("Missing response field") }
                value = child
            }
            switch field.type {
            case "string":
                guard let string = value as? String, string.count <= 500 else { throw Experience.invalid("Invalid string field") }; result[field.name] = string
            case "number":
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { throw Experience.invalid("Invalid number field") }; result[field.name] = number.stringValue
            case "boolean":
                guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw Experience.invalid("Invalid boolean field") }; result[field.name] = number.boolValue ? "Yes" : "No"
            default: throw Experience.invalid("Unsupported data field")
            }
        }
        return result
    }
}
