import Foundation

final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static var payload = Data()
    static var status = 200
    static var observed: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.observed = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Set-Cookie": "secret=must-not-reuse"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ExperienceDataChecks {
    static func main() async throws {
        let source = Experience.Source(id: "weather", url: URL(string: "https://example.com/data")!, method: "GET", response: .init(fields: [.init(name: "value", path: ["weather", "value"], type: "number")]), timeoutMs: 1000, maxResponseBytes: 128)
        let fetcher = ExperienceData(protocolClasses: [FixtureProtocol.self])
        FixtureProtocol.payload = Data(#"{"weather":{"value":12},"action":{"type":"route.start"}}"#.utf8)
        let values = try await fetcher.fetch(source)
        assert(values == ["value": "12"])
        assert(FixtureProtocol.observed?.value(forHTTPHeaderField: "Authorization") == nil)
        assert(FixtureProtocol.observed?.value(forHTTPHeaderField: "Cookie") == nil)
        assert(FixtureProtocol.observed?.httpBody == nil)
        for payload in [#"{"weather":{"value":true}}"#, #"{"weather":{"value":"12"}}"#, #"{"missing":12}"#, "[]", String(repeating: " ", count: 129) + "{}"] {
            FixtureProtocol.payload = Data(payload.utf8)
            do { _ = try await fetcher.fetch(source); fatalError("Accepted invalid or oversized response") } catch {}
        }
        FixtureProtocol.status = 302; FixtureProtocol.payload = Data("{}".utf8)
        do { _ = try await fetcher.fetch(source); fatalError("Accepted redirect response") } catch {}
        print("Data source mapping, credential isolation and response-limit checks passed")
    }
}
