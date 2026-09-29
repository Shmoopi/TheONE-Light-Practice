# Publishing a release

This walks through setting up the one-time bits, then how to cut a release.

macOS refuses to open apps from unidentified developers, so a build people can
actually use has to be **signed** with an Apple certificate and **notarised** —
sent to Apple to be checked for malware. Both happen automatically when you tag a
release, once the details below are in place.

You need an **Apple Developer account** ($99/year). Without one, people can still
build the app themselves, but you can't hand out a copy that opens on first click.

## One-time setup

### 1. Create a signing certificate

1. In Xcode: **Settings → Accounts**, add your Apple ID, then **Manage
   Certificates → + → Developer ID Application**.
2. Open **Keychain Access**, find the certificate, right-click → **Export**.
3. Save it as a `.p12` file and set a password.
4. Turn it into text so it can be stored as a secret:

   ```
   base64 -i certificate.p12 | pbcopy
   ```

### 2. Create an app-specific password

Apple needs one to notarise on your behalf.

1. Go to [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security**
   → **App-Specific Passwords**.
2. Create one and copy it.

### 3. Find your team ID

At [developer.apple.com/account](https://developer.apple.com/account) under
Membership. It's ten characters, something like `A1B2C3D4E5`.

### 4. Add them to GitHub

In your repository: **Settings → Secrets and variables → Actions**, then add:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT` | The base64 text from step 1 |
| `DEVELOPER_ID_CERT_PASS` | The password you set on the `.p12` |
| `APPLE_ID` | The email address of your Apple ID |
| `APPLE_APP_PASSWORD` | The app-specific password from step 2 |
| `APPLE_TEAM_ID` | Your team ID from step 3 |

## Cutting a release

```
git tag v1.0.0
git push origin v1.0.0
```

That's all. GitHub then runs the tests, builds and signs the app, sends it to
Apple, waits for approval, publishes a release with the `.dmg` attached, and
updates the Homebrew cask with the new version and checksum.

It takes about ten minutes, most of it waiting on Apple.

## Homebrew

`Casks/theone-light-practice.rb` makes this repository a Homebrew tap. Because
the cask lives here rather than in Homebrew's own repository, people add the tap
once before installing:

```
brew tap Shmoopi/theone-light-practice https://github.com/Shmoopi/TheONE-Light-Practice
brew install --cask theone-light-practice
```

The release workflow keeps the version and checksum up to date from then on, so
after the first release there is nothing to do here by hand.

If you'd rather people could skip the `brew tap` line, the cask has to move to a
repository named `homebrew-something` — that naming is what lets Homebrew find a
tap on its own. Worth doing only if enough people install this way to care.

## Doing it by hand

If you'd rather not use GitHub Actions:

```
Scripts/release.sh "Developer ID Application: Your Name (TEAMID)" TEAMID

export APPLE_ID="you@example.com"
export APP_PASSWORD="abcd-efgh-ijkl-mnop"
export TEAM_ID="A1B2C3D4E5"
Scripts/notarize.sh "build/TheONE Light Practice.dmg"
```

Leave the arguments off `release.sh` for an unsigned build. That's fine on your own
Mac, but it won't open on anyone else's.

## When something goes wrong

**"Missing secrets"** — one of the five above isn't set. The error names it.

**Notarising fails** — ask Apple why:

```
xcrun notarytool log <submission-id> \
  --apple-id "$APPLE_ID" --password "$APP_PASSWORD" --team-id "$TEAM_ID"
```

Usually it's a missing hardened runtime or an unsigned piece inside the app.

**"App is damaged"** — the build wasn't notarised, or the approval wasn't attached.
Check `xcrun stapler validate` passed.
