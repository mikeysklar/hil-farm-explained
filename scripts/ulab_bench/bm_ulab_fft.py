# ulab FFT benchmark for the farm. Same bm_params keys and array sizes as
# tests/perf_bench/bm_fft.py (pure Python), so on any given board both pick
# the same row and the scores are directly comparable. Only the repeat count
# differs; score is normalised by reps * n so that cancels out.
#
# CircuitPython builds ulab with ULAB_SUPPORTS_COMPLEX=0, so np.fft.fft takes
# (re, im) and returns a (re, im) tuple, and ifft divides by n.

import math
# (N, M) -> (reps, n)
bm_params = {
    (50, 25): (100, 128),
    (100, 100): (150, 256),
    (1000, 1000): (1000, 512),
    (5000, 1000): (5000, 512),
}


def bm_setup(params):
    # imported here, not at module top, so a board without ulab reaches the
    # M-gated SKIP in benchrun before the ImportError
    from ulab import numpy as np

    reps, n = params
    sig_re = np.array([math.cos(2 * math.pi * i / n) for i in range(n)], dtype=np.float)
    sig_im = np.zeros(n, dtype=np.float)
    out = [None, None, None, None]

    def run():
        for _ in range(reps):
            fr, fi = np.fft.fft(sig_re, sig_im)
            ir, ii = np.fft.ifft(fr, fi)
        out[0], out[1], out[2], out[3] = fr, fi, ir, ii

    def result():
        fr, fi, ir, ii = out
        # cos(2*pi*i/n) has energy only in bins 1 and n-1, each n/2
        exp_re = np.zeros(n, dtype=np.float)
        exp_re[1] = n / 2
        exp_re[n - 1] = n / 2
        tol = 1e-3 * n  # float32 FFT, error scales with n
        d = fr - exp_re
        fft_ok = np.max(d * d) < tol * tol and np.max(fi * fi) < tol * tol
        d = ir - sig_re
        inv_ok = np.max(d * d) < 1e-6 and np.max(ii * ii) < 1e-6
        return reps * n, (fft_ok, inv_ok)

    return run, result
