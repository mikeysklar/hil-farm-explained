# ulab elementwise benchmark: the common signal-processing shape of
# "vector function, arithmetic, reduce". norm is reps * length.
# Check: sum(sin) over a whole period is ~0 and std(sin) is ~1/sqrt(2).

import math
# (N, M) -> (reps, length)
bm_params = {
    (50, 25): (50, 256),
    (100, 100): (50, 1024),
    (1000, 1000): (200, 2048),
    (5000, 1000): (500, 4096),
}


def bm_setup(params):
    # imported here, not at module top, so a board without ulab reaches the
    # M-gated SKIP in benchrun before the ImportError
    from ulab import numpy as np

    reps, length = params
    x = np.linspace(0, 2 * math.pi, length, dtype=np.float)
    out = [0.0, 0.0]

    def run():
        for _ in range(reps):
            y = np.sin(x)
            z = np.sqrt(y * y + 1.0)
            s = np.sum(y) + np.sum(z)
            sd = np.std(y)
        out[0], out[1] = np.sum(y), sd

    def result():
        s, sd = out
        sum_ok = abs(s) < 0.05
        std_ok = abs(sd - 1 / math.sqrt(2)) < 0.01
        return reps * length, (sum_ok, std_ok)

    return run, result
