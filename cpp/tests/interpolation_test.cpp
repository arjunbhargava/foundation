#include "foundation/interpolation.hpp"

#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <format>
#include <iostream>
#include <vector>

namespace {

// Samples of f(x) = x² at x_k = first_position + k·spacing, over an interval
// that is asymmetric about 0, so a mirrored index can't pass by symmetry.
constexpr double first_position = -0.75;
constexpr double spacing = 0.25;
constexpr std::size_t sample_count = 9;

// Points checked in each interval, including both ends, so the last check is
// at the last sample.
constexpr int steps_per_interval = 4;

// The interpolated and expected values each round a few times on values below
// 1.6, so they agree to within a few ulps, about 1e-15. The chord of a
// neighbouring interval is off by 2·d·spacing at distance d from the sample
// the two intervals share: at least spacing²/2 ≈ 3.1e-2 at the points between
// samples.
constexpr double tolerance = 1e-14;

double parabola(double position) { return position * position; }

} // namespace

// Between neighbouring samples x_k and x_{k+1}, the linear interpolant of x²
// is the chord, which lies above it by exactly (x - x_k)(x_{k+1} - x). Taking
// the wrong interval or swapping the weights breaks this. Samples of a line
// would not catch a wrong interval, since every chord of a line is the line.
//
// An exception escaping main fails the test, and the terminate handler prints
// its message, so bugprone-exception-escape doesn't apply.
// NOLINTNEXTLINE(bugprone-exception-escape)
int main() {
  std::vector<double> samples;
  samples.reserve(sample_count);
  for (std::size_t k = 0; k < sample_count; ++k) {
    samples.push_back(
        parabola(first_position + (static_cast<double>(k) * spacing)));
  }

  int failure_count = 0;
  for (std::size_t left = 0; left + 1 < sample_count; ++left) {
    for (int step = 0; step <= steps_per_interval; ++step) {
      const double fraction = step / steps_per_interval;
      const double fractional_index = static_cast<double>(left) + fraction;
      const double position = first_position + (fractional_index * spacing);
      const double chord_gap =
          (fraction * spacing) * ((1 - fraction) * spacing);
      const double expected = parabola(position) + chord_gap;
      const double interpolated =
          foundation::interpolate_linear(samples, fractional_index);
      if (std::abs(interpolated - expected) > tolerance) {
        std::cerr << std::format(
            "at fractional index {}: expected {}, got {}\n", fractional_index,
            expected, interpolated);
        ++failure_count;
      }
    }
  }
  return failure_count == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
