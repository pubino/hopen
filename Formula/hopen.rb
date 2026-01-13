class Hopen < Formula
  desc "Fast local HTTP server for viewing HTML files"
  homepage "https://github.com/pubino/hopen"
  url "https://github.com/pubino/hopen/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
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

      Alternatively, a zsh shell function using Python's http.server is available:

        source #{share}/hopen.zsh
    EOS
  end

  test do
    # Create a test HTML file
    (testpath/"test.html").write("<html><body>Test</body></html>")

    # Test that hopen runs without a server (should fail gracefully)
    output = shell_output("#{bin}/hopen --help")
    assert_match "local HTTP server", output
  end
end
