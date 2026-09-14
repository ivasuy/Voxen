# Contributing to Voxen

Thanks for helping improve Voxen.

## Development setup

Voxen requires macOS 14 or newer, the macOS 14 SDK, and Apple's command-line developer tools. No third-party Swift dependencies are required.

```sh
git clone https://github.com/ivasuy/Voxen.git
cd Voxen
bash scripts/build.sh
VOXEN_SKIP_HOTKEY_TEST=1 bash scripts/test.sh
```

Omit `VOXEN_SKIP_HOTKEY_TEST=1` when running in a logged-in graphical macOS session to include the Carbon hotkey registration check.

The landing page lives in `landing/`:

```sh
cd landing
npm ci
npm run build
```

## Pull requests

- Keep generated output, dependencies, API keys, recordings, and local browser captures out of commits.
- Add or update offline tests for behavior changes.
- Run the Swift tests and landing-page build that apply to your change.
- Explain user-visible privacy or permission changes in the pull request.

By contributing, you agree that your contribution is licensed under the repository's MIT License.
