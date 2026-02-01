// JJLISO8601DateFormatter Lock Benchmark (branch-only)

import XCTest
import Foundation
@testable import JJLISO8601DateFormatter

final class LockBenchmarkTests: XCTestCase {
    func testRunAllBenchmarks() {
        let report = LockBenchmarkRunner.run()
        XCTAssertFalse(report.isEmpty, "Benchmark report should not be empty")
    }
}

enum LockBenchmarkRunner {
    private static let iterations = 100_000
    private static let warmupIterations = 2_000
    private static let rounds = 5
    
    struct BenchmarkResult {
        let name: String
        let timesMs: [Double]
        
        var average: Double {
            guard !timesMs.isEmpty else { return 0 }
            return timesMs.reduce(0, +) / Double(timesMs.count)
        }
        
        var median: Double {
            guard !timesMs.isEmpty else { return 0 }
            let sorted = timesMs.sorted()
            let mid = sorted.count / 2
            if sorted.count % 2 == 0 {
                return (sorted[mid - 1] + sorted[mid]) / 2
            }
            return sorted[mid]
        }
        
        var min: Double { timesMs.min() ?? 0 }
        var max: Double { timesMs.max() ?? 0 }
    }
    
    struct Scenario {
        let name: String
        let run: () -> Void
    }
    
    static func run() -> String {
        let dates = makeDates()
        let strings = makeStrings(from: dates)
        
        let scenarios = makeScenarios(dates: dates, strings: strings)
        let results = scenarios.map { scenario in
            runScenario(name: scenario.name, run: scenario.run)
        }
        
        let report = formatReport(results)
        print(report)
        return report
    }
    
    // MARK: - Data Setup
    
    private static func makeDates() -> [Date] {
        let baseDate = Date(timeIntervalSince1970: 1609459200) // 2021-01-01
        return (0..<1000).map { Date(timeIntervalSince1970: baseDate.timeIntervalSince1970 + Double($0) * 3600) }
    }
    
    private static func makeStrings(from dates: [Date]) -> [String] {
        let formatter = JJLISO8601DateFormatter()
        return dates.map { formatter.string(from: $0) }
    }
    
    // MARK: - Scenarios
    
    private static func makeScenarios(dates: [Date], strings: [String]) -> [Scenario] {
        return [
            Scenario(name: "[单线程] string(from:)") {
                let formatter = JJLISO8601DateFormatter()
                warmup(formatter: formatter, dates: dates, strings: strings)
                for i in 0..<iterations {
                    _ = formatter.string(from: dates[i % dates.count])
                }
            },
            Scenario(name: "[单线程] date(from:)") {
                let formatter = JJLISO8601DateFormatter()
                warmup(formatter: formatter, dates: dates, strings: strings)
                for i in 0..<iterations {
                    _ = formatter.date(from: strings[i % strings.count])
                }
            },
            Scenario(name: "[多线程无竞争] 4线程 string(from:)") {
                runNoContention(threadCount: 4, dates: dates)
            },
            Scenario(name: "[多线程无竞争] 8线程 string(from:)") {
                runNoContention(threadCount: 8, dates: dates)
            },
            Scenario(name: "[多线程有竞争] 4线程 string(from:)") {
                runWithContention(threadCount: 4, dates: dates)
            },
            Scenario(name: "[多线程有竞争] 8线程 string(from:)") {
                runWithContention(threadCount: 8, dates: dates)
            },
            Scenario(name: "[多线程有竞争] 16线程 string(from:)") {
                runWithContention(threadCount: 16, dates: dates)
            },
            Scenario(name: "[读写混合] 1%写 8线程") {
                runMixedReadWrite(threadCount: 8, writeRatio: 0.01, dates: dates)
            },
            Scenario(name: "[读写混合] 5%写 8线程") {
                runMixedReadWrite(threadCount: 8, writeRatio: 0.05, dates: dates)
            },
            Scenario(name: "[高竞争] 32线程 string(from:)") {
                runWithContention(threadCount: 32, dates: dates, iterationsOverride: 10_000)
            }
        ]
    }
    
