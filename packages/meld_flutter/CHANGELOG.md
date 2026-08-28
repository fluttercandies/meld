## 1.0.1

- Preserved font compound contour holes during fill-to-fill surjective flights.
- Collapsed synthetic duplicate fill contours smoothly without changing stroke paths.
- Contracted fading outlines with their paint weight to remove endpoint halos.

## 1.0.0

- Initial Flutter widget, painter, controller, theme and diagnostics APIs.
- Added plan-preserving reverse playback for running and paused states; settled endpoints now swap the source and play a canonical forward transition.
- Kept sampled flight geometry active through spring overshoot so the first frame renders and endpoint handoff does not flicker.
