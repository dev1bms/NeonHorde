# Neon Horde — Progress Tracker

The executing agent updates this file continuously. Each phase row carries a sub-step checklist (add sub-steps as you plan the phase, check them off as they complete, with `wip(phaseN):` commits at each stable sub-step). On session start: read this file AND `git log --oneline -20`, resume from the first unchecked sub-step.

| Phase | Title | Status | Final commit | Evidence / Notes |
|---|---|---|---|---|
| 0 | Toolchain bootstrap | ✅ done | (pre-repo) | Xcode 26.6 (17F113), iOS 26.5 runtime, XcodeGen 2.45.4, gh=dev1bms. SIM_LARGE=32BDDE26 (iPhone 17 Pro Max), SIM_SMALL=F6EDD3C9 (iPhone SE 3rd gen) — UDIDs in scripts/env.sh |
| 1 | Project scaffold | ✅ done | Phase 1 | Xcode 26.6 build clean; Core pkg tests 4/4 native; centered placeholder scene screenshot-verified on NH-Large @60fps; Info.plist via XcodeGen info block incl. PrivacyInfo.xcprivacy, NSPhotoLibraryAddUsageDescription, dark style |
| 2 | Core engine | ✅ done | Phase 2 | 14 Core tests green native; stress 500 enemies: avg_fps=60.0, draws=9 (<25), avg_tick 2.4ms stable (clump O(n²) fixed via separationNeighborCap=8 + testTickBudgetInDenseClump); screenshot verified |
| 3 | Combat loop | ✅ done | Phase 3 | 18 Core tests green; combat/death/restart screenshot-verified (RUN OVER overlay + timer/kill reset); fresh-bot deaths avg 52s min 45s across 20 seeds. NOTE: official 90-240s balance row deferred to Phase 4's upgrade-picking bot (pre-upgrade window 40-120s enforced instead — rationale in BalanceTests) |
| 4 | Upgrade draft system | ✅ done | Phase 4 | 25 Core tests green; official window: fresh+drafts avg 192s (90-240 ✓); upgrades 2.56× baseline (≥2 ✓); 8 weapon demo screenshots distinct; draft UI verified; player hard-collision added (fixed orbit-blade design flaw) |
| 5 | Run structure & boss | ✅ done | Phase 5 | Full timeline + arena-wipe boss entrance; kiting bot 5/5 victories; upgrades gate victory (declined=0 wins, 2/2 enrage deaths); defeat+victory screens verified; 60fps. Test spec amended: duration-ratio → victory-gating (boss finale saturates duration) |
| 6 | Meta progression | ✅ done | Phase 6 | 8 MetaTests green; save survives terminate+relaunch (◈500 screenshot + meta.json inspection, banked run totalRuns:1/bestKills:58); Lab adaptive layout verified LARGE+SMALL; Overdrive+revive+cosmetics wired |
| 7 | Juice & audio | ✅ done | Phase 7 | Juice checklist complete (flash/shake/hit-stop/slow-mo/damage-numbers/trail/banner/pause) screenshot-verified; audio agent: 8 SFX .caf + 2 music .m4a all GATES PASS (loopDelta=0.0000); haptic-mapping app tests 2/2; auto-pause on backgrounding verified; Core 39/39; icon generated (opaque PASS) |
| 8 | Menus, share & identity | ✅ done | Phase 8 | Live attract-mode menu, share sheet + 1080×1350 card, Retry/Lab/Share/Menu flow, neon icon on home screen. CRITICAL FIX: XcodeGen `resources:` key was invalid → icon/audio/PrivacyInfo never bundled; now via sources+buildPhase (bundle verified: Assets.car + 10 audio + xcprivacy) |
| 9 | QA hardening | ✅ done | Phase 9 | Headless 30-min soak (4 runs/3 wins, pools bounded); rendered soak RSS flat 231-234MB (host sim-reaping documented in KNOWN_ISSUES — not an app defect); backgrounding auto-pause verified; SE+ProMax safe areas clean; 0 project warnings; suites green |
| 10 | App Store readiness | ✅ done | Phase 10 | fastlane installed + lanes (build_release/beta/release); metadata all within limits (check_metadata.sh); 6 store screenshots @1320×2868 on Release build (forest art); STORE_ANSWERS.md (9+, DSA non-trader, privacy); site/ built — publishing deferred to runbook (public-repo creation needs owner action); unsigned Release device build succeeds |
| 11 | Release gate | ☐ not started | — | gated on ~/.appstoreconnect/neonhorde.env (GOAL §8); halt (b) = write RELEASE_RUNBOOK.md + summary |
| 8B | Forest-warrior art infra | ✅ done | Phase 8B | FULLY INTEGRATED: owner collage sliced (tools/slice_artdrop.py — flood-fill alpha, label scrub, CCL props), dynamic cell detection, mirror-tiled seamless grounds, animated hero/monsters/treant-boss live in-game (screenshots), art-composited app icon (opaque ✓). Known polish: faint label ghosts on close inspection (regenerate per-asset via ART_PROMPTS for final quality) |
| 8C | Audio v2 | ✅ done | Phase 8C | Forest-fantasy SFX + Karplus-Strong music + ambience bed; 11 gates PASS (loops 0.0000); ext_*.mp3 override ready for owner audio; launch clean |

## Sub-step checklists

(Managed by the executing agent — one section per phase as work begins.)
