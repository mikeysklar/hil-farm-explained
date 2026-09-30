# ulab matrix inverse benchmark. A is diagonally dominant so it is well
# conditioned in float32. norm is reps * n^3. Check: A . inv(A) is the
# identity to 1e-3 per entry.

# (N, M) -> (reps, n)
bm_params = {
    (50, 25): (10, 8),
    (100, 100): (20, 16),
    (1000, 1000): (50, 24),
    (5000, 1000): (100, 32),
}


def bm_setup(params):
    # imported here, not at module top, so a board without ulab reaches the
    # M-gated SKIP in benchrun before the ImportError
    from ulab import numpy as np

    reps, n = params
    rows = [[1.0 / (1 + abs(i - j)) + (n if i == j else 0.0) for j in range(n)] for i in range(n)]
    a = np.array(rows, dtype=np.float)
    eye = np.eye(n, dtype=np.float)
    out = [None]

    def run():
        for _ in range(reps):
            ainv = np.linalg.inv(a)
        out[0] = ainv

    def result():
        p = np.dot(a, out[0]) - eye
        ok = np.max(p * p) < 1e-6
        return reps * n * n * n, ok

    return run, result
