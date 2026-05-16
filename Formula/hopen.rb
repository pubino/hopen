class Hopen < Formula
  desc "Hopen"
  homepage "https://github.com/pubino/hopen"
  url "https://github.com/pubino/hopen/archive/refs/tags/v0.2.5.tar.gz"
  sha256 "e0b945ad52bba4c379eab439a4bd672113d8c2a7008a160b887bb2a997ac509d"
  license "MIT"

  depends_on "rust" => :build

  def install
    system "cargo", "build", "--release", "--locked"
    bin.install "target/release/hopen"

    # Install shell function for zsh users who prefer Python-based server
    share.install "hopen.zsh"
  end

  def caveats
    <<~EOS
      To use hopen without specifying -r each time, set HOPEN_SITE_HOME:
        export HOPEN_SITE_HOME=/path/to/your/site/root
      Add this to your ~/.zshrc or ~/.bashrc.

      To run hopen as a background service:
        1. Configure your site directory:
           echo "/path/to/your/site" > ~/.hopenrc
        2. Start the service:
           brew services start hopen

      Alternatively, a zsh shell function using Python's http.server is available:
        source #{share}/hopen.zsh
    EOS
  end

  service do
    # Run the binary with the new flag to prevent browser popups on boot.
    # We pass -f to keep the process in the foreground so Homebrew can manage it.
    # We do NOT pass the -r flag here; we rely on the Rust app checking ~/.hopenrc
    run [opt_bin/"hopen", "--no-browser", "-f"]

    # CRITICAL: Only restart if the app exits successfully (0).
    # If it exits with (1) due to a missing ~/.hopenrc file, it will stay dead
    # instead of entering an infinite restart loop and flooding the user's logs.
    keep_alive successful_exit: true

    # standard homebrew log locations
    log_path var/"log/hopen.log"
    error_log_path var/"log/hopen.error.log"
    working_dir ENV["HOME"]
  end

  test do
    # Create a test HTML file
    (testpath/"test.html").write("<html><body>Test</body></html>")

    # Test that hopen runs without a server (should fail gracefully)
    output = shell_output("#{bin}/hopen --help")
    assert_match "local HTTP server", output
  end
end
