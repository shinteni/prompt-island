#!/bin/zsh

vibelsland_log_path() {
    print "$1/Library/Logs/VibelslandFree/app.log"
}

vibelsland_bridge_path() {
    print "$1/.vibelsland-free/bin/vibelsland-bridge"
}

vibelsland_socket_path() {
    print "$1/.vibelsland-free/run/vibelsland.sock"
}

vibelsland_stop_pid() {
    local pid="$1"
    if [[ -n "$pid" ]]; then
        /bin/kill "$pid" >/dev/null 2>&1 || true
        wait "$pid" >/dev/null 2>&1 || true
    fi
}

vibelsland_cleanup_temp_home() {
    local temp_home="$1"
    shift
    local pid
    for pid in "$@"; do
        vibelsland_stop_pid "$pid"
    done
    /bin/rm -rf "$temp_home"
}

vibelsland_write_test_config() {
    local temp_home="$1"
    shift

    local enable_claude=false
    local enable_codex_cli=false
    local enable_codex_desktop=false
    local enable_sounds=false
    local sound_theme=soft
    local do_not_disturb=true
    local launch_at_login=false
    local island_position=topCenter
    local approval_timeout_seconds=7200
    local max_visible_sessions=5
    local assignment

    for assignment in "$@"; do
        case "$assignment" in
            enableClaude=*) enable_claude="${assignment#*=}" ;;
            enableCodexCLI=*) enable_codex_cli="${assignment#*=}" ;;
            enableCodexDesktop=*) enable_codex_desktop="${assignment#*=}" ;;
            enableSounds=*) enable_sounds="${assignment#*=}" ;;
            soundTheme=*) sound_theme="${assignment#*=}" ;;
            doNotDisturb=*) do_not_disturb="${assignment#*=}" ;;
            launchAtLogin=*) launch_at_login="${assignment#*=}" ;;
            islandPosition=*) island_position="${assignment#*=}" ;;
            approvalTimeoutSeconds=*) approval_timeout_seconds="${assignment#*=}" ;;
            maxVisibleSessions=*) max_visible_sessions="${assignment#*=}" ;;
        esac
    done

    local config_dir="$temp_home/Library/Application Support/VibelslandFree"
    /bin/mkdir -p "$config_dir"
    /bin/cat > "$config_dir/config.json" <<JSON
{
  "enableClaude": $enable_claude,
  "enableCodexCLI": $enable_codex_cli,
  "enableCodexDesktop": $enable_codex_desktop,
  "enableSounds": $enable_sounds,
  "soundTheme": "$sound_theme",
  "doNotDisturb": $do_not_disturb,
  "launchAtLogin": $launch_at_login,
  "islandPosition": "$island_position",
  "approvalTimeoutSeconds": $approval_timeout_seconds,
  "maxVisibleSessions": $max_visible_sessions
}
JSON
}

vibelsland_wait_for_process() {
    local pid="$1"
    local failure_message="$2"
    if ! /bin/kill -0 "$pid" >/dev/null 2>&1; then
        echo "$failure_message" >&2
        exit 1
    fi
}

vibelsland_wait_for_bridge() {
    local bridge="$1"
    local socket="$2"
    for _ in {1..60}; do
        if [[ -x "$bridge" && -S "$socket" ]]; then
            break
        fi
        sleep 0.2
    done

    [[ -x "$bridge" ]]
    [[ -S "$socket" ]]
}
