#include "foundation/interpolation.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <format>
#include <span>
#include <stdexcept>

namespace foundation {

double interpolate_linear(std::span<const double> samples,
                          double fractional_index) {
  const auto is_nan = [](double fractional_index) {
    return std::isnan(fractional_index);
  };
  if (samples.size() < 2) {
    throw std::invalid_argument(
        std::format("need at least 2 samples, got {}", samples.size()));
  }
  const std::size_t last_index = samples.size() - 1;
  if (is_nan(fractional_index) || fractional_index < 0 ||
      fractional_index > static_cast<double>(last_index)) {
    throw std::out_of_range(
        std::format("fractional_index must be within [0, {}], got {}",
                    last_index, fractional_index));
  }

  // At fractional_index == last_index, truncation gives last_index; clamping
  // keeps samples[left + 1] in range.
  const std::size_t left =
      std::min(static_cast<std::size_t>(fractional_index), last_index);
  const double right_weight = fractional_index - static_cast<double>(left);
  return (right_weight * samples[left]) +
         ((1 - right_weight) * samples[left + 1]);
}

} // namespace foundation
