import Foundation

@main struct ExperienceChecks {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Developer/Contracts")
        let schema = root.appendingPathComponent("experience.schema.json")
        var count = 0
        for category in ["valid", "invalid"] {
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("fixtures/" + category), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            for file in files {
                do {
                    _ = try Experience.decode(Data(contentsOf: file), schemaURL: schema)
                    precondition(category == "valid", "Accepted invalid fixture: \(file.lastPathComponent)")
                } catch {
                    precondition(category == "invalid", "Rejected valid fixture: \(file.lastPathComponent): \(error)")
                }
                count += 1
            }
        }
        print("Experience shared-fixture checks passed: \(count)")
    }
}
