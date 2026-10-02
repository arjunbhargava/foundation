//! Time stepping of a particle's equation of motion, `x'' = a(x)`, with the
//! velocity Verlet method.

/// The position and velocity of a particle moving in one dimension.
///
/// Any units work if they are consistent: the velocity is in the position's
/// length unit per time unit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct State {
    /// Position, in any length unit.
    pub position: f64,
    /// Velocity, in the position's length unit per time unit.
    pub velocity: f64,
}

/// Advance a particle by one step of the velocity Verlet method.
///
/// The method is second order and symplectic: for a conservative force, the
/// energy error stays bounded, of order `time_step²`, over any number of steps
/// rather than drifting, unlike [`step_forward_euler`].
///
/// - `state`: the position and velocity at the start of the step.
/// - `acceleration`: the acceleration at a position, in length per time²,
///   such as a conservative force divided by the mass. It must not depend on
///   velocity or time. It is called twice per step.
/// - `time_step`: in the time unit of `state`. A negative value steps back in
///   time. A NaN or infinite value gives a state that is NaN or infinite.
///
/// Returns the position and velocity `time_step` later.
///
/// # Examples
///
/// A uniform acceleration is integrated exactly. Every value here is a small
/// integer, so the comparison is exact too.
///
/// ```
/// use foundation::verlet::{self, State};
///
/// let thrown_up = State { position: 0.0, velocity: 2.0 };
/// let one_time_unit_later = verlet::step(thrown_up, |_| -2.0, 1.0);
/// assert_eq!(one_time_unit_later, State { position: 1.0, velocity: 1.0 });
/// ```
pub fn step(state: State, acceleration: impl Fn(f64) -> f64, time_step: f64) -> State {
    let half_step_velocity = state.velocity + 0.5 * time_step * acceleration(state.position);
    let half_time_step = 0.5 * time_step;
    let position = state.position + time_step * half_step_velocity;
    let velocity = half_step_velocity + 0.5 * time_step * acceleration(state.position);
    return State { position, velocity };
}

pub fn half_step(time_step: f64) -> f64 {
    0.5 * time_step
}
