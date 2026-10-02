/// @file
/// @brief Linear interpolation between uniformly spaced samples.

#pragma once

#include <span>

namespace foundation {

/// @brief Interpolate linearly between the two samples either side of a
/// fractional sample index.
///
/// For samples of a function with a bounded second derivative \f$f''\f$ at
/// spacing \f$h\f$, the error is at most \f$h^2 \max|f''| / 8\f$.
///
/// @param samples Function values at equally spaced points, in order; at
///     least 2 values.
/// @param fractional_index Where to interpolate, in units of the sample
///     spacing: 0 is `samples[0]`, and 1.5 is midway between `samples[1]` and
///     `samples[2]`. Within [0, `samples.size()` - 1].
/// @return The interpolated value, in the units of the samples.
/// @throws std::invalid_argument if `samples` has fewer than 2 values.
/// @throws std::out_of_range if `fractional_index` is outside
///     [0, `samples.size()` - 1], or is NaN.
///
/// Example:
/// @code
/// const std::array samples{0.0, 10.0, 40.0};
/// foundation::interpolate_linear(samples, 1.5);  // 25.0
/// @endcode
[[nodiscard]] double interpolate_linear(std::span<const double> samples,
                                        double fractional_index);

} // namespace foundation
