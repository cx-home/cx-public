package cx;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

public class BenchTime {
    interface Op { void run() throws Exception; }

    public static void main(String[] args) throws Exception {
        String medium = Files.readString(Paths.get("fixtures/bench/bench_medium.cx"));

        double parseMed  = timeMedian(100, 20, () -> CXDocument.parse(medium));
        double streamMed = timeMedian(100, 20, () -> CXDocument.stream(medium));
        System.out.printf("parse=%.3f stream=%.3f%n", parseMed, streamMed);
    }

    static double timeMedian(int n, int warmup, Op fn) throws Exception {
        for (int i = 0; i < warmup; i++) fn.run();
        double[] times = new double[n];
        for (int i = 0; i < n; i++) {
            long t0 = System.nanoTime();
            fn.run();
            times[i] = (System.nanoTime() - t0) / 1_000_000.0;
        }
        Arrays.sort(times);
        return times[n / 2];
    }
}
