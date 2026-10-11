# Homebrew formula. It lives in a tap, the repo joshua-hvmn/homebrew-tap, as
# Formula/git-workflow.rb; this copy is the source for it.
class GitWorkflow < Formula
  desc "Git flow or trunk flow with guardrails, SemVer prereleases and atomic releases"
  homepage "https://github.com/joshua-hvmn/git-workflow"
  url "https://github.com/joshua-hvmn/git-workflow/releases/download/v2.0.0/git-workflow-v2.0.0.tar.gz"
  sha256 "3c83fbe70f7d509ce368753242a7b5e486a1432b3fd18cecaa65a99d34e22d50"
  license "MIT"

  def install
    system "make", "install", "PREFIX=#{prefix}"
  end

  test do
    assert_match "git-workflow v#{version}", shell_output("#{bin}/git-workflow version")
  end
end
