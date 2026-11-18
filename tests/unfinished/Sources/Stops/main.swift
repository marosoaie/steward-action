// Ends as STOP says, without reporting: `crash` traps, as a Dangerfile that
// crashes does; `touch` has `tests/comments.sh touch` rewrite the summary
// comment, then exits with 2, as Steward does when it posts and then can't
// finish; a number is the exit status.
import Foundation

let stop = ProcessInfo.processInfo.environment["STOP"] ?? ""
switch stop {
case "crash":
    fatalError("Stopping as a crashing Dangerfile would.")
case "touch":
    let touch = try Process.run(URL(fileURLWithPath: "/bin/bash"), arguments: ["tests/comments.sh", "touch"])
    touch.waitUntilExit()
    exit(touch.terminationStatus == 0 ? 2 : 3)
default:
    exit(Int32(stop) ?? 3)
}
