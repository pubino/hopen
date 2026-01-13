# Shared Task Notes

## Current Status
All core tasks completed:
- LICENSE.md (MIT, Princeton University 2026)
- README.md with full documentation
- GitHub Actions workflow (all tests passing)
- Homebrew formula created
- Pushed to https://github.com/pubino/hopen

## Next Steps: Complete Homebrew Tap Setup

The Homebrew formula is in `Formula/hopen.rb` but requires a separate tap repository to work. To complete:

1. **Create the homebrew-hopen tap repository:**
   ```bash
   gh repo create pubino/homebrew-hopen --public --description "Homebrew tap for hopen"
   ```

2. **Copy the formula to the tap:**
   ```bash
   cd /tmp
   git clone git@github.com:pubino/homebrew-hopen.git
   mkdir -p homebrew-hopen/Formula
   cp /path/to/hopen/Formula/hopen.rb homebrew-hopen/Formula/
   cd homebrew-hopen
   git add . && git commit -m "Add hopen formula" && git push
   ```

3. **Create a release tag and update the formula:**
   - Create v0.1.0 tag on pubino/hopen
   - Download the tarball and compute SHA256
   - Update `Formula/hopen.rb` in the tap with the correct SHA256

4. **Test the installation:**
   ```bash
   brew tap pubino/hopen
   brew install pubino/hopen/hopen
   ```

## Notes
- The formula includes caveats about HOPEN_SITE_HOME in post-install
- Tests run in Docker via `./run_tests.sh --docker`
- CI runs on push/PR to main
