#!/system/bin/sh

MODDIR=${0%/*}

# Keep the source certificate directory separate from the module's writable
# mirror so the collected set can be assembled before it is published.
SYS_CERT_DIR=/system/etc/security/cacerts
LIVE_CERT_DIR="$MODDIR$SYS_CERT_DIR"
STAGING_DIR="$MODDIR/.certs-staging"
BACKUP_DIR="$MODDIR/.certs-backup"
# This journal makes an interrupted publish recoverable on the next boot.
PUBLISH_STATE_FILE="$MODDIR/.cert-publish-state"
# Created only after the complete certificate set has been published.
CERTS_READY_FILE="$MODDIR/.certs-ready"

# AdGuard Personal CA belongs in the system store.
# AdGuard Intermediate CA must remain in the user store.
ADGUARD_PERSONAL_HASH="0f4ed297"
ADGUARD_PERSONAL_FILENAME="${ADGUARD_PERSONAL_HASH}.0"
ADGUARD_INTERMEDIATE_HASH="47ec1af8"
ADGUARD_INTERMEDIATE_TEXT="Guard Personal Intermediate"

log() {
    echo "$(date '+%m-%d %H:%M:%S ')" "$@" >> "$MODDIR/log.txt"
}

# Match the certificate by its Android hashed filename.
is_adguard_personal() {
    case "$(basename "$1")" in
        "$ADGUARD_PERSONAL_HASH".*)
            return 0
            ;;
    esac

    return 1
}

# Match either the hashed filename or the certificate's subject text because
# Android may assign a different numeric suffix to the same certificate.
is_adguard_intermediate() {
    local certificate="$1"
    local name

    name=$(basename "$certificate")

    case "$name" in
        "$ADGUARD_INTERMEDIATE_HASH".*)
            return 0
            ;;
    esac

    if grep -q "$ADGUARD_INTERMEDIATE_TEXT" "$certificate" 2>/dev/null; then
        return 0
    fi

    return 1
}

# User certificate stores can contain several versions of the Personal CA.
# Select the file with the greatest numeric suffix as the current version.
find_adguard_personal_certificate() {
    local cert
    local suffix
    local best_suffix=""
    local best_cert=""

    for cert in /data/misc/user/*/cacerts-added/"$ADGUARD_PERSONAL_HASH".*; do
        [ -f "$cert" ] || continue

        suffix=${cert##*.}

        case "$suffix" in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        if [ -z "$best_suffix" ] || [ "$suffix" -gt "$best_suffix" ]; then
            best_suffix=$suffix
            best_cert=$cert
        fi
    done

    printf '%s\n' "$best_cert"
}

# Copy a certificate while preserving both distinct files and duplicate
# contents that happen to use the same filename.
copy_certificate() {
    local source="$1"
    local destination_dir="$2"
    local name
    local target
    local base
    local index

    name=$(basename "$source")
    target="$destination_dir/$name"

    if [ -e "$target" ]; then
        if cmp -s "$source" "$target"; then
            return 0
        fi

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

# The Personal CA has a required filename, so it is copied explicitly.
copy_certificate_as() {
    local source="$1"
    local destination_dir="$2"
    local name="$3"

    cp -f "$source" "$destination_dir/$name"
}

# Staging is disposable and is rebuilt for every run.
clear_staged_certificates() {
    rm -rf "$STAGING_DIR"
}

# Record whether the live directory is backed up, or has been fully replaced.
write_publish_state() {
    printf '%s\n' "$1" > "$PUBLISH_STATE_FILE"
}

# Save the currently published set before making any changes to it.
backup_live_certificates() {
    local cert
    local name

    if ! rm -rf "$BACKUP_DIR" ||
        ! mkdir -p "$BACKUP_DIR"; then
        log "Failed to prepare certificate backup directory"
        return 1
    fi

    for cert in "$LIVE_CERT_DIR"/*; do
        [ -f "$cert" ] || continue

        name=$(basename "$cert")

        if ! cp -f "$cert" "$BACKUP_DIR/$name"; then
            log "Failed to back up certificate: $name"
            return 1
        fi
    done
}

# Restore the previous set after a partial or failed publication.
restore_live_certificates() {
    local cert
    local name

    if ! mkdir -p "$LIVE_CERT_DIR"; then
        log "Failed to recreate live certificate directory"
        return 1
    fi

    if ! rm -f "$LIVE_CERT_DIR"/*; then
        log "Failed to clear incomplete live certificate set"
        return 1
    fi

    for cert in "$BACKUP_DIR"/*; do
        [ -f "$cert" ] || continue

        name=$(basename "$cert")

        if ! cp -f "$cert" "$LIVE_CERT_DIR/$name"; then
            log "Failed to restore certificate: $name"
            return 1
        fi
    done
}

# Finish or roll back a publication that was interrupted by a reboot.
recover_interrupted_publish() {
    local state

    [ -f "$PUBLISH_STATE_FILE" ] || {
        rm -rf "$BACKUP_DIR"
        return 0
    }

    state=$(cat "$PUBLISH_STATE_FILE")

    case "$state" in
        prepared)
            log "Recovering interrupted certificate publication"

            if ! restore_live_certificates; then
                log "Failed to recover previous certificate set"
                return 1
            fi
            ;;
        published)
            log "Cleaning up completed certificate publication"
            ;;
        *)
            log "Unknown certificate publication state: $state"

            if ! restore_live_certificates; then
                log "Failed to recover from unknown publication state"
                return 1
            fi
            ;;
    esac

    rm -f "$PUBLISH_STATE_FILE"
    rm -rf "$BACKUP_DIR"
}

# Build the desired certificate set in a temporary directory. The live
# directory is not changed until this collection step succeeds.
collect_certificates() {
    local certificate_count=0
    local certificate_name
    local adguard_personal

    if ! rm -rf "$STAGING_DIR" ||
        ! mkdir -p "$STAGING_DIR"; then
        log "Failed to prepare certificate staging directory"
        return 1
    fi

    log "Grabbing system certificates"

    for cert in "$SYS_CERT_DIR"/*; do
        [ -f "$cert" ] || continue

        # Do not keep an obsolete Personal CA from the system store.
        if is_adguard_personal "$cert"; then
            log "Skipping stale AdGuard Personal CA: $(basename "$cert")"
            continue
        fi

        # The Intermediate CA must remain user-store-only.
        if is_adguard_intermediate "$cert"; then
            certificate_name=$(basename "$cert")
            log "Skipping AdGuard Intermediate CA: $certificate_name"
            continue
        fi

        if ! copy_certificate "$cert" "$STAGING_DIR"; then
            log "Failed to copy system certificate: $cert"
            return 1
        fi

        certificate_count=$((certificate_count + 1))
    done

    log "Grabbing user certificates"

    for user_dir in /data/misc/user/*; do
        [ -d "$user_dir/cacerts-added" ] || continue

        for cert in "$user_dir/cacerts-added"/*; do
            [ -f "$cert" ] || continue

            # The Personal CA is selected after all profiles are scanned.
            if is_adguard_personal "$cert"; then
                continue
            fi

            # Keep the Intermediate CA in the Android user store.
            if is_adguard_intermediate "$cert"; then
                certificate_name=$(basename "$cert")
                log "Skipping AdGuard Intermediate CA: $certificate_name"
                continue
            fi

            if ! copy_certificate "$cert" "$STAGING_DIR"; then
                log "Failed to copy user certificate: $cert"
                return 1
            fi

            certificate_count=$((certificate_count + 1))
            log "Grabbing user certificate: $(basename "$cert")"
        done
    done

    # AdGuard requires its current Personal CA to be named exactly .0.
    adguard_personal=$(find_adguard_personal_certificate)

    if [ -n "$adguard_personal" ]; then
        if ! copy_certificate_as \
            "$adguard_personal" \
            "$STAGING_DIR" \
            "$ADGUARD_PERSONAL_FILENAME"; then
            log "Failed to copy AdGuard Personal CA"
            return 1
        fi

        certificate_count=$((certificate_count + 1))
        log "Added current AdGuard Personal CA as $ADGUARD_PERSONAL_FILENAME"
    else
        log "No AdGuard Personal CA found in user certificate stores"
    fi

    log "Collected $certificate_count pre-APEX certificate files"
}

# Replace the live set transactionally: back it up, publish the staged files,
# remove stale files, and clean up the journal only after success.
publish_certificates() {
    local cert
    local name

    if ! backup_live_certificates; then
        return 1
    fi

    if ! write_publish_state prepared; then
        log "Failed to create publication journal"
        rm -rf "$BACKUP_DIR"
        return 1
    fi

    if ! mkdir -p "$LIVE_CERT_DIR"; then
        log "Failed to create live certificate directory"
        restore_live_certificates
        return 1
    fi

    for cert in "$STAGING_DIR"/*; do
        [ -f "$cert" ] || continue

        name=$(basename "$cert")

        if ! cp -f "$cert" "$LIVE_CERT_DIR/$name"; then
            log "Failed to publish certificate: $name"
            restore_live_certificates
            return 1
        fi
    done

    for cert in "$LIVE_CERT_DIR"/*; do
        [ -f "$cert" ] || continue

        name=$(basename "$cert")

        if [ ! -f "$STAGING_DIR/$name" ] &&
            ! rm -f "$cert"; then
            log "Failed to remove stale certificate: $name"
            restore_live_certificates
            return 1
        fi
    done

    if ! write_publish_state published; then
        log "Failed to finalize publication journal"
        restore_live_certificates
        return 1
    fi

    rm -rf "$BACKUP_DIR"
    rm -f "$PUBLISH_STATE_FILE"
    clear_staged_certificates
}

# The post-fs-data hook runs early in boot, before consumers need the
# certificate set. Failures are logged and leave the previous set intact.
main() {
    if ! : > "$MODDIR/log.txt"; then
        return 1
    fi

    if ! recover_interrupted_publish; then
        log "Failed to recover interrupted publication"
        return 1
    fi

    if ! rm -f "$CERTS_READY_FILE"; then
        log "Failed to remove certificate completion marker"
        return 1
    fi

    log "AlwaysTrustUserCerts - post-fs-data.sh"

    if ! collect_certificates; then
        log "Failed to collect certificates"
        clear_staged_certificates
        return 1
    fi

    if ! publish_certificates; then
        log "Failed to publish certificates"
        clear_staged_certificates
        return 1
    fi

    if ! : > "$CERTS_READY_FILE"; then
        log "Failed to mark certificate completion"
        return 1
    fi

    log "Finished collecting certificates"
}

main
exit $?
