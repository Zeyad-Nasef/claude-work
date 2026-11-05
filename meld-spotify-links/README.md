# Spotify links in Meld

I wanted Spotify links to open in Meld the same way YouTube Music links do, but
open.spotify.com never shows up in Meld's "Open by default > Add link" list.
These are my notes on why, plus the patch that fixes it.

Repo: https://github.com/FrancescoGrazioso/Meld
Patch: `0001-feat-spotify-open-Spotify-links-in-Meld.patch` (made on top of
upstream main `fa6e079`)

## Why it doesn't work

Android builds the "Add link" list from the intent filters in the app's
manifest. Meld only declares metrolist.cc, the YouTube domains and youtu.be.
No Spotify, so there's nothing to tick.

Even with the manifest fixed, Meld would still ignore the link.
`MainActivity.handleDeepLinkIntent()` only understands YouTube URLs (watch?v=,
playlist?list=, channel, browse). A `/track/<id>` path falls through and
nothing happens. Sharing a Spotify link into Meld does nothing today for the
same reason.

Most of what's needed was already in the app: the Spotify playlist and album
screens, and SpotifyQueue, which plays a Spotify track by matching it on
YouTube. The only missing piece was a call to fetch a single track by ID.

## What the patch does

- Manifest: new intent filter for open.spotify.com (track, album, playlist and
  artist paths, plus the /intl-xx/, /embed/ and old /user/ prefixes). It's not
  autoVerify since only Spotify can verify spotify.com.
- `SpotifyLink.kt`: small parser that gets the type and ID out of a URL, a
  `spotify:` URI or shared text like "Song - Artist https://open.spotify.com/...".
- `Spotify.track(id)`: reads the link preview tags (title, artists, album,
  cover, duration) from the public track page, the same tags WhatsApp uses for
  the preview. `SpotifyTrackPage.kt` does the parsing.
  - It used to call REST `tracks/{id}`, but REST gets rate limited with the web
    player token (Meld's own `SpotifyProfileCache` says so), and that's why the
    first test build showed "Couldn't open this Spotify link".
  - REST is still there as a fail-fast fallback.
  - Spotify only puts those tags in the page for non-browser clients, so the
    request uses a plain "Meld" user agent instead of Meld's usual desktop
    Chrome one.
- `MainActivity`: Spotify links are handled before the rest of
  `handleDeepLinkIntent`.
  - Playlist and album links open the Spotify screens.
  - A track starts playing, then continues as radio.
  - An artist link opens the matching YT Music artist, like the home feed does.
  - Episodes and shows get a "not supported" toast.
  - If you're not logged in to Spotify, it sends you to the login screen.
- Three new strings in `metrolist_strings.xml`, plus `SpotifyLinkTest` (8 tests).

What's been checked so far:

- The whole app builds with the patch, both `assembleFossDebug` and
  `assembleFossRelease`.
- All 27 Spotify unit tests pass, including the 8 new SpotifyLinkTest ones.
- The built APK has the open.spotify.com filter, and R8 keeps the new code.
- `lintFossDebug` passes. The only warning on the new lines was the missing
  autoVerify, which is on purpose, so it's marked with
  `tools:ignore="AppLinkWarning"`.
- The patch applies cleanly to upstream main.

What hasn't been checked: running it on a real phone. That's the test list
further down.

## Prebuilt APK

There's already a build of this patch, so you can skip straight to the phone
settings below.

- `Meld-plus-spotify-links.apk` is a release build, minified like the official
  one. App name "Meld+", package `com.meld.app.links`. It installs next to the
  normal Meld, so nothing gets overwritten.
- It's signed with my own key (`meld-plus.jks`, alias `meldplus`, password in
  `keystore-password.txt`). Keep that key around. Without it, a newer build
  can't update Meld+ in place.
- There's also a debug build ("Meld Debug", `com.meld.app.debug`), but it's
  slower. Use the release one.

Things that behave differently from the official app:

- You have to log in to Spotify again inside Meld+, because it has its own data.
- Last.fm login/scrobbling won't work. The Last.fm API keys are maintainer
  secrets and aren't in this build.
- The built-in updater still checks the official releases. If it offers an
  update, ignore it. That would install the official Meld, not update Meld+.

How it was built (from the patched repo):

```bash
METROLIST_APPLICATION_ID=com.meld.app.links METROLIST_APP_NAME="Meld+" \
  ./gradlew :app:assembleFossRelease
apksigner sign --ks meld-plus.jks --ks-key-alias meldplus \
  --out Meld-plus-spotify-links.apk app/build/outputs/apk/foss/release/app-foss-release-unsigned.apk
```

