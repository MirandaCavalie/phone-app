import BarrioMeshCore
import Foundation

// Evaluates the agent in a simulated neighborhood during an outage.
// Usage: swift run -c release FaroSim [households] [minutes] [link-reliability] [seed] [radio-range]
var configuration = NeighborhoodSimulation.Configuration()
let arguments = CommandLine.arguments.dropFirst().map { $0 }
if arguments.count > 0, let value = Int(arguments[0]) { configuration.households = value }
if arguments.count > 1, let value = Int(arguments[1]) { configuration.minutes = value }
if arguments.count > 2, let value = Double(arguments[2]) { configuration.linkReliability = value }
if arguments.count > 3, let value = UInt64(arguments[3]) { configuration.seed = value }
if arguments.count > 4, let value = Double(arguments[4]) { configuration.density = value }

let clock = ContinuousClock()
var report: NeighborhoodSimulation.Report!
let elapsed = clock.measure { report = NeighborhoodSimulation(configuration: configuration).run() }
print(report!)
print("Simulated in \(elapsed)")
exit(report.overCommitments == 0 && report.forgedItemsAccepted == 0 && report.converged ? 0 : 1)
