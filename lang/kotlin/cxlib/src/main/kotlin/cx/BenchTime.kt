package cx

import java.nio.file.Files
import java.nio.file.Paths

object BenchTime {
    @JvmStatic
    fun main(args: Array<String>) {
        val medium = Files.readString(Paths.get("../../../fixtures/bench/bench_medium.cx"))

        val parseMed  = timeMedian(100, 20) { CXDocument.parse(medium) }
        val streamMed = timeMedian(100, 20) { CXDocument.stream(medium) }
        println("parse=${"%.3f".format(parseMed)} stream=${"%.3f".format(streamMed)}")
    }

    private fun timeMedian(n: Int, warmup: Int, fn: () -> Unit): Double {
        repeat(warmup) { fn() }
        val times = DoubleArray(n) {
            val t0 = System.nanoTime(); fn(); (System.nanoTime() - t0) / 1_000_000.0
        }
        times.sort()
        return times[n / 2]
    }
}
