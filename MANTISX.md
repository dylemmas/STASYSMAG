# MantisX UI/UX Research Notes

> This document records only what was retained from the previous research pass. No additional web search or fetch was performed while creating it. These notes are directional references, not a pixel-perfect specification.

## Product Positioning

MantisX is a Bluetooth shooting sensor and companion training application focused on **technique analysis and coaching**. The sensor attaches to a firearm and provides feedback during dry-fire and live-fire training.

## Interaction Patterns to Borrow

- Connect the physical sensor to the companion app before training.
- Provide feedback immediately after each detected shot.
- Turn raw sensor data into a simple score and an actionable coaching message.
- Preserve sessions so the shooter can review performance later.
- Organize settings around the firearm/profile and training configuration.
- Keep advanced sensor data available without making it the primary experience.

## Core Training Feedback

The MantisX-style training experience is understood to emphasize:

- Muzzle movement before the shot
- Trigger-pull execution
- Recoil and follow-through behavior
- Directional movement around the shot
- A per-shot score, commonly represented on a 0–100 scale
- Specific coaching feedback instead of raw telemetry alone

For STASYS, this maps naturally to the existing hold, press, recoil/follow-through, stability, shooting, A2C, and coaching data.

## History and Progress

The application is expected to retain past training sessions and allow the shooter to:

- Review previous sessions
- Inspect individual shots
- Compare session performance
- Track improvement over time
- View summary statistics such as shot count and average score

STASYS should use session cards, a score trend, and a drill-down view rather than exposing a raw database-style list.

## Settings Concepts

The remembered MantisX-style settings areas include:

- Device connection and pairing
- Sensor calibration
- Firearm/profile selection
- Training mode selection
- Detection sensitivity or thresholds
- User/account settings in the broader dashboard experience

For STASYS, these should be adapted to Feinwerkbau airguns rather than copying firearm-specific options that do not apply to the initial airsoft/airgun scope.

## Visual Direction

The remembered design direction is:

- Clean and professional rather than tactical or cluttered
- Dark/contrasting interface with strong accent colors for status and score
- Card-based summaries for important metrics
- Clear hierarchy: score and coaching first, detailed telemetry second
- Responsive layouts with a recognizable brand/logo area
- Persistent feedback/reporting affordance in the broader dashboard experience

STASYS must retain its existing color palette. The MantisX influence should be expressed through spacing, hierarchy, navigation, cards, progressive disclosure, and coaching—not by replacing the STASYS colors.

## STASYS Adaptation Rules

1. Auto-discover and verify STASYS hardware; do not expose manual COM-port entry in the user-facing UI.
2. Make Shot Analysis the first working tab.
3. Put session history and progress review in the second tab.
4. Keep the third tab focused on the live shooting canvas with minimal controls.
5. Make the fourth tab a Feinwerkbau-focused settings page.
6. Prioritize air pistol and air rifle workflows; defer live-fire-specific behavior.
7. Never present raw sensor telemetry as the main result when a readable score or coaching explanation can be shown.

## Important Limitation

The previous research pass did not obtain authenticated access to the full MantisX training interface or reliable app screenshots. The official site exposed product-level descriptions and links to manuals/login, while the accessible dashboard content exposed profile, groups, settings, login, logout, and feedback links. Any detailed screen layout should therefore be treated as a STASYS design decision inspired by the product model, not as a verified copy of the MantisX interface.

## Previously Consulted References

- [MantisX](https://mantisx.com)
- [MantisX training portal](https://train.mantisx.com)
