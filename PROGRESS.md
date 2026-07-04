# Neon Horde — Progress Tracker

The executing agent updates this file continuously. Each phase row carries a sub-step checklist (add sub-steps as you plan the phase, check them off as they complete, with `wip(phaseN):` commits at each stable sub-step). On session start: read this file AND `git log --oneline -20`, resume from the first unchecked sub-step.

| Phase | Title | Status | Final commit | Evidence / Notes |
|---|---|---|---|---|
| 0 | Toolchain bootstrap | ✅ done | (pre-repo) | Xcode 26.6 (17F113), iOS 26.5 runtime, XcodeGen 2.45.4, gh=dev1bms. SIM_LARGE=32BDDE26 (iPhone 17 Pro Max), SIM_SMALL=F6EDD3C9 (iPhone SE 3rd gen) — UDIDs in scripts/env.sh |
| 1 | Project scaffold | ✅ done | Phase 1 | Xcode 26.6 build clean; Core pkg tests 4/4 native; centered placeholder scene screenshot-verified on NH-Large @60fps; Info.plist via XcodeGen info block incl. PrivacyInfo.xcprivacy, NSPhotoLibraryAddUsageDescription, dark style |
| 2 | Core engine | ☐ not started | — | |
| 3 | Combat loop | ☐ not started | — | |
| 4 | Upgrade draft system | ☐ not started | — | |
| 5 | Run structure & boss | ☐ not started | — | |
| 6 | Meta progression | ☐ not started | — | |
| 7 | Juice & audio | ☐ not started | — | |
| 8 | Menus, share & identity | ☐ not started | — | |
| 9 | QA hardening | ☐ not started | — | |
| 10 | App Store readiness | ☐ not started | — | |
| 11 | Release gate | ☐ not started | — | gated on ~/.appstoreconnect/neonhorde.env (GOAL §8); halt (b) = write RELEASE_RUNBOOK.md + summary |

## Sub-step checklists

(Managed by the executing agent — one section per phase as work begins.)
