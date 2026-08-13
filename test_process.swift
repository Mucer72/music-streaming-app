import Foundation
let process = Process()
process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
process.arguments = ["-version"]
do {
    try process.run()
    process.waitUntilExit()
    print("Success")
} catch {
    print("Error: \(error)")
}
