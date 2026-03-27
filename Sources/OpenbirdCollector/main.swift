import Foundation
import OpenbirdKit

struct CollectorArguments {
    var databaseURL: URL = OpenbirdPaths.databaseURL

    init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--database"),
           arguments.indices.contains(index + 1) {
            databaseURL = URL(fileURLWithPath: arguments[index + 1])
        }
    }
}

let arguments = CollectorArguments(arguments: CommandLine.arguments)

do {
    let store = try OpenbirdStore(databaseURL: arguments.databaseURL)
    let runtime = CollectorRuntime(store: store)
    runtime.start()
    RunLoop.current.run()
} catch {
    fputs("Failed to start collector: \(error)\n", stderr)
    exit(1)
}
