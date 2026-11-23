#!/usr/bin/env bats

setup() {
  load lib
  bin=$BATS_TEST_TMPDIR/bin
  mkdir -p "$bin"
  cp "$ANIX_E2E_SOURCE/home/default/rootshell/xdg-open" "$bin/xdg-open"
  cat >"$bin/rootshell-open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$XDG_TEST_ARGS"
SH
  chmod +x "$bin/xdg-open" "$bin/rootshell-open"
  export XDG_TEST_ARGS=$BATS_TEST_TMPDIR/args
  export PATH="$bin:$PATH"
  unset HERDR_ENV HERDR_SOCKET_PATH LC_ROOTSHELL_PANE TMUX ROOTSHELL_OPEN_MODE ROOTSHELL_OPEN
}

open_url() {
  run script -qec "env $* XDG_TEST_ARGS=$XDG_TEST_ARGS $bin/xdg-open https://example.com" /dev/null
}

@test "a Herdr pane uses the clipboard transport" {
  open_url HERDR_ENV=1
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_TEST_ARGS")" = "--clipboard https://example.com" ]
}

@test "a Rootshel SSH pane sends the URL" {
  open_url LC_ROOTSHELL_PANE=pane-1
  [ "$status" -eq 0 ]
  [ -s "$XDG_TEST_ARGS" ]
}

@test "ROOTSHELL_OPEN_MODE overrides the transport" {
  open_url HERDR_ENV=1 ROOTSHELL_OPEN_MODE=openurl
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_TEST_ARGS")" = "https://example.com" ]

  rm -f "$XDG_TEST_ARGS"
  open_url LC_ROOTSHELL_PANE=pane-1 ROOTSHELL_OPEN_MODE=clipboard
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_TEST_ARGS")" = "--clipboard https://example.com" ]
}

@test "the wrapper accepts exactly one HTTP or HTTPS URL" {
  run "$bin/xdg-open"
  [ "$status" -eq 64 ]

  run "$bin/xdg-open" https://example.com https://example.org
  [ "$status" -eq 64 ]

  run "$bin/xdg-open" file:///etc/passwd
  [ "$status" -eq 64 ]

  run "$bin/xdg-open" 'javascript:alert(1)'
  [ "$status" -eq 64 ]
}
