# Releasing Marc

Releases are built by the [Release workflow](../.github/workflows/release.yml). It produces a
Developer ID-signed, notarized and stapled `Marc-<version>.dmg`, a SHA-256 checksum and a signed
Sparkle `appcast.xml`, and attaches them to a **draft** GitHub release. Nothing reaches users
until a maintainer reviews the draft and publishes it by hand: Sparkle reads the feed from
`releases/latest`, which ignores drafts and pre-releases.

Development builds (`make build`, CI) are ad-hoc signed and have updates turned off. None of the
steps below are needed to build or contribute to Marc.

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
