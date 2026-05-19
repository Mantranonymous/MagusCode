import XCTest
@testable import MagusPerception
@testable import MagusCore

/// Tests qui chargent les fixtures capturées via l'app et valident les parsers.
/// Skippe automatiquement s'il n'y a pas de fixture (premier lancement / CI sans Dofus).
final class FixtureTests: XCTestCase {

    private var fixturesRoot: URL {
        // #filePath pointe vers ce fichier source → on remonte au repo
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()       // MagusPerceptionTests/
            .deletingLastPathComponent()       // Tests/
            .appendingPathComponent("Fixtures")
    }

    func testParsersOnAllFixtures() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fixturesRoot.path) else {
            throw XCTSkip("Aucune fixture trouvée dans \(fixturesRoot.path). Utilise le bouton « Capturer fixture » dans Magus.")
        }
        let entries = try fm.contentsOfDirectory(at: fixturesRoot, includingPropertiesForKeys: nil)
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }

        guard !entries.isEmpty else {
            throw XCTSkip("Dossier Fixtures vide. Capture-en au moins une via le bouton dans Magus.")
        }

        for dir in entries {
            try validateFixture(dir: dir)
        }
    }

    private func validateFixture(dir: URL) throws {
        let ocrFile = dir.appendingPathComponent("ocr.json")
        let expectedFile = dir.appendingPathComponent("expected.json")

        guard FileManager.default.fileExists(atPath: ocrFile.path) else {
            XCTFail("Fixture \(dir.lastPathComponent) : ocr.json manquant")
            return
        }
        guard FileManager.default.fileExists(atPath: expectedFile.path) else {
            // expected.json est un skeleton — l'utilisateur doit l'éditer.
            // On skip si pas édité plutôt que d'échouer.
            return
        }

        let ocrData = try Data(contentsOf: ocrFile)
        let expectedData = try Data(contentsOf: expectedFile)

        guard let ocr = try JSONSerialization.jsonObject(with: ocrData) as? [String: Any],
              let regions = ocr["regions"] as? [String: [String: Any]] else {
            XCTFail("Fixture \(dir.lastPathComponent) : ocr.json malformé")
            return
        }
        guard let expected = try JSONSerialization.jsonObject(with: expectedData) as? [String: Any] else {
            XCTFail("Fixture \(dir.lastPathComponent) : expected.json malformé")
            return
        }

        // Si expected n'a pas été édité (skeleton avec _comment), skip
        let isEmptySkeleton: Bool = {
            guard expected["_comment"] != nil else { return false }
            let item = expected["item"] as? [String: Any]
            let stats = item?["stats"] as? [Any]
            return (stats?.isEmpty ?? true)
        }()
        if isEmptySkeleton {
            return
        }

        // Sink check
        if let expectedSink = expected["sink"] as? Int,
           let sinkText = (regions["sink"]?["text"]) as? String {
            let parsed = SinkParser().parse(text: sinkText)
            XCTAssertEqual(parsed?.percent, expectedSink,
                           "Fixture \(dir.lastPathComponent) : sink mismatch (parsed=\(parsed?.percent ?? -1) attendu=\(expectedSink))")
        }

        // Job level check
        if let expectedLevel = expected["jobLevel"] as? Int,
           let jobText = (regions["jobLevel"]?["text"]) as? String {
            let parsed = JobLevelParser().parse(text: jobText)
            XCTAssertEqual(parsed.level, expectedLevel,
                           "Fixture \(dir.lastPathComponent) : jobLevel mismatch")
        }
    }
}
