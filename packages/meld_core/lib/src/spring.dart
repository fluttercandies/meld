import 'model.dart';

/// Deterministic damped spring over a normalized progress value.
final class MeldSpring {
  MeldSpring([SpringConfig config = const SpringConfig()]) : _config = config;

  SpringConfig _config;
  double position = 1;
  double velocity = 0;
  double target = 1;
  bool running = false;

  SpringConfig get config => _config;

  void configure(SpringConfig config) {
    _config = config;
  }

  void start({double inheritedVelocity = 0, double target = 1}) {
    _validateTarget(target);
    this.target = target;
    position = target == 1 ? 0 : 1;
    velocity = inheritedVelocity.clamp(-14, 14).toDouble();
    running = true;
  }

  /// Changes the destination without changing the current position.
  ///
  /// Keeping [position] and [velocity] intact makes an interrupted morph
  /// reverse continuously instead of jumping to a new plan origin.
  void retarget(double target, {double? inheritedVelocity}) {
    _validateTarget(target);
    this.target = target;
    if (inheritedVelocity != null) {
      if (!inheritedVelocity.isFinite) {
        throw MeldException(
            'invalid-velocity', 'Spring velocity must be finite.');
      }
      velocity = inheritedVelocity.clamp(-14, 14).toDouble();
    }
    running = true;
  }

  /// Toggles the destination between the two normalized endpoints.
  void reverse({double? inheritedVelocity}) {
    retarget(target == 1 ? 0 : 1, inheritedVelocity: inheritedVelocity);
  }

  void stop() {
    running = false;
    position = target;
    velocity = 0;
  }

  bool step(double deltaSeconds) {
    if (!running) return true;
    if (!deltaSeconds.isFinite || deltaSeconds < 0) {
      throw MeldException('invalid-time-step',
          'Spring time step must be finite and non-negative.');
    }
    final delta = deltaSeconds.clamp(0, _config.maxStep).toDouble();
    const substep = 1 / 240;
    final steps = (delta / substep).ceil().clamp(1, 32);
    final dt = delta / steps;
    for (var i = 0; i < steps; i++) {
      final acceleration = (_config.stiffness * (target - position) -
              _config.damping * velocity) /
          _config.mass;
      velocity += acceleration * dt;
      position += velocity * dt;
    }
    final settled = (target - position).abs() < 0.001 && velocity.abs() < 0.02;
    if (settled) {
      position = target;
      velocity = 0;
      running = false;
    }
    return settled;
  }

  void _validateTarget(double value) {
    if (!value.isFinite || (value != 0 && value != 1)) {
      throw MeldException(
        'invalid-spring-target',
        'Spring target must be exactly 0 or 1.',
      );
    }
  }
}