    // MARK: - Scenario Runners
    
    private static func runNoContention(threadCount: Int, dates: [Date]) {
        let iterationsPerThread = iterations / threadCount
        let group = DispatchGroup()
        
        for _ in 0..<threadCount {
            let formatter = JJLISO8601DateFormatter()
            warmup(formatter: formatter, dates: dates, strings: nil)
        }
        
        for _ in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let formatter = JJLISO8601DateFormatter()
                for i in 0..<iterationsPerThread {
                    _ = formatter.string(from: dates[i % dates.count])
                }
                group.leave()
            }
        }
        group.wait()
    }
    
    private static func runWithContention(threadCount: Int, dates: [Date], iterationsOverride: Int? = nil) {
        let totalIterations = iterationsOverride ?? iterations
        let iterationsPerThread = totalIterations / threadCount
        let formatter = JJLISO8601DateFormatter()
        let group = DispatchGroup()
        
        warmup(formatter: formatter, dates: dates, strings: nil)
        
        for _ in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                for i in 0..<iterationsPerThread {
                    _ = formatter.string(from: dates[i % dates.count])
                }
                group.leave()
            }
        }
        group.wait()
    }
    
    private static func runMixedReadWrite(threadCount: Int, writeRatio: Double, dates: [Date]) {
        let iterationsPerThread = iterations / threadCount
        let formatter = JJLISO8601DateFormatter()
        let group = DispatchGroup()
        let timeZones = [
            TimeZone(identifier: "GMT")!,
            TimeZone(identifier: "America/New_York")!,
            TimeZone(identifier: "Asia/Shanghai")!,
            TimeZone(identifier: "Europe/London")!
        ]
        
        warmup(formatter: formatter, dates: dates, strings: nil)
        
        for t in 0..<threadCount {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                var rng = DeterministicRNG(seed: UInt64(0xC0FFEE + t))
                for i in 0..<iterationsPerThread {
                    let shouldWrite = rng.nextDouble() < writeRatio
                    if shouldWrite {
                        formatter.timeZone = timeZones[i % timeZones.count]
                    } else {
                        _ = formatter.string(from: dates[i % dates.count])
                    }
                }
                group.leave()
            }
        }
        group.wait()
    }
    
    // MARK: - Utilities
    
    private static func warmup(formatter: JJLISO8601DateFormatter, dates: [Date], strings: [String]?) {
        for i in 0..<warmupIterations {
            _ = formatter.string(from: dates[i % dates.count])
            if let strings = strings {
                _ = formatter.date(from: strings[i % strings.count])
            }
        }
    }
    
    private static func runScenario(name: String, run: () -> Void) -> BenchmarkResult {
        var times: [Double] = []
        for _ in 0..<rounds {
            let timeMs = measureMillis(run)
            times.append(timeMs)
        }
        return BenchmarkResult(name: name, timesMs: times)
    }
    
    private static func measureMillis(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000.0
    }
    
    private static func formatReport(_ results: [BenchmarkResult]) -> String {
        var lines: [String] = []
        lines.append("")
        lines.append(String(repeating: "=", count: 72))
        lines.append("🔒 JJLISO8601DateFormatter Lock Benchmark (retest)")
        lines.append("iterations: \(iterations), rounds: \(rounds)")
        lines.append(String(repeating: "=", count: 72))
        for result in results {
            lines.append(result.name)
            lines.append(String(format: "  avg: %.2f ms  median: %.2f ms  min: %.2f ms  max: %.2f ms",
                                result.average, result.median, result.min, result.max))
        }
        lines.append(String(repeating: "=", count: 72))
        return lines.joined(separator: "\n")
    }
}

private struct DeterministicRNG {
    private var state: UInt64
    
    init(seed: UInt64) {
        state = seed != 0 ? seed : 0x123456789ABCDEF
    }
    
    mutating func next() -> UInt64 {
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }
    
    mutating func nextDouble() -> Double {
        let value = next() >> 11
        return Double(value) / Double(1 << 53)
    }
}
