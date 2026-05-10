class Sweep < Formula
  desc "Master Maintenance Suite for Developers - Clean your workspace and reclaim storage"
  homepage "https://github.com/abdulrasol/sweep-cli"
  version "3.3.3" # Update this version with every release
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/abdulrasol/sweep-cli/releases/download/v#{version}/Sweep-macOS.zip"
      sha256 "REPLACE_WITH_ACTUAL_SHA256"
    else
      url "https://github.com/abdulrasol/sweep-cli/releases/download/v#{version}/Sweep-macOS.zip"
      sha256 "REPLACE_WITH_ACTUAL_SHA256"
    end
  end

  on_linux do
    url "https://github.com/abdulrasol/sweep-cli/releases/download/v#{version}/Sweep-linux.tar.gz"
    sha256 "REPLACE_WITH_ACTUAL_SHA256"
  end

  def install
    if OS.mac?
      # Install the CLI binary
      bin.install "sweep"
      # For the Desktop app, users should download the DMG manually or via Cask
    else
      bin.install "sweep"
    end
  end

  test do
    system "#{bin}/sweep", "--version"
  end
end
