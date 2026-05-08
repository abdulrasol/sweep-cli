# 🧹 Sweep CLI
### The Master Maintenance Console for Mac Developers

**Sweep CLI** is a professional-grade, multi-framework workstation utility built to keep your Mac clean, fast, and healthy. It handles everything from disk space recovery to code security audits and Git hygiene.

> **Powered and built by Abdulrasol with love of AI.**

---

## 🚀 Key Features

### 1. **Omni-Framework Cleanup**
Automatically detects and cleans build artifacts for:
-   **Flutter:** `flutter clean`, `.dart_tool`, `android/.gradle`, `ios/Pods`.
-   **Node.js / React:** `node_modules`, `dist`, `.next`, `.nuxt`.
-   **Android Native:** `build`, `app/build`, `.gradle`.
-   **Python:** `.venv`, `__pycache__`, `.pytest_cache`.
-   **Rust:** `cargo clean`, `target`.
-   **Java/Maven:** `target`, `build`.

### 2. **Global System Maintenance**
One-tap access to deep system cleaning:
-   **Xcode:** DerivedData and Tool Caches.
-   **Package Managers:** Homebrew upgrades, NPM global updates, Pip caches.
-   **Docker:** Deep system prune for unused containers and images.
-   **Simulators:** Deletes unavailable iOS simulators.

### 3. **Smart Health & Security**
-   **Health Audit:** Runs background security checks (`npm audit`, `flutter pub outdated`) during scanning.
-   **Big File Hunter:** Identifies individual files >100MB within your projects.
-   **Git Hygiene:** Scans for and removes local branches already merged into `main`/`master`.
-   **Freshness Tracking:** Marks projects not touched in **30+ days** as `[STALE]`.

### 4. **Professional CLI Experience**
-   **Interactive Console:** Categorized UI with smooth scrolling and dynamic hover notes.
-   **Drill-Down:** Press `Enter` on any batch to manage individual projects within that category.
-   **Dry Run Mode:** Simulate the cleanup to see exactly how much space you *would* reclaim.
-   **Persistence:** Remembers your last scanned directory and persistent "Ignore" list.

---

## 🛠 Installation

### Global Install (Recommended)
Run the script once with the `--install` flag to compile it to a native binary and add it to your PATH:

```bash
dart sweep.dart --install
```

**After installation, you can just type:**
```bash
sweep
```

### Manual Run
```bash
dart sweep.dart
```

---

## 🎮 Master Console Shortcuts

| Key | Action |
| :--- | :--- |
| **Arrows ↑/↓** | Navigate the list (Scrolls automatically) |
| **Space** | Toggle item for cleanup |
| **Enter** | **Drill-Down:** Open a batch sub-menu |
| **M** | **Maintenance:** Toggle Auto-Fix/Upgrade for dependencies |
| **I** | **Ignore:** Add project to permanent skip-list |
| **D** | **Dry Run:** Toggle simulation mode (no deletion) |
| **X** | **Execute:** Start all selected cleanup tasks |
| **B** | **Back:** Go back from a sub-menu |
| **Q / ESC** | **Exit:** Close the tool |

---

## 🩺 Automated Reports
Every session generates a professional `cleanup_report.md` in your scan root, detailing exactly which files were removed, space reclaimed, and any security issues found.

---

### **Built by Abdulrasol**
*Crafted with high-performance Dart and AI assistance.*
