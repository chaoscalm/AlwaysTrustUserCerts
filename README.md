# Always Trust User Certificates

Always Trust User Certificates is a Magisk, KernelSU, and KernelSU Next module
that adds Android user-installed CA certificates to the system trust store.
This allows applications that do not trust user certificates by default to use
them without a `network_security_config` override.

> **Warning:** This changes certificate trust for the entire device. Only
> install certificates from sources you trust. Applications can still enforce
> certificate pinning or other custom trust rules.

## Features

- Supports Magisk, KernelSU, and KernelSU Next.
- Supports multiple Android users.
- Supports Android 7 through Android 17.
- Supports traditional system certificate directories.
- Supports Mainline Conscrypt APEX certificate directories.
- Detects standard and versioned Conscrypt APEX paths.
- Converts user certificates from DER to PEM format.
- Preserves PEM certificates without re-encoding them.
- Handles AdGuard Personal and Intermediate certificates specially.
- Stages certificate changes before publishing them.
- Removes certificates that were deleted from Android user profiles.
- Backs up and restores the previous certificate set.
- Recovers from interrupted publication after a reboot.
- Injects certificate mounts into zygote and application namespaces.
- Monitors both 32-bit (`zygote`) and 64-bit (`zygote64`) processes.
- Waits up to five minutes for Android boot completion.
- Provides an action script with certificate counts and status information.

## How It Works

Depending on the Android version and Google Play system update, certificates
may be stored in one of these locations:

- `/system/etc/security/cacerts`
- `/apex/com.android.conscrypt/cacerts`
- `/apex/com.android.conscrypt@VERSION/cacerts`

The module detects the active location automatically.

During `post-fs-data`, the module:

1. Reads system certificates.
2. Reads certificates from every Android user profile.
3. Converts DER-encoded user certificates to PEM format for compatibility with
   certificate consumers that read the directory directly, including
   BoringSSL-based stacks such as Flutter/Dart.
4. Applies the AdGuard certificate rules.
5. Builds the complete certificate set in a staging directory.
6. Backs up the currently published set.
7. Publishes the staged set and removes stale certificates.
8. Creates a completion marker only after publication succeeds.

If publication is interrupted or fails, the previous complete certificate set
is restored where possible.

## Conscrypt APEX Support

On devices using Mainline Conscrypt, `service.sh`:

1. Detects the active Conscrypt APEX certificate directory.
2. Adds its certificates to the collected module certificate set.
3. Creates a writable combined certificate directory.
4. Mounts the combined directory over the traditional system certificate path.
5. Applies ownership, permissions, and SELinux labels.
6. Injects the mount into zygote and application mount namespaces.

The service monitors both `zygote` and `zygote64`, and retries namespace
injection when processes restart or change namespaces.

The service waits up to **300 seconds** for `sys.boot_completed`. If Android
does not finish booting within that period, the service logs the failure and
exits instead of waiting indefinitely.

## AdGuard Certificate Handling

The module:

- Places the current AdGuard Personal CA in the system certificate set.
- Publishes the Personal CA using the required filename `0f4ed297.0`.
- Selects the newest Personal CA when multiple user profiles contain versions
  of the certificate.
- Keeps the AdGuard Intermediate CA out of the system set so it remains in the
  Android user certificate store.

## Installation

1. Install the CA certificate through Android Settings.
2. Install this module through Magisk, KernelSU, or KernelSU Next.
3. Reboot the device.
4. Verify the module log or run the module action.

The module must be active after reboot for newly installed or removed
certificates to be reflected in the system trust store.

## Module Action

Run the module action from the Magisk or KernelSU module interface.

The action reports:

- System certificate count.
- User certificate count across all Android users.
- Total certificate count.
- AdGuard Personal CA status.

Example:

```text
Always Trust User Certificates
System certificates: 42
User certificates: 3
Total certificates: 45
AdGuard Personal CA: ON
