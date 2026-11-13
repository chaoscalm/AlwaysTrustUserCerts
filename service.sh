#!/system/bin/sh

# Resolve the directory where this script is installed.
MODDIR=${0%/*}

# Traditional Android system certificate directory.
SYS_CERT_DIR=/system/etc/security/cacerts

# Active Conscrypt APEX certificate directory.
APEX_CERT_DIR=

# Track whether this script mounted the temporary certificate filesystem.
TMPFS_MOUNTED=0

# Count certificates found in the active Conscrypt APEX.
APEX_CERT_COUNT=0

# Marker created by post-fs-data.sh after collection succeeds.
CERTS_READY_FILE="$MODDIR/.certs-ready"

# Number of immediate retries for namespace mount injection.
INITIAL_INJECTION_RETRIES=3

# Maximum number of seconds to wait for Android boot completion.
BOOT_COMPLETION_TIMEOUT=300

# Use Android's standard tool locations, with fallbacks for alternate layouts.
MOUNT=/system/bin/mount
UMOUNT=/system/bin/umount
NSENTER=/system/bin/nsenter

[ -x "$MOUNT" ] || MOUNT=/bin/mount
[ -x "$UMOUNT" ] || UMOUNT=/bin/umount
[ -x "$NSENTER" ] || NSENTER=/bin/nsenter

log() {
    # Append timestamped diagnostics to the module log.
    echo "$(date '+%m-%d %H:%M:%S ')" "$@" >> "$MODDIR/log.txt"
}

copy_certificate() {
    local source="$1"
    local destination_dir="$2"
    local name
    local target
    local base
    local index

    name=$(basename "$source")
    target="$destination_dir/$name"

    # Avoid storing identical certificates more than once.
    if [ -e "$target" ]; then
        if cmp -s "$source" "$target"; then
            return 0
        fi

        # Preserve different certificates with the same filename.
        case "$name" in
            *.*)
                base=${name%.*}
                ;;
            *)
                base=$name
                ;;
        esac

        index=1
        target="$destination_dir/$base.$index"

        # Find an unused filename without overwriting another certificate.
        while [ -e "$target" ]; do
            if cmp -s "$source" "$target"; then
                return 0
            fi

            index=$((index + 1))
            target="$destination_dir/$base.$index"
        done
    fi

    cp -f "$source" "$target"
}

is_apex_path_mounted() {
    local cert_dir="$1"
    local apex_dir="${cert_dir%/cacerts}"
    local pid
    local name

    # Check global, service, and zygote mount namespaces.
    for pid in 1 $$; do
        [ -r "/proc/$pid/mountinfo" ] || continue

        if grep -Fq " $cert_dir " "/proc/$pid/mountinfo" ||
            grep -Fq " $apex_dir " "/proc/$pid/mountinfo"; then
            return 0
        fi
    done

    # Check zygote namespaces because APEX mounts may be namespace-specific.
    for name in zygote zygote64; do
        for pid in $(pidof "$name" 2>/dev/null); do
            [ -r "/proc/$pid/mountinfo" ] || continue

            if grep -Fq " $cert_dir " "/proc/$pid/mountinfo" ||
                grep -Fq " $apex_dir " "/proc/$pid/mountinfo"; then
                return 0
            fi
        done
    done

    return 1
}

find_apex_cert_dir() {
    # Android may expose Conscrypt at a standard or versioned APEX path.
    for dir in \
        /apex/com.android.conscrypt/cacerts \
        /apex/com.android.conscrypt@*/cacerts; do
        if [ -d "$dir" ] && is_apex_path_mounted "$dir"; then
            echo "$dir"
            return 0
        fi
    done

    return 1
}

