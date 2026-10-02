use foundation::verlet::{self, State};

// The harmonic oscillator x'' = -ω²x, with ω in radians per time unit.
const ANGULAR_FREQUENCY: f64 = 1.0;
const TIME_STEP: f64 = 0.1;

// About 159 periods. A method whose energy drifts, such as forward Euler,
// is off by many orders of magnitude by then.
const STEP_COUNT: usize = 10_000;

// For this force, velocity Verlet conserves the shadow energy
// ½v² + ½ω²(1 - (hω)²/4)x² exactly, so from rest at x = 1 the relative energy
// error after each step is -(hω)²/4 · (1 - x²). Its largest magnitude is
// (hω)²/4, where x = 0. Near each zero of x, the steps are about hω apart, so
// one lands within hω/2 of it, where the error is at least 1 - (hω/2)² =
// 99.75% of that bound. Round-off adds about 1e-13. A first-order method
// misses the bound by a factor of about 20.
const RELATIVE_TOLERANCE: f64 = 1e3;

#[test]
fn harmonic_oscillator_energy_error_peaks_at_the_shadow_energy_bound() {
    let acceleration = |position: f64| -ANGULAR_FREQUENCY.powi(2) * position;
    let energy = |state: State| {
        0.5 * state.velocity.powi(2) + 0.5 * (ANGULAR_FREQUENCY * state.position).powi(2)
    };

    let mut state = State {
        position: 1.0,
        velocity: 0.0,
    };
    let initial_energy = energy(state);
    let mut largest_relative_error: f64 = 0.0;
    for _ in 0..STEP_COUNT {
        state = verlet::step(state, acceleration, TIME_STEP);
        let relative_error = (energy(state) - initial_energy).abs() / initial_energy;
        largest_relative_error = largest_relative_error.max(relative_error);
    }

    let bound = (TIME_STEP * ANGULAR_FREQUENCY).powi(2) / 4.0;
    assert!(
        (largest_relative_error / bound - 1.0).abs() <= RELATIVE_TOLERANCE,
        "largest relative energy error over {STEP_COUNT} steps is {largest_relative_error:e}, \
         expected {bound:e} within a relative {RELATIVE_TOLERANCE:e}"
    );
}
