#!/bin/sh
#
# One-line installer:
#
#   curl -fsSL https://raw.githubusercontent.com/alee-ibrahim/vmerge/main/install.sh | sh
#
# Why this exists, and why it is a pipe rather than a file to download:
# macOS quarantines anything a browser saves, refuses to run it, and passes the
# mark on to everything unpacked from it - so a downloaded zip cannot contain a
# script that clears its own quarantine, because the script is quarantined too.
# curl sets no such mark. Piping the installer is not a shortcut around
# Gatekeeper; it is the only shape that can do the setup at all without a
# notarised build, which needs a paid Apple developer account.
#
# Everything is wrapped in a function called on the last line. A pipe that is
# cut halfway leaves a truncated script, and without this the shell would run
# whatever complete lines arrived before the break.

set -eu

main() {
    REPO="${VMERGE_REPO:-alee-ibrahim/vmerge}"
    PREFIX="${VMERGE_PREFIX:-$HOME/.local/bin}"

    say() { printf '  %s\n' "$*"; }
    die() { printf '\n  %s\n\n' "$*" >&2; exit 1; }

    printf '\n  Installing vmerge\n\n'

    # ---------------------------------------------------------------- platform
    os=$(uname -s)
    arch=$(uname -m)

    case "$os/$arch" in
        Darwin/arm64)
            asset="MERGE-VIDEOS-macos-arm64"
            ;;
        Darwin/*)
            die "This installs the Apple Silicon build, and this Mac is $arch.
  Build from source instead: https://github.com/$REPO"
            ;;
        *)
            die "There is no published build for $os/$arch.
  Windows: download MERGE-VIDEOS.exe from
    https://github.com/$REPO/releases/latest
  Anything else: build from source, https://github.com/$REPO"
            ;;
    esac

    for tool in curl shasum install; do
        command -v "$tool" >/dev/null 2>&1 || die "This needs $tool, which is not on PATH."
    done

    # ---------------------------------------------------------------- download
    # The /releases/latest/download/ route redirects to the newest release's
    # asset without an API call. That matters: api.github.com rate-limits by IP
    # and would make this fail for reasons having nothing to do with the user.
    base="https://github.com/$REPO/releases/latest/download"

    work=$(mktemp -d)
    # Cleans up on failure and on ctrl-c as well as on success, so a stopped
    # install does not leave 3 MB in the temp folder.
    trap 'rm -rf "$work"' EXIT INT TERM

    say "Downloading $asset"
    curl -fsSL --retry 3 -o "$work/vmerge" "$base/$asset" \
        || die "Could not download the program from $base/$asset"

    # ------------------------------------------------------------------ verify
    # The release publishes a digest beside each binary. Checking it costs half
    # a second and is the difference between "it downloaded" and "it downloaded
    # intact".
    if curl -fsSL --retry 3 -o "$work/expected" "$base/$asset.sha256" 2>/dev/null; then
        expected=$(tr -d ' \t\r\n*' < "$work/expected" | cut -c1-64)
        actual=$(shasum -a 256 "$work/vmerge" | cut -d' ' -f1)
        if [ "$expected" != "$actual" ]; then
            die "The download does not match its published checksum.
  expected $expected
  got      $actual
  Nothing has been installed."
        fi
        say "Checksum verified"
    else
        say "No checksum published for this release; skipping that check"
    fi

    # ----------------------------------------------------------------- install
    mkdir -p "$PREFIX" || die "Could not create $PREFIX"
    install -m 755 "$work/vmerge" "$PREFIX/vmerge" \
        || die "Could not write to $PREFIX"

    # curl does not set the quarantine attribute, so there should be nothing to
    # clear. Done anyway because it costs nothing and covers the case where
    # someone saved this script in a browser and ran it by hand.
    xattr -d com.apple.quarantine "$PREFIX/vmerge" 2>/dev/null || true

    # The release is already ad-hoc signed on the build machine. An arm64 binary
    # with no signature at all is killed by the kernel before it starts, so this
    # re-signs only when the existing signature does not verify.
    if command -v codesign >/dev/null 2>&1; then
        codesign -v "$PREFIX/vmerge" 2>/dev/null \
            || codesign --force --sign - "$PREFIX/vmerge" 2>/dev/null \
            || true
    fi

    say "Installed to $PREFIX/vmerge"

    # ------------------------------------------------------------ warm up tools
    # ffmpeg installs itself on first use. Doing it now means the first real
    # merge starts immediately instead of pausing for a 40 MB download, and it
    # surfaces a broken setup here, where there is a message to read, rather
    # than in the middle of something.
    #
    # stdin comes from /dev/null for two reasons: the program waits on a
    # keypress when it has something to report, and under `curl | sh` this
    # script's own stdin is the pipe - a child reading it would eat the rest of
    # the installer.
    say "Fetching ffmpeg (about 40 MB, once)"
    empty=$(mktemp -d)
    "$PREFIX/vmerge" --no-tui --no-update --folder "$empty" </dev/null >/dev/null 2>&1 || true
    rm -rf "$empty"

    if [ -x "$PREFIX/ffmpeg/bin/ffmpeg" ]; then
        say "ffmpeg ready"
    else
        say "ffmpeg is not set up yet - it will download on first use"
    fi

    # -------------------------------------------------------------------- done
    printf '\n  Done.\n\n'

    case ":$PATH:" in
        *":$PREFIX:"*)
            say "Run it with:  vmerge --folder ~/Desktop/clips"
            ;;
        *)
            # Naming the file rather than guessing the shell: a wrong rc file is
            # worse than none, because nothing happens and there is no error.
            say "$PREFIX is not on your PATH. Either run it in full:"
            say ""
            say "  $PREFIX/vmerge --folder ~/Desktop/clips"
            say ""
            say "or add it to your PATH, then reopen Terminal:"
            say ""
            say "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
            ;;
    esac
    printf '\n'
}

main "$@"
