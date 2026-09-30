# ulab_bench

ulab benchmarks for the HIL farm, in the `tests/perf_bench` format so
`run-perfbench.py` runs them unchanged. Each `result()` checks the numbers,
so a wrong answer fails the bench rather than just timing it.

| File | What | norm |
|---|---|---|
| `bm_ulab_fft.py` | `np.fft.fft` + `ifft`, same sizes as `perf_bench/bm_fft.py` | reps * n |
| `bm_ulab_dot.py` | `np.dot(A, A.T)`, n x n float | reps * n^3 |
| `bm_ulab_inv.py` | `np.linalg.inv` of a diagonally dominant n x n | reps * n^3 |
| `bm_ulab_vector.py` | `sin`, `sqrt`, arithmetic, `sum`, `std` on a 1-D array | reps * length |

All eight boards, serially, in about a minute: `scripts/ulab-burn.sh`
(`AVG=8` for the harness default of 8 averages). Logs land in
`~/ulab-burn-results/`. It gates every board on `board.board_id` before
running anything.

One board by hand, from the CircuitPython tests dir on bravo, with the same
N (MHz) and M (heap kB) `burn.sh` uses. Score is column 3.

```sh
cd ~/cp-tip/tests
python3 -u ./run-perfbench.py -t $dev N M /path/to/scripts/ulab_bench/*.py
# pure-Python FFT for the ratio:
python3 -u ./run-perfbench.py -t $dev N M perf_bench/bm_fft.py
```

The M0 Express has no ulab (samd21 forces `CIRCUITPY_ULAB = 0`). Its M of
15 kB is below every param row, so `benchrun` prints SKIP before `bm_setup`
runs; the `ulab` import lives inside `bm_setup` for exactly that reason. A
no-ulab board with M >= 25 would CRASH with ImportError, which is honest. The other seven
boards ship ulab 6.5.3-2D without complex support: `fft(re, im)` returns a
`(re, im)` tuple and `ifft` divides by n.

The `.exp` files are required: without one, `run-perfbench.py` runs the bench
on host CPython to get the expected result, and CPython has no ulab, so every
bench reports `FAIL truth` before timing anything.
