#!/system/bin/sh

# Directory where this script is installed.
MODDIR=${0%/*}

# Certificate directories.
MODULE_CERT_DIR="$MODDIR/system/etc/security/cacerts"
SYSTEM_CERT_DIR=/system/etc/security/cacerts
USER_CERT_ROOT=/data/misc/user

# Android filename of the AdGuard Personal CA.
ADGUARD_PERSONAL_FILENAME="0f4ed297.0"

# Use the module certificate directory when it exists.
if [ -d "$MODULE_CERT_DIR" ]; then
    SYSTEM_CERT_DIR="$MODULE_CERT_DIR"
fi

# Count certificate files in a directory.
count_certificates() {
    count=0

    for certificate in "$1"/*; do
        [ -f "$certificate" ] || continue
        count=$((count + 1))
    done

    echo "$count"
}

# Count certificates installed for all Android users.
count_user_certificates() {
    user_count=0

    for user_dir in "$USER_CERT_ROOT"/*; do
        [ -d "$user_dir/cacerts-added" ] || continue

        for certificate in "$user_dir/cacerts-added"/*; do
            [ -f "$certificate" ] || continue
            user_count=$((user_count + 1))
        done
    done

    echo "$user_count"
}

# Calculate certificate counts.
SYSTEM_CERT_COUNT=$(count_certificates "$SYSTEM_CERT_DIR")
USER_CERT_COUNT=$(count_user_certificates)
TOTAL_CERT_COUNT=$((SYSTEM_CERT_COUNT + USER_CERT_COUNT))

# Display certificate counts.
echo "Always Trust User Certificates"
echo "System certificates: $SYSTEM_CERT_COUNT"
echo "User certificates: $USER_CERT_COUNT"
echo "Total certificates: $TOTAL_CERT_COUNT"

# Display AdGuard status in green or red.
if [ -f "$SYSTEM_CERT_DIR/$ADGUARD_PERSONAL_FILENAME" ]; then
    printf 'AdGuard Personal CA: \033[1;32mON\033[0m\n'
else
    printf 'AdGuard Personal CA: \033[1;31mOFF\033[0m\n'
fi

exit 0