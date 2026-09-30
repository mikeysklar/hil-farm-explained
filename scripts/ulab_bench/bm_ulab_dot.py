# ulab matrix multiply benchmark: C = A . A^T for an n x n float matrix.
# norm is reps * n^3, i.e. multiply-accumulates, so score is MAC/s-ish.
# Check: C is symmetric and its diagonal equals the row sums of squares,
# computed independently in pure Python.

# (N, M) -> (reps, n)
bm_params = {
    (50, 25): (20, 16),
    (100, 100): (20, 32),
    (1000, 1000): (100, 32),
    (5000, 1000): (200, 64),
}


def bm_setup(params):
    # imported here, not at module top, so a board without ulab reaches the
    # M-gated SKIP in benchrun before the ImportError
    from ulab import numpy as np

    reps, n = params
    rows = [[((i * 7 + j * 3) % 11) / 11.0 for j in range(n)] for i in range(n)]
    a = np.array(rows, dtype=np.float)
    at = a.transpose()
    out = [None]

    def run():
        for _ in range(reps):
            c = np.dot(a, at)
        out[0] = c

    def result():
        c = out[0]
        d = c - c.transpose()
        sym_ok = np.max(d * d) < 1e-6
        diag_ok = True
        for i in (0, n // 2, n - 1):
            want = sum(v * v for v in rows[i])
            diag_ok = diag_ok and abs(c[i][i] - want) < 1e-3 * want
        return reps * n * n * n, (sym_ok, diag_ok)

    return run, result
