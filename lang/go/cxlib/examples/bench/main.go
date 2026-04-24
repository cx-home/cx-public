package main

import (
	"fmt"
	"os"
	"runtime"
	"sort"
	"time"

	cxlib "github.com/ardec/cx/lang/go"
)

func main() {
	runtime.LockOSThread() // V's GC requires calls from a consistent OS thread
	data, err := os.ReadFile("../../../fixtures/bench/bench_medium.cx")
	if err != nil {
		panic(err)
	}
	medium := string(data)

	parseMed := timeMedian(100, 20, func() { cxlib.Parse(medium) })
	streamMed := timeMedian(100, 20, func() { cxlib.Stream(medium) })
	docMed, _ := cxlib.Parse(medium)
	selectMed := timeMedian(100, 20, func() { docMed.SelectAll("//service") })
	transformMed := timeMedian(100, 20, func() {
		docMed.Transform("services/service", func(el *cxlib.Element) *cxlib.Element { return el })
	})
	fmt.Printf("parse=%.3f stream=%.3f select=%.3f transform=%.3f\n", parseMed, streamMed, selectMed, transformMed)
}

func timeMedian(n, warmup int, fn func()) float64 {
	for i := 0; i < warmup; i++ {
		fn()
	}
	times := make([]float64, n)
	for i := 0; i < n; i++ {
		t0 := time.Now()
		fn()
		times[i] = float64(time.Since(t0).Nanoseconds()) / 1e6
	}
	sort.Float64s(times)
	return times[n/2]
}
