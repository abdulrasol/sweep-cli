# Sweep Project Guidelines

## 🔄 Development Workflow
- **Auto-Push & Tag Mandate:** After completing every bug fix or new feature implementation, automatically stage, commit, and push the changes to GitHub.
- **Tagging Protocol:** Immediately after pushing changes, update the version tag (e.g., `v3.0.x`) and push it to trigger the automated release pipeline. Increment the patch version for fixes and the minor version for features.
- **Roadmap Synchronization:** Always update `TODO.md` when a task is completed by marking it with `[x]`.

## 🛠 Engineering Standards
- **Core Engine Unity:** Ensure all scanning and logic changes are applied to `sweep_desktop/lib/sweep_core.dart` to maintain consistency between CLI and Desktop.
- **Cross-Platform Integrity:** All UI changes must be verified for readability in both Dark and Light modes.
- **Crash Resilience:** The `main()` function in `lib/main.dart` must remain wrapped in fail-safe initialization blocks.
