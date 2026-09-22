#!/usr/bin/env bats
# Tests for the opt-in external hand-off (external_open in scripts/lib.sh).
# Same style as pick-scan.bats: source lib.sh directly against a temp
# fixture, with a stub command that records its argv instead of launching a
# real player.

setup() {
  LIB="$BATS_TEST_DIRNAME/../scripts/lib.sh"
  unset HERDR_BIN_PATH
  # shellcheck disable=SC1090
  . "$LIB"

  FIX="$(cd "$(mktemp -d)" && pwd -P)"
  mkdir -p "$FIX/home/clips" "$FIX/repo"
  git -C "$FIX/repo" init -q -b main
  printf 'audio\n' >"$FIX/home/clips/speaker.m4a"
  printf 'audio\n' >"$FIX/home/clips/SHOUT.M4A"
  printf 'notes\n' >"$FIX/home/clips/notes.md"

  STUB_LOG="$FIX/stub.log"
  STUB="$FIX/stub-open"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >>"%s"\n' "$STUB_LOG" >"$STUB"
  chmod +x "$STUB"

  cd "$FIX/repo"
  unset QUICKLOOK_EXTERNAL_EXTS QUICKLOOK_EXTERNAL_CMD QUICKLOOK_SCAN_FAST QUICKLOOK_ROOTS
}

# external_open detaches the command, so its side effects land after the
# call returns; poll briefly for the stub's log instead of reading it once.
stub_log() {
  local _
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$STUB_LOG" ] && break
    sleep 0.1
  done
  cat "$STUB_LOG"
}

teardown() {
  cd /
  rm -rf "$FIX"
}

@test "external_open: should decline when QUICKLOOK_EXTERNAL_EXTS is unset" {
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  run external_open "$FIX/home/clips/speaker.m4a"
  [ "$status" -eq 1 ]
  [ ! -e "$STUB_LOG" ]
}

@test "external_open: should decline when the extension is not listed" {
  QUICKLOOK_EXTERNAL_EXTS="mp3 wav"
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  run external_open "$FIX/home/clips/notes.md"
  [ "$status" -eq 1 ]
  [ ! -e "$STUB_LOG" ]
}

@test "external_open: should decline when the path is not a file" {
  QUICKLOOK_EXTERNAL_EXTS="m4a"
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  run external_open "$FIX/home/clips/missing.m4a"
  [ "$status" -eq 1 ]
  [ ! -e "$STUB_LOG" ]
}

@test "external_open: should run the command with the path when the extension is listed" {
  QUICKLOOK_EXTERNAL_EXTS="mp3 m4a"
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  run external_open "$FIX/home/clips/speaker.m4a"
  [ "$status" -eq 0 ]
  [ "$(stub_log)" = "$FIX/home/clips/speaker.m4a" ]
}

@test "external_open: should match extensions case-insensitively in both directions" {
  QUICKLOOK_EXTERNAL_EXTS="M4a"
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  run external_open "$FIX/home/clips/SHOUT.M4A"
  [ "$status" -eq 0 ]
  [ "$(stub_log)" = "$FIX/home/clips/SHOUT.M4A" ]
}

@test "external_open: should pass extra words in the command as separate args" {
  QUICKLOOK_EXTERNAL_EXTS="m4a"
  QUICKLOOK_EXTERNAL_CMD="$STUB -p"
  run external_open "$FIX/home/clips/speaker.m4a"
  [ "$status" -eq 0 ]
  [ "$(stub_log)" = "$(printf -- '-p\n%s' "$FIX/home/clips/speaker.m4a")" ]
}

@test "external_open: should run the command outside the caller's process group" {
  # herdr kills a closing pane's whole process group; a player started from
  # the hint pane must not be in it.
  printf '#!/bin/sh\nps -o pgid= -p $$ | tr -d " " >"%s"\n' "$STUB_LOG" >"$STUB"
  QUICKLOOK_EXTERNAL_EXTS="m4a"
  QUICKLOOK_EXTERNAL_CMD="$STUB"
  external_open "$FIX/home/clips/speaker.m4a"
  local own
  own="$(ps -o pgid= -p $$ | tr -d ' ')"
  [ -n "$(stub_log)" ]
  [ "$(stub_log)" != "$own" ]
}
