# 🧹 Sweep CLI
### The Master Maintenance Console for Cross-Platform Developers

**Sweep CLI** is a professional-grade, multi-framework workstation utility built to keep your machine clean, fast, and healthy. Whether you are on **macOS, Windows, or Linux**, Sweep handles everything from disk space recovery to code security audits and Git hygiene.

> **Powered and built by Abdulrasol with love of AI (Google Gemini 1.5 Flash).**

---

## 📖 The Story Behind Sweep
Yesterday at the office, a teammate asked me to run a Flutter app we were building directly on his device. I plugged it in and ran `flutter run ios`. Suddenly, an error popped up: **"Not enough disk space."**

At first, I thought his iPhone was full. He checked—it had plenty of room. I checked my Mac and was shocked: **only 1GB of free space left!** Years of build artifacts and caches had quietly eaten my entire hard drive. 

I needed a solution. I started with a simple command to clear Xcode's `DerivedData`, but then I thought: *"Why stop there? Why not build a tool that cleans EVERYTHING for EVERY framework?"*

Because of my cloud usage limits, I deeply collaborated with **Gemini 1.5 Flash** to craft this high-performance Dart utility. I call it **Sweep**. It fixed my space issues instantly, and now it's here to fix yours.

---

## 🚀 Key Features

### 1. 🤖 **Smart Auto-Detection**
Sweep scans your directories and automatically detects which frameworks you are using (Flutter, Node, Python, Rust, etc.). It only shows you relevant cleanup options.

### 2. ⚡ **Omni-Framework Cleanup**
Cleans build artifacts safely across all major environments:
-   **Flutter:** `flutter clean`, `.dart_tool`, `android/.gradle`, `ios/Pods`.
-   **Node.js / React / Vue:** `node_modules`, `dist`, `.next`, `.nuxt`.
-   **Android Native:** `build`, `app/build`, `.gradle`.
-   **Python:** `.venv`, `__pycache__`, `.pytest_cache`.
-   **Rust:** `cargo clean`, `target`.
-   **Java/Maven:** `target`, `build`.

### 3. 🛠 **System Maintenance & Health**
-   **Global Caches:** Clears Homebrew, NPM, Yarn, and Pip global caches.
-   **Docker:** Performs a deep prune of unused containers and images.
-   **Health Audit:** Runs background security checks (`npm audit`, `flutter pub outdated`).
-   **One-Click Fix:** Press `M` to automatically upgrade dependencies for unhealthy projects.
-   **Big File Hunter:** Finds individual files >100MB hiding in your projects.

### 4. 🌳 **Git Hygiene**
Scans for local branches that have already been merged into `main` or `master` and offers to delete them in bulk.

### 5. 🌟 **v2.0 Elite Features**
-   **Extensibility:** Add your own frameworks by editing `~/.sweep_rules.json`.
-   **Visual Dashboard:** Run `sweep --stats` to see a bar chart of your lifetime space savings.
-   **Self-Updating:** Keep the tool on the cutting edge by running `sweep --update`.

---

## 🖥 Platform Support

| Feature | macOS | Linux | Windows |
| :--- | :---: | :---: | :---: |
| Build Cleaning | ✅ | ✅ | ✅ |
| System Caches | ✅ | ✅ | ✅ |
| Xcode Specifics | ✅ | ❌ | ❌ |
| Size Estimation | `du` | `du` | `PowerShell` |
| Native Binary | ✅ | ✅ | ✅ |

---

## 🛠 Installation & Building

### Prerequisites
-   [Dart SDK](https://dart.dev/get-dart) installed on your system.

### Quick Install (Mac & Linux)
1.  Clone the repo: `git clone https://github.com/abdulrasol/sweep-cli.git`
2.  Navigate to folder: `cd sweep-cli`
3.  Run the installer:
    ```bash
    dart sweep.dart --install
    ```
4.  **Usage:** 
    - `sweep` : Open the interactive console.
    - `sweep --stats` : View your space savings dashboard.
    - `sweep --update` : Download and install the latest version from GitHub.

### Quick Install (Windows)
1.  Open PowerShell as Administrator.
2.  Run:
    ```powershell
    dart compile exe sweep.dart -o sweep.exe
    ```
3.  Move `sweep.exe` to a folder in your System PATH.
4.  **Usage:** Type `sweep` in your terminal!

---

## 🎮 Keyboard Shortcuts

| Key | Action |
| :--- | :--- |
| **Arrows ↑/↓** | Navigate the list (Auto-scrolling) |
| **Space** | Toggle item for cleanup |
| **Enter** | **Drill-Down:** Open a project batch to see individual folders |
| **M** | **Maintenance:** Toggle Auto-Upgrade `[FIX]` for dependencies |
| **I** | **Ignore:** Add path to permanent skip-list |
| **D** | **Dry Run:** Toggle simulation mode (no deletion) |
| **X** | **EXECUTE:** Start the selected cleanup tasks |
| **B** | **Back:** Return from a sub-menu |
| **Q / ESC** | **Exit:** Close the tool |

---

## 📄 License & Credits
-   **Author:** Abdulrasol
-   **Engine:** Built via "Voice Coding" and collaboration with **Google Gemini 1.5 Flash**.
-   **License:** MIT - Feel free to use, modify, and share.

*Every cleanup session generates a `cleanup_report.md` in your scan root for full transparency.*

---
**Built by Abdulrasol with love of AI.**
