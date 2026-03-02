#!/usr/bin/env bash
# Shared utility functions — sourced by install.sh, not run directly.

prompt() {
  local name="$1" text="$2" default="${3:-}" value=""
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$text" "$default" >&2
  else
    printf "%s: " "$text" >&2
  fi

  if [ -t 0 ]; then
    read -r value
  elif [ -r /dev/tty ]; then
    read -r value < /dev/tty
  fi

  value="${value:-$default}"

  if [ -z "$value" ]; then
    echo "❌ $name cannot be empty" >&2
    exit 1
  fi

  printf '%s' "$value"
}

prompt_optional() {
  local name="$1" text="$2" default="${3:-}" value=""
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$text" "$default" >&2
  else
    printf "%s: " "$text" >&2
  fi

  if [ -t 0 ]; then
    read -r value
  elif [ -r /dev/tty ]; then
    read -r value < /dev/tty
  fi

  printf '%s' "${value:-$default}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing $1"; exit 1; }
}

# Validate IPv4 address format
validate_ip() {
  local ip="$1"
  if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
      [ "$octet" -gt 255 ] && return 1
    done
    return 0
  fi
  return 1
}

check_file() {
  local file="$1"
  if [ -f "$file" ] && [ -r "$file" ]; then
    echo "found"
  elif sudo test -f "$file" 2>/dev/null; then
    echo "sudo"
  else
    echo "missing"
  fi
}

# Extract a value from the simple JSON config strings used by CONFIGS array.
# Usage: config_get "$config" "hostname"
config_get() {
  local config="$1" key="$2"
  local clean
  clean=$(echo "$config" | sed 's/[{}]//g' | sed 's/"//g')
  echo "$clean" | grep -o "${key}:[^,]*" | cut -d: -f2-
}
