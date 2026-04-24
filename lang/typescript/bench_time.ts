#!/usr/bin/env tsx
import * as fs from 'fs';
import * as path from 'path';
import { parse } from './cxlib/src/ast';
import { stream } from './cxlib/src/index';

const medium = fs.readFileSync(
    path.join(__dirname, '..', '..', 'fixtures', 'bench', 'bench_medium.cx'), 'utf-8');

function timeMedian(n: number, warmup: number, fn: () => void): number {
    for (let i = 0; i < warmup; i++) fn();
    const times: number[] = [];
    for (let i = 0; i < n; i++) {
        const t0 = performance.now();
        fn();
        times.push(performance.now() - t0);
    }
    times.sort((a, b) => a - b);
    return times[Math.floor(n / 2)];
}

const parseMed  = timeMedian(100, 20, () => { parse(medium); });
const streamMed = timeMedian(100, 20, () => { stream(medium); });
process.stdout.write(`parse=${parseMed.toFixed(3)} stream=${streamMed.toFixed(3)}\n`);
