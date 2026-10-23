# Releasing Marc

Releases are built by the [Release workflow](../.github/workflows/release.yml) and attached to
a **draft** GitHub release. Nothing reaches users until a maintainer reviews the draft and
publishes it by hand. The workflow has two modes:

| Mode | When | Result |
| --- | --- | --- |
| **Signed** | All secrets in [Repository configuration](#4-repository-configuration) are set. | Developer ID-signed, notarized and stapled `Marc-<version>.dmg`, a SHA-256 checksum and a signed Sparkle `appcast.xml`. Installed copies update themselves. |
| **Preview** | None of those secrets are set (the current setup). | An ad hoc-signed `Marc-<version>.dmg` and its checksum, always marked as a pre-release. |

If only some of the secrets are set, the workflow stops with an error rather than guessing.

Development builds (`make build`, CI) are ad-hoc signed and have updates turned off. None of the
steps below are needed to build or contribute to Marc.

## Disk image

`scripts/make-dmg.sh` builds `Marc-<version>.dmg` with a designed window: the background from
`design/render-dmg-background.swift` (rendered at 1× and 2× each time), the app and an Applications
shortcut at fixed positions, and the app icon as the volume icon. It uses
[dmgbuild](https://github.com/dmgbuild/dmgbuild), installed into a temporary virtual environment
from the hash-pinned `packaging/dmg/requirements.txt`, so no Finder scripting is involved. CI
builds a preview disk image on every push to catch problems early.

## App icons

`design/render-icons.swift` draws both icon styles from vector paths and writes every size into
`Marc/Resources/Assets.xcassets`: the white Marc tile as `AppIcon` and the dark Aurora tile as an
alternate offered in Settings. Run it after changing the artwork:

```bash
swift design/render-icons.swift Marc/Resources/Assets.xcassets
```

## Preview builds

Preview builds need no Apple Developer account, at the cost of a rougher experience for people
who install them:

- macOS blocks the first launch. Users move Marc to Applications, try to open it, then choose
  **Open Anyway** in System Settings → Privacy & Security. The release notes explain this
  automatically.
- There are no automatic updates: without a Sparkle key, *Check for Updates* opens the Releases
  page instead.
- Each build has a different ad hoc signature, so after an update macOS may ask once whether Marc
  can use the passwords it saved in the keychain.
- GitHub's `releases/latest` never points at a pre-release, so preview builds are only listed on
  the Releases page.

Preview builds turn the hardened runtime off: with it on, library validation refuses to load the
ad hoc-signed Sparkle framework and the app quits at launch. Both workflows launch the built app
with `scripts/smoke-test.sh` to catch problems like this before anything is published.

Tag previews with a pre-release suffix, for example `v0.1.0-preview.1`. Their notes come from the
matching `## [0.1.0-preview.1]` section of the changelog if there is one, otherwise from
`## [0.1.0]`, otherwise from *Unreleased*.

Switching to signed releases later only needs the one-time setup below; the workflow picks the
signed mode as soon as every secret is present.

## One-time setup

You need a paid Apple Developer Program membership for the Developer ID certificate and
notarization.

### 1. Developer ID certificate

1. In Xcode → Settings → Accounts, or on developer.apple.com, create a **Developer ID
   Application** certificate.
2. Export it with its private key from Keychain Access as a `.p12` file with a strong password.
3. Encode it: `base64 -i DeveloperID.p12 | pbcopy`.

### 2. Notarization API key

1. In App Store Connect → Users and Access → Integrations → App Store Connect API, create a
   team key with the **Developer** role.
2. Download the `.p8` file (it can be downloaded only once) and note the **Key ID** and the
   **Issuer ID**.

### 3. Sparkle signing keys

Sparkle verifies every update with an EdDSA signature.

1. Download the Sparkle distribution matching the version in `project.yml` from
   <https://github.com/sparkle-project/Sparkle/releases> and run `./bin/generate_keys`. It
   stores the private key in your login Keychain and prints the public key.
2. Export the private key for CI: `./bin/generate_keys -x sparkle_private_key.txt`, then delete
   that file once it is saved as a secret.
3. **Back up the private key.** If it is lost, existing installations can't verify updates
   signed with a new key.

### 4. Repository configuration

In the repository's Settings → Secrets and variables → Actions, add:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `DEVELOPER_ID_CERTIFICATE_P12` | The base64-encoded `.p12` file. |
| Secret | `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The `.p12` password. |
| Secret | `APPLE_TEAM_ID` | Your 10-character Team ID. |
| Secret | `NOTARY_API_KEY_ID` | The App Store Connect API Key ID. |
| Secret | `NOTARY_API_ISSUER_ID` | The App Store Connect Issuer ID. |
| Secret | `NOTARY_API_KEY_P8` | The full contents of the `.p8` file. |
| Secret | `SPARKLE_PRIVATE_ED_KEY` | The exported Sparkle private key. |
| Variable | `SPARKLE_PUBLIC_ED_KEY` | The Sparkle public key (base64). |

Then, under Settings → Environments, create an environment named **`release`** and add
yourself as a required reviewer. Every release run then waits for an explicit approval.

The workflow stops with a clear error if any of these values is missing; it never produces an
unsigned release.

## Cutting a release

1. **Prepare the changelog.** On a `chore/release-x.y.z` branch, rename the *Unreleased*
   section of [CHANGELOG.md](../CHANGELOG.md) to `## [x.y.z] - YYYY-MM-DD`, add a new empty
   *Unreleased* section above it, and set `MARKETING_VERSION` in `project.yml` to `x.y.z`.
   Merge the branch into `main` after CI passes.
2. **Tag the release** on the merge commit, using the `v` prefix:

   ```bash
   git tag -s vX.Y.Z -m "Marc X.Y.Z"
   git push origin vX.Y.Z
   ```

   Pushing the tag starts the Release workflow. To rebuild an existing tag, run the workflow
   manually from the Actions tab with the version number.
3. **Approve the run** in the `release` environment.
4. **Review the draft release** on GitHub: download the DMG, check that it opens without a
   Gatekeeper warning, that *About Marc* shows the right version, and that the release notes
   are correct.
5. **Publish** the draft. Users with Marc installed are offered the update on their next check.

Versions with a pre-release suffix (`v0.2.0-beta.1`) are marked as pre-releases. Their appcast is
attached to the release but is not served from `releases/latest`, so existing users aren't
updated to them.

## Versioning

- Marc follows [Semantic Versioning](https://semver.org). Until 1.0, minor versions may contain
  breaking changes to stored data, with migrations.
- `CFBundleShortVersionString` is the tag's version. `CFBundleVersion` is the number of commits
  on the tagged commit (`git rev-list --count`), so it increases with every release, as Sparkle
  requires.

## If something goes wrong

- **Notarization rejected:** the workflow prints Apple's notary log. Typical causes are a
  nested binary without the hardened runtime or a missing secure timestamp.
- **A bad release was published:** publish a fixed version with a higher number. Don't delete
  the release that users already have; Sparkle can't downgrade.
- **The Sparkle private key leaked:** rotate it with `generate_keys`, ship a release signed with
  the old key that contains the new public key, then sign later releases with the new key.
