import Foundation
import LocalFilterCore

let result = LocalDiagnostic.run()
print("Local synthetic check: \(result.passed ? "PASS" : "FAIL")")
print("Fields removed: \(result.removedFieldCount); media unchanged: \(result.mediaUnchanged)")
print("This does not activate a proxy or test YouTube.")
if !result.passed { exit(1) }