count_certificates() {
    local directory="$1"
    local count=0
    local cert

    # Count regular files in a certificate directory.
    for cert in "$directory"/*; do
        [ -f "$cert" ] || continue
        count=$((count + 1))
    done

    echo "$count"
}

has_mount() {
    local pid="$1"

    # Accept only numeric process identifiers.
    case "$pid" in
        ''|*[!0-9]*)
            return 1
            ;;
    esac

    # Confirm that the APEX certificate path is mounted in this namespace.
    [ -r "/proc/$pid/mountinfo" ] &&
        grep -Fq " $APEX_CERT_DIR " "/proc/$pid/mountinfo"
}

has_tmpfs_mount() {
    # Confirm that the system certificate path is backed by the tmpfs
    # created by this script, rather than merely checking that it exists.
    [ -r "/proc/$$/mountinfo" ] &&
        awk -v target="$SYS_CERT_DIR" \
            '$5 == target && index($0, " - tmpfs ") { found = 1 }
             END { exit !found }' "/proc/$$/mountinfo"
}

cleanup_tmpfs() {
    # Remove the temporary mount if setup fails.
    if [ "$TMPFS_MOUNTED" -eq 1 ]; then
        "$UMOUNT" "$SYS_CERT_DIR" 2>/dev/null ||
            log "Failed to clean up $SYS_CERT_DIR"
        TMPFS_MOUNTED=0
    fi
}

fail_setup() {
    # Log the failure and clean up any mount created by this script.
    log "$1"
    cleanup_tmpfs
    return 1
}

inject_mount() {
    local pid="$1"

    # The target process must still have a mount namespace.
    [ -e "/proc/$pid/ns/mnt" ] || return 1

    # Bind the combined system certificate directory into the target
    # process's mount namespace at the active Conscrypt certificate path.
    "$NSENTER" \
        --mount="/proc/$pid/ns/mnt" \
        -- "$MOUNT" --rbind "$SYS_CERT_DIR" "$APEX_CERT_DIR" &&
        has_mount "$pid"
}

inject_with_retries() {
    local pid="$1"
    local attempt=1

    # A zygote can be transitioning namespaces during boot. Retry a bounded
    # number of times here, then let monitor_zygote continue periodic retries.
    while [ "$attempt" -le "$INITIAL_INJECTION_RETRIES" ]; do
        if inject_mount "$pid"; then
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    return 1
}

monitor_zygote() {
    (
        while true; do
            # Android may run 32-bit, 64-bit, or both zygote processes.
            zygote_pids=""

            for name in zygote zygote64; do
                for pid in $(pidof "$name" 2>/dev/null); do
                    zygote_pids="$zygote_pids $pid"
                done
            done

            for zp in $zygote_pids; do
                # Ensure the zygote namespace has the certificate mount.
                if ! has_mount "$zp"; then
                    log "Injecting into zygote ($zp)"

                    if ! inject_with_retries "$zp"; then
                        log "Failed to inject zygote ($zp)"
                        continue
                    fi
                fi

                # Find processes whose parent is this zygote.
                children=$(
                    ps -A -o PID,PPID 2>/dev/null |
                        awk -v parent="$zp" '$2 == parent { print $1 }'
                )

                # Fallback for older Android ps implementations.
                if [ -z "$children" ]; then
                    children=$(
                        echo "$zp" |
                            xargs -n1 ps -o pid -P 2>/dev/null |
                            grep -v PID
                    )
                fi

                # Inject the certificate mount into each zygote child.
                for pid in $children; do
                    if ! has_mount "$pid"; then
                        log "Injecting into child $pid"

                        if ! inject_with_retries "$pid"; then
                            log "Failed to inject child $pid"
                        fi
                    fi
                done
            done

            # Recheck periodically for new zygotes and application processes.
            sleep 5
        done
    ) &
}

main() {
    log "AlwaysTrustUserCerts - service.sh"

    # Wait until Android has completed booting and APEX mounts are available.
    # Abort after a bounded period instead of blocking forever.
    boot_wait=0

    while [ "$(getprop sys.boot_completed)" != 1 ]; do
        if [ "$boot_wait" -ge "$BOOT_COMPLETION_TIMEOUT" ]; then
            log "Timed out waiting for Android boot completion"
            return 1
        fi

        /system/bin/sleep 1s
        boot_wait=$((boot_wait + 1))
    done

    # Only use certificate files produced successfully by post-fs-data.sh.
    if [ ! -f "$CERTS_READY_FILE" ]; then
        log "Certificate collection did not complete"
        return 1
    fi

    # Detect the active Conscrypt certificate directory.
    APEX_CERT_DIR=$(find_apex_cert_dir)

    if [ -n "$APEX_CERT_DIR" ]; then
        log "Using Conscrypt certificate directory: $APEX_CERT_DIR"
        log "Grabbing apex certs"

        # Ensure the module certificate directory exists.
        if ! mkdir -p "$MODDIR$SYS_CERT_DIR"; then
            fail_setup "Failed to create module certificate directory"
            return 1
        fi

        # Refuse to hide a missing or invalid system certificate directory.
        if [ ! -d "$SYS_CERT_DIR" ]; then
            fail_setup "System certificate directory is unavailable: $SYS_CERT_DIR"
            return 1
        fi

        # Preserve the certificates collected by post-fs-data.sh and append
        # the active Conscrypt APEX certificates.
        for cert in "$APEX_CERT_DIR"/*; do
            [ -f "$cert" ] || continue

            if ! copy_certificate "$cert" "$MODDIR$SYS_CERT_DIR"; then
                fail_setup "Failed to copy apex certificate: $cert"
                return 1
            fi

            APEX_CERT_COUNT=$((APEX_CERT_COUNT + 1))
        done

        # Never replace the system trust store with an empty directory.
        if [ "$APEX_CERT_COUNT" -eq 0 ]; then
            fail_setup "No certificates found in $APEX_CERT_DIR"
            return 1
        fi

        if [ "$(count_certificates "$MODDIR$SYS_CERT_DIR")" -eq 0 ]; then
            fail_setup "Module certificate directory is empty"
            return 1
        fi

        # Create a writable certificate directory for the combined set.
        if ! "$MOUNT" -t tmpfs tmpfs "$SYS_CERT_DIR"; then
            fail_setup "Failed to mount tmpfs at $SYS_CERT_DIR"
            return 1
        fi

        TMPFS_MOUNTED=1

        if ! has_tmpfs_mount; then
            fail_setup "Certificate directory is not backed by the expected tmpfs"
            return 1
        fi

        # Copy the combined certificate set into the new mount.
        for cert in "$MODDIR$SYS_CERT_DIR"/*; do
            [ -f "$cert" ] || continue

            if ! cp -f "$cert" "$SYS_CERT_DIR/"; then
                fail_setup "Failed to copy certificate to $SYS_CERT_DIR: $cert"
                return 1
            fi
        done

        # Refuse to continue if the mounted directory is empty.
        if [ "$(count_certificates "$SYS_CERT_DIR")" -eq 0 ]; then
            fail_setup "Combined certificate directory is empty"
            return 1
        fi

        # Apply ownership, permissions, and SELinux labeling to the
        # certificate directory.
        chown root:root "$SYS_CERT_DIR" ||
            { fail_setup "Failed to set ownership on $SYS_CERT_DIR"; return 1; }

        chmod 755 "$SYS_CERT_DIR" ||
            { fail_setup "Failed to set permissions on $SYS_CERT_DIR"; return 1; }

        chcon u:object_r:system_security_cacerts_file:s0 "$SYS_CERT_DIR" ||
            { fail_setup "Failed to set SELinux context on $SYS_CERT_DIR"; return 1; }

        # Apply secure ownership, permissions, and SELinux labeling to each
        # certificate file.
        for cert in "$SYS_CERT_DIR"/*; do
            [ -f "$cert" ] || continue

            chown root:root "$cert" ||
                { fail_setup "Failed to set ownership on $cert"; return 1; }

            chmod 644 "$cert" ||
                { fail_setup "Failed to set permissions on $cert"; return 1; }

            chcon u:object_r:system_security_cacerts_file:s0 "$cert" ||
                { fail_setup "Failed to set SELinux context on $cert"; return 1; }
        done

        # Keep the mount applied to zygote and application namespaces.
        monitor_zygote
    else
        # Non-APEX devices use the module's /system certificate overlay.
        log "No Conscrypt APEX certificate directory found"
    fi

    log "Finished injecting certs"
}

main
exit $?
