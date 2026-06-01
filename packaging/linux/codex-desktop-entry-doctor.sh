#!/bin/sh

codex_desktop_refresh_desktop_database() {
    codex_desktop_db_dir="${1:-}"
    [ -n "$codex_desktop_db_dir" ] || return 0

    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$codex_desktop_db_dir" >/dev/null 2>&1 || true
    fi
}

codex_desktop_write_user_local_entry() {
    codex_desktop_template_path="${1:?missing desktop template path}"
    codex_desktop_target_path="${2:?missing desktop target path}"
    codex_desktop_home_dir="${3:?missing home directory}"

    mkdir -p "$(dirname "$codex_desktop_target_path")"
    sed "s|@HOME@|${codex_desktop_home_dir}|g" \
        "$codex_desktop_template_path" > "$codex_desktop_target_path"
    chmod 0644 "$codex_desktop_target_path"
    codex_desktop_refresh_desktop_database "$(dirname "$codex_desktop_target_path")"
}

codex_desktop_entry_has_sidebar_mime() {
    grep -Eq '^MimeType=.*x-scheme-handler/codex-browser-sidebar([;]|$)' "$1"
}

codex_desktop_entry_has_new_window_action() {
    grep -Eq '^Actions=.*new-window([;]|$)' "$1" &&
        grep -Eq '^\[Desktop Action new-window\]$' "$1"
}

codex_desktop_entry_is_legacy_generated() {
    codex_desktop_file="${1:?missing desktop entry path}"
    [ -f "$codex_desktop_file" ] || return 1

    grep -q '^Name=Codex Desktop$' "$codex_desktop_file" || return 1
    grep -Eq '(^Exec=.*codex-desktop|^TryExec=.*codex-desktop|^Icon=codex-desktop$)' \
        "$codex_desktop_file" || return 1

    if grep -Eq 'codex-desktop-open-next|^Actions=NewWindow([;]|$)|^\[Desktop Action NewWindow\]$|^Actions=NewInstance([;]|$)|^\[Desktop Action NewInstance\]$' \
        "$codex_desktop_file"; then
        return 0
    fi

    # Earlier Linux desktop builds wrote user-level launchers that shadow the
    # system package entry and pin CODEX_ELECTRON_RESOURCES_PATH to
    # ~/.local/share/codex-desktop/resources. Newer packages install the app and
    # bundled plugin marketplace under /opt/codex-desktop/resources; leaving the
    # stale user entry in place makes GNOME launch the new binary against the old
    # resources tree, so bundled plugins such as Computer Use appear to be
    # missing even though the package installed them correctly.
    if grep -Eq 'CODEX_ELECTRON_RESOURCES_PATH=[^ ]*/\.local/share/codex-desktop/resources' \
        "$codex_desktop_file"; then
        return 0
    fi

    if ! codex_desktop_entry_has_sidebar_mime "$codex_desktop_file"; then
        return 0
    fi

    if ! codex_desktop_entry_has_new_window_action "$codex_desktop_file"; then
        return 0
    fi

    return 1
}

codex_desktop_next_backup_path() {
    codex_desktop_backup_target="${1:?missing desktop entry path}.bak"
    codex_desktop_backup_index=0

    while [ -e "$codex_desktop_backup_target" ]; do
        codex_desktop_backup_index=$((codex_desktop_backup_index + 1))
        codex_desktop_backup_target="${1}.bak.${codex_desktop_backup_index}"
    done

    printf '%s\n' "$codex_desktop_backup_target"
}

codex_desktop_repair_shadow_entry() {
    codex_desktop_target_path="${1:?missing desktop entry path}"
    codex_desktop_backup_target=""

    if ! codex_desktop_entry_is_legacy_generated "$codex_desktop_target_path"; then
        return 1
    fi

    codex_desktop_backup_target="$(codex_desktop_next_backup_path "$codex_desktop_target_path")"
    mv "$codex_desktop_target_path" "$codex_desktop_backup_target"
    codex_desktop_refresh_desktop_database "$(dirname "$codex_desktop_target_path")"
}