For the phone settings below, use "Meld+" and `com.meld.app.links` instead of
"Meld Debug" and `com.meld.app.debug`.

## Getting it on the phone

### 1. Fork and apply

Fork the repo on GitHub, then:

```bash
git clone https://github.com/<you>/Meld.git
cd Meld
git checkout -b feat/spotify-deep-links
git am /path/to/0001-feat-spotify-open-Spotify-links-in-Meld.patch
git push -u origin feat/spotify-deep-links
```

If upstream has moved and `git am` fails, try `git am -3`. Any conflict will
probably be in MainActivity around `handleDeepLinkIntent`.

### 2. Build

These are the same commands Meld's CONTRIBUTING.md uses:

```bash
./gradlew --console=plain :app:testFossDebugUnitTest --warning-mode summary
./gradlew --console=plain assembleFossDebug :app:lintFossDebug --warning-mode summary
# app/build/outputs/apk/foss/debug/app-foss-debug.apk
```

Docker works too: `docker compose run --rm dev ./gradlew --console=plain :app:assembleFossDebug`

If you don't want to build locally, you can use GitHub Actions on your fork:

1. Enable Actions on the fork.
2. Open a PR inside the fork (feat/spotify-deep-links into your own main).
   The "Build PR" workflow builds a debug APK and doesn't need any secrets.
3. Fix one line first: that workflow builds foss but uploads from
   `apk/gms/debug/`, so the artifact comes out empty. Change the path to
   `app/build/outputs/apk/foss/debug/*.apk`.

The debug build installs next to the official Meld as "Meld Debug"
(com.meld.app.debug). It can't replace the official app because it's signed
with a different key. You'll need to log in to Spotify again inside it.

### 3. Phone settings

1. If the Spotify app is installed, go to Settings > Apps > Spotify > Open by
   default and turn off "Open supported links". Spotify is verified for its own
   domain, so it wins otherwise. It's the same thing as YouTube vs Morphe.
2. Then go to Settings > Apps > Meld Debug > Open by default > Add link and tick
   open.spotify.com.

Or with adb (Android 12+):

```bash
adb shell pm set-app-links-allowed --user 0 --package com.spotify.music false
adb shell pm set-app-links-user-selection --user 0 --package com.meld.app.debug true open.spotify.com
adb shell pm get-app-links com.meld.app.debug
```

### 4. Test

```bash
adb shell am start -a android.intent.action.VIEW -c android.intent.category.BROWSABLE \
  -d "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
```

Things to try:

- [ ] A track link plays, and the queue keeps going after it.
- [ ] An album link opens the album screen.
- [ ] A playlist link opens the playlist screen. Try an editorial one too, e.g. 37i9dQZF1DXcBWIGoYBM5M.
- [ ] An artist link opens the YT Music artist page.
- [ ] Links with ?si=... and /intl-de/ links behave the same.
- [ ] Sharing a Spotify link into Meld from another app works.
- [ ] An episode link shows the toast and doesn't crash.
- [ ] Logged out of Spotify in Meld, a track link sends you to the login screen.
- [ ] With Meld fully closed, tapping a track link still plays it.
- [ ] YouTube Music links still work like before.

### 5. Send it upstream

Once it's tested, open a PR from the fork to FrancescoGrazioso/Meld main.
Something like:

> **feat(spotify): open Spotify links in Meld**
>
> Spotify links couldn't be set to open in Meld because open.spotify.com
> wasn't in the manifest, and handleDeepLinkIntent ignored them anyway.
> Playlists/albums now open the Spotify screens, tracks play through
> SpotifyQueue, artists open the YT Music artist. Shared links work too.
>
> Tested on <phone / Android version>: (list what you checked above)

Their PR CI runs the unit tests, so SpotifyLinkTest gets checked there.

## Not done yet

- spotify.link short links. They're redirects, so Meld would have to follow
  the redirect first. I left them out of the manifest on purpose. Otherwise
  they'd open Meld and do nothing.
- If Spotify ever drops the preview tags from track pages, the proper fix is
  GQL getTrack. Its hash would need adding to SpotifyHashProvider and the JSON
  registry (see AGENTS.md).
- Links still require a Spotify login. Track lookups no longer need it, but
  playlists, albums and the radio queue do.
- Podcasts aren't supported because Meld can't play them.
- Cold start: same as the YouTube links, `playerConnection` might not be bound
  yet when the link arrives. Watch for that when testing with the app closed.
