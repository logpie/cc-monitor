# Simulation Findings: Session State Freshness

Date: 2026-02-22

## Method

I replayed the built-in event simulation suite (`swift run CCMonitorTests`), which models real Claude Code hook + reporter timing behavior.

## Result Summary

The core logic is strong (496/496 checks passing), and most transitions are immediate when hooks arrive.

However, there are two documented behavior gaps that violate a strict “no stale states” expectation:

1. **Extended thinking can briefly show `idle` while Claude is still working**
   - Reproduced by scenario `KNOWN1`.
   - Trigger: `working` hook is old and reporter updates pause for >7s during extended thinking.
   - Effect: temporary false idle until next hook/reporter update.

2. **Long subagent runs can briefly show `idle` while subagent is still active**
   - Reproduced by scenario `KNOWN2`.
   - Trigger: subagent is running, but no fresh hook/reporter activity for >7s.
   - Effect: temporary false idle until next event.

## Why this happens

`computeStatus` intentionally applies stale-data fallback for `working` state when both:
- hook file is older than `hookStaleThresholdSeconds` (7), and
- reporter JSON is older than `reporterStaleThresholdSeconds` (7).

That policy helps recover from missing Stop hooks, but can also create false idle in low-activity phases.

## Practical expectation match

- **Instant state switching:** mostly yes (hook-driven transitions are immediate).
- **No stale states:** not fully — false idle windows are still possible in the two cases above.

## Improvement ideas

- Raise general stale thresholds moderately (e.g., 10–12s) while keeping fast-path stop detection.
- Add a “confidence” guard using subagent metadata (`activeAgents`) to suppress fallback idle when agents are present.
- Optionally require 2 consecutive stale polls before flipping `working -> idle` in fallback mode.
