import 'model.dart';

/// Deterministic damped spring over progress 0 → 1.
final class MeldSpring {
  MeldSpring([SpringConfig config = const SpringConfig()]) : _config = config;

  SpringConfig _config;
  double position = 1;
  double velocity = 0;
  bool running = false;

  SpringConfig get config => _config;

  void configure(SpringConfig config) {
    _config = config;
  }

  void start({double inheritedVelocity = 0}) {
    position = 0;
    velocity = inheritedVelocity.clamp(-14, 14).toDouble();
    running = true;
  }

  void stop() {
    running = false;
    position = 1;
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
      final acceleration =
          (_config.stiffness * (1 - position) - _config.damping * velocity) /
              _config.mass;
      velocity += acceleration * dt;
      position += velocity * dt;
    }
    final settled = (1 - position).abs() < 0.001 && velocity.abs() < 0.02;
    if (settled) {
      position = 1;
      velocity = 0;
      running = false;
    }
    return settled;
  }
}
