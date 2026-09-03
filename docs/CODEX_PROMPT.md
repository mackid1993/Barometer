# Codex prompts

Two prompts: one to start, one to continue after each review. Paste them as-is into Codex CLI run from `/Users/david/MenuBarStats`.

## Kickoff prompt

```
You are implementing MenuBarStats, a free open source macOS menu bar system monitor that replaces iStat Menus and works with menu bar managers (Thaw, Bartender) on macOS 27. The repository is /Users/david/MenuBarStats. It contains only design documents right now.

Read these files completely before writing any code, in this order:
1. AGENTS.md (standing rules; they override your defaults)
2. docs/DESIGN.md (architecture, verified data sources, and the identity contract in section 3.5, which is non-negotiable)
3. docs/PLAN.md (the phased plan with task IDs, "Done when" conditions, and "Verify" commands)
4. Tools/probes/*.swift (working probe scripts already verified on this Mac; reuse their approach)

Environment facts you must respect: macOS 27.0 beta on an Apple M4 Pro; Command Line Tools only, no Xcode, Swift 6.2.3, SDK 26.2; build only with SwiftPM (`swift build`, `swift test`) plus the Makefile and Scripts/make-app.sh you will create in Phase 0; zero third-party dependencies; Swift 6 strict concurrency; American spelling everywhere.

Execute Phase 0 of docs/PLAN.md now: tasks P0-T1 through P0-T5, in order. For each task: implement it, run every command on its "Verify" line, record the output under the task ID in docs/PROGRESS.md (create the file), and commit with a message of the form "P0-T3: application shell". No attribution lines or co-author trailers in commits.

Rules that matter most:
- The bundle identifier is net.brustein.MenuBarStats and the autosave names are the ten listed in AGENTS.md. Put them in the ModuleID enum and nowhere else. Never put a live value in a status item's title, window title, accessibility label, or accessibility identifier; live values go only in accessibilityValue, and all menu bar content is an NSImage in button.image.
- One process owns every status item. No helper app, no XPC service, no daemon.
- Do not modify, launch, or read the preferences of iStat Menus, Stats, or Thaw except for the read-only Thaw identity check command in docs/PLAN.md, and only when David says Thaw is running.
- If a verification step needs something you cannot do (a permission dialog, plugging in a charger, running Thaw), do everything else, then stop and tell me exactly what you need.
- If the design turns out to be wrong on this machine, do not silently work around it: write what you observed in docs/PROGRESS.md, pick the nearest approach from docs/DESIGN.md section 6, and explain it in the commit message.

When Phase 0 is complete, stop. Post a summary with: what was built, the verification output for each task, anything that deviated from the design and why, and open questions. Do not start Phase 1.
```

## Continue prompt (use after each review)

```
Continue with Phase N of docs/PLAN.md in /Users/david/MenuBarStats. Re-read AGENTS.md and docs/PROGRESS.md first so you know the current state and any deviations already recorded. Do the tasks in order, run every "Verify" command, record output in docs/PROGRESS.md under each task ID, and commit per task with messages like "PN-T2: ...". Obey the identity contract in AGENTS.md without exception. Stop at the end of the phase and summarize what was built, the verification results, deviations, and open questions. Do not start Phase N+1.
```

Replace `N` with the phase number. If you want Codex to run several phases without stopping, say "continue through Phase M without stopping for review" and it will still commit per task and log per task.

## Notes for David

- Have Thaw running before Phase 0's P0-T3 verification so the identity check has something to read. The check is read-only: `defaults read com.stonerl.Thaw | grep -o 'net\.brustein\.MenuBarStats:[^"]*' | sort -u`.
- If you want a different bundle identifier, change it in AGENTS.md, docs/DESIGN.md section 3.5, and docs/PLAN.md before the kickoff. It cannot change after the first launch without losing menu bar positions.
- Phase 2 (weather) needs network access from the Codex sandbox to fetch fixture JSON once. If the sandbox blocks it, fetch the fixtures yourself with the curl commands Codex prints and drop them into Tests/MenuBarStatsCoreTests/Fixtures/.
