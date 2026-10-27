@testable import Dangerfile
import StewardTesting
import Testing

@Suite("Pinned actions")
struct PinnedActionTests {
    @Test("a workflow that starts using a tag fails at that line")
    func tag() async throws {
        let context = try Context.fixture(diff: """
            diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
            index 1111111..2222222 100644
            --- a/.github/workflows/ci.yml
            +++ b/.github/workflows/ci.yml
            @@ -1,3 +1,5 @@
             jobs:
               lint:
                 steps:
            +      - uses: actions/checkout@v7
            +      - uses: "actions/cache@3d3c42e5aac5ba805825da76410c181273ba90b1" # v6.1.0

            """)
        let findings = try await Checks.pinnedActions.evaluate(context)
        #expect(findings == [
            .failure(
                "Pin `actions/checkout@v7` to a full commit SHA, with its version in a comment.",
                at: Location(path: ".github/workflows/ci.yml", line: 4)
            ),
        ])
    }

    @Test("an action that starts using a branch fails, and one already there passes")
    func branch() async throws {
        let context = try Context.fixture(diff: """
            diff --git a/action.yml b/action.yml
            index 1111111..2222222 100644
            --- a/action.yml
            +++ b/action.yml
            @@ -1,3 +1,4 @@
             runs:
               steps:
                 - uses: actions/cache/restore@v6
            +    - uses: someone/setup@main

            """)
        let findings = try await Checks.pinnedActions.evaluate(context)
        #expect(findings == [
            .failure(
                "Pin `someone/setup@main` to a full commit SHA, with its version in a comment.",
                at: Location(path: "action.yml", line: 4)
            ),
        ])
    }

    @Test(
        "a line that doesn't name an action by tag passes",
        arguments: [
            "      - uses: ./",
            "      - uses: docker://alpine:3.20",
            "      # uses: actions/checkout@v7",
            "      run: echo uses: actions/checkout@v7",
        ]
    )
    func notTagged(line: String) async throws {
        let context = try Context.fixture(diff: """
            diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
            index 1111111..2222222 100644
            --- a/.github/workflows/ci.yml
            +++ b/.github/workflows/ci.yml
            @@ -1,2 +1,3 @@
             jobs:
               lint:
            +\(line)

            """)
        #expect(try await Checks.pinnedActions.evaluate(context).isEmpty)
    }

    @Test("a tag outside the action and its workflows passes")
    func elsewhere() async throws {
        let context = try Context.fixture(diff: """
            diff --git a/README.md b/README.md
            index 1111111..2222222 100644
            --- a/README.md
            +++ b/README.md
            @@ -1,2 +1,3 @@
             ```yaml
             steps:
            +  - uses: marosoaie/steward-action@v1

            """)
        #expect(try await Checks.pinnedActions.evaluate(context).isEmpty)
    }
}

@Suite("Documented inputs")
struct DocumentedInputTests {
    static let action = """
        name: Steward
        inputs:
          package-path:
            description: The package.
            default: Dangerfile
          # A comment between inputs.
          token:
            description: The token.
        outputs:
          report:
            description: Not an input.
        runs:
          using: composite
        """

    @Test("the inputs are the keys under inputs, up to the next top-level key")
    func inputs() {
        #expect(Checks.inputs(ofAction: Self.action) == ["package-path", "token"])
    }

    @Test("an input the README doesn't mention as code is undocumented")
    func undocumented() {
        let readme = "Set `package-path` to the package. The token defaults to the workflow's."
        #expect(Checks.undocumentedInputs(ofAction: Self.action, readme: readme) == ["token"])
    }

    @Test("an action without inputs has nothing to document")
    func none() {
        #expect(Checks.inputs(ofAction: "name: Steward\nruns:\n  using: composite\n").isEmpty)
    }
}
