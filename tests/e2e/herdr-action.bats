#!/usr/bin/env bats

setup() {
  load lib
  bin=$BATS_TEST_TMPDIR/bin
  mkdir -p "$bin"
  cp "$ANIX_E2E_SOURCE/scripts/herdr-action" "$bin/herdr-action"

  cat >"$bin/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$HERDR_TEST_ARGS"
SH
  cat >"$bin/herdr-ide" <<'SH'
#!/usr/bin/env bash
printf 'ide %s\n' "$*" >"$HERDR_TEST_ARGS"
SH
  chmod +x "$bin/herdr" "$bin/herdr-ide" "$bin/herdr-action"

  export HERDR_BIN_PATH=$bin/herdr
  export HERDR_TEST_ARGS=$BATS_TEST_TMPDIR/args
}

@test "bar opens the bar entrypoint as an overlay" {
  run "$bin/herdr-action" bar
  [ "$status" -eq 0 ]
  [ "$(cat "$HERDR_TEST_ARGS")" = \
    "plugin pane open --plugin herdr-bar --entrypoint bar --placement overlay" ]
}

@test "sidebar focuses the explorer" {
  run "$bin/herdr-action" sidebar
  [ "$status" -eq 0 ]
  [ "$(cat "$HERDR_TEST_ARGS")" = "plugin action invoke herdr-sidebar.show-explorer" ]
}

@test "ttt opens the editor entrypoint" {
  run "$bin/herdr-action" ttt
  [ "$status" -eq 0 ]
  [ "$(cat "$HERDR_TEST_ARGS")" = \
    "plugin pane open --plugin ttt.editor --entrypoint editor" ]
}

@test "ide delegates to herdr-ide" {
  run "$bin/herdr-action" ide
  [ "$status" -eq 0 ]
  [ "$(cat "$HERDR_TEST_ARGS")" = "ide " ]
}

@test "an unknown action is a usage error" {
  run "$bin/herdr-action" nope
  [ "$status" -eq 2 ]
  [[ $output == *"unknown action: nope"* ]]
}