codex_desktop_repair_user_shadow_entries() {
    codex_desktop_user_name="${1:?missing user name}"
    codex_desktop_home_dir="${2:?missing home directory}"
    codex_desktop_target_file="${3:?missing desktop target file}"
    codex_desktop_app_dir="$codex_desktop_home_dir/.local/share/applications"

    [ -d "$codex_desktop_app_dir" ] || return 0

    for codex_desktop_user_entry in \
        "$codex_desktop_app_dir/$codex_desktop_target_file" \
        "$codex_desktop_app_dir"/codex*.desktop; do
        [ -f "$codex_desktop_user_entry" ] || continue
        if ! codex_desktop_entry_is_legacy_generated "$codex_desktop_user_entry"; then
            continue
        fi

        codex_desktop_backup_target="$(codex_desktop_next_backup_path "$codex_desktop_user_entry")"
        runuser -u "$codex_desktop_user_name" -- mv \
            "$codex_desktop_user_entry" "$codex_desktop_backup_target" >/dev/null 2>&1 || true
    done

    runuser -u "$codex_desktop_user_name" -- sh -c '
        if command -v update-desktop-database >/dev/null 2>&1; then
            update-desktop-database "$1" >/dev/null 2>&1 || true
        fi
    ' sh "$codex_desktop_app_dir" >/dev/null 2>&1 || true
}

codex_desktop_repair_system_package_shadow_entries() {
    codex_desktop_package_name="${1:-codex-desktop}"
    codex_desktop_target_file="${codex_desktop_package_name}.desktop"

    if ! command -v runuser >/dev/null 2>&1 || ! command -v getent >/dev/null 2>&1; then
        return 0
    fi

    # First handle every normal local account, including users who are not
    # currently logged in. Package managers own /usr/share/applications, but a
    # stale user-level ~/.local/share/applications entry wins over the system
    # entry in most desktop environments, so a clean package upgrade must repair
    # these safe-to-identify legacy generated entries proactively.
    getent passwd | while IFS=: read -r codex_desktop_user_name _ codex_desktop_uid _ _ codex_desktop_home_dir _; do
        case "$codex_desktop_uid" in
            ''|*[!0-9]*)
                continue
                ;;
        esac
        [ "$codex_desktop_uid" -ge 1000 ] 2>/dev/null || continue
        [ -n "$codex_desktop_home_dir" ] || continue
        [ "$codex_desktop_home_dir" != "/" ] || continue
        [ -d "$codex_desktop_home_dir" ] || continue
        codex_desktop_repair_user_shadow_entries \
            "$codex_desktop_user_name" \
            "$codex_desktop_home_dir" \
            "$codex_desktop_target_file"
    done

    # Also keep the older active-session path as a fallback for systems where
    # getent passwd is restricted but /run/user exposes the logged-in desktop
    # account.
    for codex_desktop_runtime_dir in /run/user/*; do
        [ -d "$codex_desktop_runtime_dir" ] || continue

        codex_desktop_uid="$(basename "$codex_desktop_runtime_dir")"
        case "$codex_desktop_uid" in
            ''|*[!0-9]*|0)
                continue
                ;;
        esac

        codex_desktop_passwd_entry="$(getent passwd "$codex_desktop_uid" || true)"
        [ -n "$codex_desktop_passwd_entry" ] || continue

        codex_desktop_user_name="$(printf '%s\n' "$codex_desktop_passwd_entry" | cut -d: -f1)"
        codex_desktop_home_dir="$(printf '%s\n' "$codex_desktop_passwd_entry" | cut -d: -f6)"
        [ -n "$codex_desktop_user_name" ] || continue
        [ -n "$codex_desktop_home_dir" ] || continue
        [ "$codex_desktop_home_dir" != "/" ] || continue

        codex_desktop_repair_user_shadow_entries \
            "$codex_desktop_user_name" \
            "$codex_desktop_home_dir" \
            "$codex_desktop_target_file"
    done
}
