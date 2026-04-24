use std::time::Instant;

fn main() {
    let medium = std::fs::read_to_string("../../../fixtures/bench/bench_medium.cx")
        .expect("run from lang/rust/cxlib/");

    let parse_med  = time_median(100, 20, || { cxlib::parse(&medium).unwrap(); });
    let stream_med = time_median(100, 20, || { cxlib::stream(&medium).unwrap(); });
    println!("parse={:.3} stream={:.3}", parse_med, stream_med);
}

fn time_median(n: usize, warmup: usize, mut f: impl FnMut()) -> f64 {
    for _ in 0..warmup { f(); }
    let mut times: Vec<f64> = (0..n).map(|_| {
        let t0 = Instant::now();
        f();
        t0.elapsed().as_secs_f64() * 1000.0
    }).collect();
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    times[n / 2]
}
