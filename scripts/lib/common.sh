#!/usr/bin/env bash

# Output and prompt helpers shared by the anix scripts. Source this file from a
# checkout; it defines functions and changes nothing else.

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

warn() { printf 'warning: %s\n' "$*" >&2; }

say() { printf '\n==> %s\n' "$*"; }

# ask PROMPT [DEFAULT]
# A yes/no prompt. With --yes (assume_yes=1) it returns the default without
# reading. End of input counts as "no", so an unattended run cannot accept a
# prompt by accident.
ask() {
  local prompt=$1 default=${2:-n} reply
  if [[ ${assume_yes:-0} -eq 1 ]]; then
    [[ $default == y ]]
    return
  fi
  if [[ $default == y ]]; then
    prompt="$prompt [Y/n]"
  else
    prompt="$prompt [y/N]"
  fi
  read -r -p "$prompt " reply || return 1
  reply=${reply:-$default}
  [[ $reply == [Yy]* ]]
}

# ask_secret PROMPT VAR
# Read a value without echoing it. With --yes the value is empty.
ask_secret() {
  local prompt=$1 var=$2 value
  if [[ ${assume_yes:-0} -eq 1 ]]; then
    printf -v "$var" '%s' ""
    return 0
  fi
  read -r -s -p "$prompt " value || true
  printf '\n' >&2
  printf -v "$var" '%s' "$value"
}
