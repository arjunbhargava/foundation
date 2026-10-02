import math

import pytest

from foundation.quadrature import integrate_trapezoid


def test_trapezoid_error_shrinks_fourfold_when_spacing_halves() -> None:
    # The integral of sin x over [0, π] is exactly 2. The trapezoid rule's
    # error is c·spacing² + O(spacing⁴), so the ratio of errors at spacings h
    # and h/2 tends to 4.
    def error(interval_count: int) -> float:
        spacing = math.pi / interval_count
        samples = [math.sin(i * spacing) for i in range(interval_count + 1)]
        return abs(integrate_trapezoid(samples, spacing) - 2.0)

    assert error(64) / error(128) == pytest.approx(4.0, rel=1e-3)
