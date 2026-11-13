# Always Trust User Certificates

A Magisk/KernelSU module that copies Android user-installed CA certificates into the system trust store, allowing applications that normally reject user certificates to trust them without a `network_security_config` override.

> **Warning:** This changes the device-wide certificate trust configuration. Applications that normally reject user certificates may trust them after the module is enabled. Install certificates only from sources you trust.

## Features

- Supports Magisk, KernelSU, and KernelSU Next.
- Supports multiple Android users.
- Supports Android 7 through Android 17.
- Supports traditional system CA directories and Mainline Conscrypt.
- Detects standard and versioned Conscrypt APEX certificate paths.
- Stages certificate updates before publishing them.
- Preserves the previous certificate set if collection or publication fails.
- Recovers from interrupted certificate publication after reboot.
- Injects certificate mounts into zygote and application namespaces.
- Monitors both 32-bit (`zygote`) and 64-bit (`zygote64`) zygotes.
- Reapplies mounts after namespace changes or zygote restarts.
- Waits up to five minutes for Android boot completion instead of looping indefinitely.
- Includes AdGuard Personal CA handling.
- Includes an action script for certificate counts and status reporting.

Depending on the Android version and Google Play system update, certificates may be stored in:

- `/system/etc/security/cacerts`
- `/apex/com.android.conscrypt/cacerts`
- `/apex/com.android.conscrypt@VERSION/cacerts`

The module detects the active location automatically.

## Installation

1. Install a CA certificate through Android Settings.
2. Install this module through Magisk, KernelSU, or KernelSU Next.
3. Reboot the device.
4. Check the module log or run the module action to display certificate counts.

After reboot, collected user certificates are included in the system trust store. Applications may still enforce certificate pinning or other custom trust restrictions.

## Certificate Collection and Publication

During early boot, the module:

1. Collects system certificates and certificates installed for all Android users.
2. Excludes stale or user-store-only AdGuard certificates where required.
3. Builds the desired certificate set in a staging directory.
4. Backs up the currently published certificate set.
5. Publishes the staged set and removes stale files.
6. Marks the set ready only after publication succeeds.

If publication is interrupted or fails, the previous certificate set is restored where possible. This prevents a partial update from replacing the working trust store with an incomplete one.

## Conscrypt and Namespace Injection

On devices with a Conscrypt APEX, `service.sh` creates a writable combined certificate directory and bind-mounts it into the active Conscrypt certificate path.

Android processes can use separate mount namespaces, so the service checks and injects the mount for both zygotes and their application children.

The service waits up to **300 seconds** for `sys.boot_completed`. If boot does not complete within that period, it logs a timeout and exits instead of running forever.

## Module Action

The included `action.sh` script displays certificate counts and AdGuard status.

Run the action from the Magisk or KernelSU module action interface. It reports:

- System certificate count
- User certificate count across all Android users
- Total certificate count
- Whether the AdGuard Personal CA is enabled

Example output:

```text
Always Trust User Certificates
System certificates: 42
User certificates: 3
Total certificates: 45
AdGuard Personal CA: ON
