# 📋 User Action Log: Completing the Sweep Ecosystem

This file tracks the manual steps required from the repository owner to fully activate the advanced features and distribution channels I have implemented.

## 📦 Phase 5: Community & Distribution

### 1. 🍏 Homebrew (macOS / Linux)
- [ ] **Create Repository:** Create a new public repository on your GitHub account named `homebrew-sweep`.
- [ ] **Upload Formula:** 
    - Create a folder named `Formula` in that new repository.
    - Upload the file `Formula/sweep.rb` (from this repo) into that folder.
    - **Result:** Users will be able to run `brew install abdulrasol/sweep`.

### 2. 🪟 WinGet (Windows)
- [ ] **Generate PAT:** Create a GitHub Personal Access Token (classic) with the `public_repo` scope.
- [ ] **Add Secret:** Go to this repository's **Settings** -> **Secrets and variables** -> **Actions**.
- [ ] **Set WINGET_TOKEN:** Create a new repository secret named `WINGET_TOKEN` and paste your PAT there.
- [ ] **Result:** Every time you push a new tag, a Pull Request will be automatically sent to Microsoft to update Sweep on the official WinGet store.

## 🛠 Project Metadata

### 3. 👤 Branding & Contact
- [ ] **Update Email:** Open `sweep_desktop/pubspec.yaml` and replace `rasol@example.com` with your real contact email. This appears in the native Linux and Windows package metadata.
- [ ] **Push Change:** Commit and push this change to update the official package info.

## ⌨️ CLI 2.0 Features

### 4. 🧹 Git Hygiene
- [ ] **Install Hook:** In any of your local coding projects, run `sweep --install-hook`.
- [ ] **Result:** This installs a pre-commit hook that automatically cleans your build artifacts before every commit, keeping your repositories small and clean.

## 🚀 Future Maintenance

### 5. 🏷 Tagging Protocol
- [ ] **Increment Versions:** Remember to push a new tag (e.g., `git tag v3.5.0 && git push origin v3.5.0`) whenever you want to trigger a new multi-platform build and GitHub Release.
