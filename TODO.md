# 🧹 Sweep: Master Development Roadmap

## ✅ COMPLETED (Ready for Release)

### 🧬 Engine & Core (The Brain)
- [x] **Engine Consolidation:** Unified `sweep_core.dart` powers both CLI and Desktop.
- [x] **Centralized Logic:** Framework markers, cleanup commands, and stats are shared.
- [x] **Stats Persistence:** Global history tracking for lifetime savings.
- [x] **Custom Rules Engine:** Fully functional JSON-based rule system.

### 🎨 Desktop Elite Experience
- [x] **Visual Dashboard:** Interactive `fl_chart` bars showing reclaimed storage history.
- [x] **Rules Manager GUI:** Dedicated page to manage custom frameworks without JSON editing.
- [x] **System Tray Integration:** Native macOS menu bar support for background residency.
- [x] **Elite UI/UX:** Scrollable layouts, responsive grids, and professional brand logos.
- [x] **Theme Persistence:** Remembers Dark/Light mode and Accent Colors across restarts.
- [x] **Stability Hardening:** Disabled macOS Sandbox and added resilient startup checks.

### 🛡️ Proactive Intelligence
- [x] **Vulnerability Radar:** Integrated `npm audit` and `pub outdated` into the scan engine.
- [x] **Health Indicators:** Color-coded badges (`[OK]`, `[OLD]`, `[!!!]`) for project status.
- [x] **Disk Guardian:** Background service monitors free space every hour.
- [x] **Native Notifications:** Sends system alerts when disk space drops below custom threshold.

### 🚚 Advanced Deployment
- [x] **Cross-Platform Build:** Support for macOS (`.app`), Windows (`APPDATA`), and Linux (`.desktop`).
- [x] **Verbose Installer:** Terminal progress bars and real-time build logs for the desktop app.
- [x] **Automated CI/CD:** GitHub Actions workflow to build and release binaries on every `v*` tag.

---

## 🚀 UP NEXT (The Future)

### ⌨️ Phase 4: CLI 2.0 (Modern TUI)
- [x] **Interactive Terminal:** Integrate `dart_console` for arrow-key navigation and list selection.
- [ ] **Pre-Commit Hook:** Special mode to run a "quick sweep" as a Git hook.
- [ ] **Terminal Dashboard:** ASCII-art version of the savings chart for CLI users.

### 📦 Phase 5: Community & Distribution
- [ ] **Homebrew (macOS/Linux):** Create a formal formula for `brew install sweep`.
- [ ] **Chocolatey/Scoop (Windows):** Add to Windows package managers.
- [ ] **Linux PPA:** Provide `.deb` and `.rpm` packages for major distros.

### 🤖 Phase 6: Advanced Optimization
- [ ] **Auto-Purge Mode:** Add a setting for the Guardian to clean automatically when threshold is hit.
- [ ] **Cloud Cache Support:** Clean remote build caches for Docker, Firebase, and AWS.
- [ ] **AI File Hunter:** Use local model/logic to identify "likely useless" large files beyond build artifacts.
- [ ] **Project Analytics:** Show which framework (e.g., Flutter vs. Node) is eating the most of your disk.
