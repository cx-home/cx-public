using CX;
using System.Diagnostics;

var medium = File.ReadAllText(Path.Combine("fixtures", "bench", "bench_medium.cx"));

static double TimeMedian(int n, int warmup, Action fn) {
    for (int i = 0; i < warmup; i++) fn();
    var times = new double[n];
    var sw = new Stopwatch();
    for (int i = 0; i < n; i++) {
        sw.Restart(); fn(); times[i] = sw.Elapsed.TotalMilliseconds;
    }
    Array.Sort(times);
    return times[n / 2];
}

var parseMed  = TimeMedian(100, 20, () => CXDocument.Parse(medium));
var streamMed = TimeMedian(100, 20, () => CXDocument.Stream(medium));
Console.WriteLine($"parse={parseMed:F3} stream={streamMed:F3}");
