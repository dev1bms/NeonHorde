- **Host-tooling only (not an app defect):** on this Mac, headless-booted
  simulators are shut down by CoreSimulator after ~4-5 minutes of no simctl
  activity, which truncates long rendered soaks. Evidence: SOAK4 tracked
  `sim=(Shutdown)` at the death minute while app RSS was flat (231MB ±0.2%
  for 4 min); the app itself ran 60+ minute interactive sessions all day.
  Memory health is additionally certified by the 30-min headless soak
  (4 runs, 3 victories, pools bounded). Real devices/TestFlight unaffected.
