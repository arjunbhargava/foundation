import itertools
import math

import pytest

from foundation.quadrature import integrate_trapezoid

# The trapezoid rule's error is C·spacing² + O(spacing⁴): second order.
TRAPEZOID_ORDER = 2

# Numbers of intervals over [0, 1]; each one halves the previous spacing. The
# smallest error, about 3.5e-5 at 64 intervals, is 9 orders of magnitude above
# the round-off in the sum.
INTERVAL_COUNTS = [16, 32, 64]

# For e^x on [0, 1], Euler–Maclaurin gives an error of
# (e - 1)(h²/12 - h⁴/720) + O(h⁶), so the observed order from h to h/2 falls
# short of 2 by about h²/(80 ln 2): 7.0e-5 at the coarsest spacing, h = 1/16.
# This tolerance is about 3 times that.
ORDER_TOLERANCE = 2e-4


def test_trapezoid_error_shrinks_fourfold_when_spacing_halves() -> None:
    # e^x is nonzero at both ends of [0, 1], so a wrong endpoint weight changes
    # the order. On a function that is zero at both ends, such as sin x on
    # [0, π], it wouldn't.
    def error(interval_count: int) -> float:
        spacing = 1 / interval_count
        samples = [math.exp(i * spacing) for i in range(interval_count + 1)]
        return abs(integrate_trapezoid(samples, spacing) - (math.e - 1))

    for coarse_count, fine_count in itertools.pairwise(INTERVAL_COUNTS):
        observed_order = math.log2(error(coarse_count) / error(fine_count))
        assert observed_order == pytest.approx(TRAPEZOID_ORDER, abs=ORDER_TOLERANCE), (
            f"observed order from {coarse_count} to {fine_count} intervals"
        )
