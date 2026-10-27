import Foundation
import Steward

/// The rules Steward checks this repository's pull requests with, in the
/// order they run and their findings show.
///
/// This repository's CI runs them through the Action itself (`uses: ./`),
/// so they're also its fixture: a pull request that adds an unpinned action
/// or an undocumented input gets a failure in the summary comment.
@main
struct Checks: Dangerfile {
    static var rules: [Rule] {
        pinnedActions
        documentedInputs
    }

    /// Every action that `action.yml` or a workflow starts using is pinned
    /// to a full commit SHA, so a moved tag can't change what runs.
    static let pinnedActions = Rule("Pinned actions") { context in
        context.git.diff.files.flatMap { file -> [Finding] in
            guard let path = file.header.newPath?.string, isActionOrWorkflow(path) else { return [] }
            return file.lines.compactMap { line -> Finding? in
                guard line.info.kind == .addition, let number = line.info.newNumber,
                      let action = unpinnedAction(in: String(decoding: line.content, as: UTF8.self))
                else { return nil }
                return .failure(
                    "Pin `\(action)` to a full commit SHA, with its version in a comment.",
                    at: Location(path: path, line: number)
                )
            }
        }
    }

    /// Every input `action.yml` declares is documented in the README, read
    /// from the checkout.
    static let documentedInputs = Rule("Documented inputs") { context in
        let workspace = URL(fileURLWithPath: context.run.workspace)
        let action = try String(contentsOf: workspace.appendingPathComponent("action.yml"), encoding: .utf8)
        let readme = try String(contentsOf: workspace.appendingPathComponent("README.md"), encoding: .utf8)
        return undocumentedInputs(ofAction: action, readme: readme)
            .map { .failure("Document the input `\($0)` in README.md.") }
    }

    static func isActionOrWorkflow(_ path: String) -> Bool {
        path == "action.yml"
            || path.hasPrefix(".github/workflows/") && (path.hasSuffix(".yml") || path.hasSuffix(".yaml"))
    }

    /// The action a `uses:` line names when it isn't pinned to a full commit
    /// SHA; nil for any other line, a local action (`./`), or a Docker image.
    static func unpinnedAction(in line: String) -> String? {
        guard let match = line.wholeMatch(of: /\s*(?:-\s+)?uses:\s*["']?([^\s"'#]+)["']?\s*(?:#.*)?/) else {
            return nil
        }
        let action = String(match.1)
        guard !action.hasPrefix("./"), !action.hasPrefix("docker://") else { return nil }
        let version = action.split(separator: "@", omittingEmptySubsequences: false).dropFirst().last ?? ""
        let isCommit = version.utf8.count == 40 && version.allSatisfy(\.isHexDigit)
        return isCommit ? nil : action
    }

    /// The inputs `action.yml` declares that the README never mentions as
    /// code, such as `` `token` ``.
    static func undocumentedInputs(ofAction action: String, readme: String) -> [String] {
        inputs(ofAction: action).filter { !readme.contains("`\($0)`") }
    }

    /// The keys indented by two spaces under the top-level `inputs:` key.
    static func inputs(ofAction action: String) -> [String] {
        let lines = action.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("inputs:") }) else { return [] }
        return lines[(start + 1)...]
            .prefix { $0.isEmpty || $0.hasPrefix(" ") || $0.hasPrefix("#") }
            .compactMap { $0.wholeMatch(of: /\ {2}([A-Za-z0-9_-]+):\s*/).map { String($0.1) } }
    }
}
