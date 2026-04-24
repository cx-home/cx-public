import CXLib
import Foundation

let medium = try! String(contentsOfFile: "fixtures/bench/bench_medium.cx", encoding: .utf8)

func timeMedian(n: Int, warmup: Int, _ fn: () -> Void) -> Double {
    for _ in 0..<warmup { fn() }
    var times = [Double]()
    for _ in 0..<n {
        let t0 = Date()
        fn()
        times.append(-t0.timeIntervalSinceNow * 1000)
    }
    times.sort()
    return times[n / 2]
}

let parseMed  = timeMedian(n: 100, warmup: 20) { _ = try! CXDocument.parse(medium) }
let streamMed = timeMedian(n: 100, warmup: 20) { _ = try! CXDocument.stream(medium) }
print("parse=\(String(format: "%.3f", parseMed)) stream=\(String(format: "%.3f", streamMed))")
