import Foundation
import CoreFoundation

struct Experience: Decodable {
    struct Metadata: Decodable { let name: String; let icon: String; let summary: String }
    struct Screen: Decodable { let id: String; let title: String; let components: [Component] }
    struct Component: Decodable { let type: String; let text: String?; let label: String?; let binding: Binding?; let action: Action? }
    struct Binding: Decodable { let source: String; let field: String; let type: String; let dataSource: String? }
    struct Action: Decodable { let type: String; let activityType: String?; let layout: String?; let screen: String?; let dataSource: String? }
    struct Source: Decodable {
        struct Response: Decodable { let fields: [Field] }
        struct Field: Decodable { let name: String; let path: [String]; let type: String }
        let id: String; let url: URL; let method: String; let response: Response; let timeoutMs: Int; let maxResponseBytes: Int
    }
    let schemaVersion: Int; let runtimeVersion: Int; let creatorKey: String
    let metadata: Metadata; let capabilities: [String]; let screens: [Screen]; let dataSources: [Source]?

    static func decode(_ data: Data, schemaURL: URL? = Bundle.main.url(forResource: "experience.schema", withExtension: "json")) throws -> Experience {
        guard data.count <= 65536, let schemaURL else { throw invalid("Configuration or schema unavailable") }
        let value = try JSONSerialization.jsonObject(with: data)
        try bounded(value)
        let schema = try JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as! [String: Any]
        try SchemaCheck.validate(value, schema)
        let config = try JSONDecoder().decode(Experience.self, from: data)
        try config.validateReferences()
        return config
    }
    static func invalid(_ message: String) -> NSError { NSError(domain: "PocketExperience", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    static func bounded(_ value: Any, depth: Int = 0) throws {
        guard depth <= 16 else { throw invalid("JSON is nested too deeply") }
        if let object = value as? [String: Any] { for child in object.values { try bounded(child, depth: depth + 1) } }
        else if let array = value as? [Any] { for child in array { try bounded(child, depth: depth + 1) } }
    }
    static func validEndpoint(_ url: URL) -> Bool {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              !url.absoluteString.contains(where: { $0.isWhitespace }) else { return false }
        return true
    }
    private func validateReferences() throws {
        func require(_ capability: String) throws { guard capabilities.contains(capability) else { throw Self.invalid("Missing declared capability") } }
        if capabilities.contains("liveActivity.route") { try require("route.recording") }
        guard !metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !metadata.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(screens.map(\.id)).count == screens.count else { throw Self.invalid("Invalid metadata or duplicate screens") }
        let sources = dataSources ?? []
        guard Set(sources.map(\.id)).count == sources.count else { throw Self.invalid("Duplicate sources") }
        for source in sources {
            guard Self.validEndpoint(source.url), Set(source.response.fields.map(\.name)).count == source.response.fields.count,
                  source.response.fields.allSatisfy({ $0.path.allSatisfy { !["__proto__", "constructor", "prototype"].contains($0) } }) else { throw Self.invalid("Invalid data source") }
        }
        for screen in screens {
            guard !screen.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Self.invalid("Empty title") }
            for component in screen.components {
                if component.type == "routeMap" { try require("route.recording") }
                if let binding = component.binding {
                    if binding.source == "route" {
                        try require("route.recording")
                        guard binding.type == (binding.field == "status" ? "string" : "number") else { throw Self.invalid("Binding type mismatch") }
                    } else {
                        guard let source = sources.first(where: { $0.id == binding.dataSource }), source.response.fields.contains(where: { $0.name == binding.field && $0.type == binding.type }) else { throw Self.invalid("Unknown data binding") }
                    }
                }
                if let action = component.action {
                    if action.type.hasPrefix("route.") { try require("route.recording") }
                    if action.type.hasPrefix("liveActivity.") { try require("liveActivity.route"); try require("route.recording") }
                    if action.type == "navigate", !screens.contains(where: { $0.id == action.screen }) { throw Self.invalid("Unknown screen") }
                    if action.type == "data.refresh", !sources.contains(where: { $0.id == action.dataSource }) { throw Self.invalid("Unknown source") }
                }
            }
        }
    }
}

/// Evaluates only the finite keywords used by the bundled shared contract.
private enum SchemaCheck {
    static func validate(_ value: Any, _ schema: [String: Any]) throws {
        func reject() throws { throw Experience.invalid("Unsupported or malformed configuration") }
        if let variants = schema["oneOf"] as? [[String: Any]] {
            guard variants.filter({ (try? validate(value, $0)) != nil }).count == 1 else { return try reject() }
        }
        if let constant = schema["const"], !equal(value, constant) { return try reject() }
        if let options = schema["enum"] as? [Any], !options.contains(where: { equal(value, $0) }) { return try reject() }
        if let type = schema["type"] as? String {
            let number = value as? NSNumber
            let numeric = number != nil && CFGetTypeID(number!) != CFBooleanGetTypeID()
            let valid: Bool
            switch type {
            case "object": valid = value is [String: Any]
            case "array": valid = value is [Any]
            case "string": valid = value is String
            case "integer": valid = numeric && number!.doubleValue.rounded() == number!.doubleValue
            case "number": valid = numeric
            default: valid = false
            }
            guard valid else { return try reject() }
        }
        if let object = value as? [String: Any] {
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            for key in schema["required"] as? [String] ?? [] { if object[key] == nil { return try reject() } }
            if schema["additionalProperties"] as? Bool == false, !Set(object.keys).isSubset(of: Set(properties.keys)) { return try reject() }
            for (key, child) in object { if let rule = properties[key] { try validate(child, rule) } }
        }
        if let array = value as? [Any] {
            guard array.count >= (schema["minItems"] as? Int ?? 0), array.count <= (schema["maxItems"] as? Int ?? Int.max) else { return try reject() }
            if schema["uniqueItems"] as? Bool == true {
                for i in array.indices { for j in array.indices where j < i { if equal(array[i], array[j]) { return try reject() } } }
            }
            for child in array { try validate(child, schema["items"] as? [String: Any] ?? [:]) }
        }
        if let string = value as? String {
            guard string.unicodeScalars.count >= (schema["minLength"] as? Int ?? 0), string.unicodeScalars.count <= (schema["maxLength"] as? Int ?? Int.max) else { return try reject() }
            if let pattern = schema["pattern"] as? String, string.range(of: pattern, options: .regularExpression) == nil { return try reject() }
        }
        if let number = value as? NSNumber {
            guard number.doubleValue.isFinite, number.doubleValue >= (schema["minimum"] as? Double ?? -.infinity), number.doubleValue <= (schema["maximum"] as? Double ?? .infinity) else { return try reject() }
        }
    }
    static func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? NSNumber, let y = b as? NSNumber { return CFGetTypeID(x) == CFGetTypeID(y) && x == y }
        return (a as? NSObject)?.isEqual(b) ?? false
    }
}
