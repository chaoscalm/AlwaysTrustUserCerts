# Changelog

## v1.5

- Converts DER-encoded user certificates to PEM format for applications and
  BoringSSL-based stacks that read the certificate directory directly.
- Preserves user certificates that are already PEM-encoded.
- Added explicit handling for AdGuard Personal and Intermediate certificates.
- Updated the README with certificate conversion, troubleshooting, and
  compatibility documentation.

## v1.4

- Added support for both 32-bit and 64-bit zygote processes.
- Reapplies certificate mounts after zygote restarts and namespace changes.
- Added support for standard and versioned Conscrypt APEX paths.
- Improved mount, certificate-copy, and namespace-injection error handling.
- Added staged certificate collection and publication.
- Added backup and rollback support for certificate publication failures.
- Added recovery for certificate publication interrupted by reboot.
- Removes certificates that are no longer installed for Android users.
- Added a bounded five-minute boot-completion timeout.
- Added the `action.sh` module action.
- The module action reports system, user, and total certificate counts.
- The module action reports AdGuard Personal CA status.
- Improved documentation for Android 17 and newer certificate layouts.

## v1.3

- Fixed bugs on Android 14 and later.

## v1.2

- Added automatic update support.

## v1.1

- Fixed permission issues for non-Conscrypt devices.
- Fixed certificate removal for non-Conscrypt devices.
- Renamed the repository.

## v1.0

- Added support for Mainline Conscrypt certificates.
- Added support for multiple Android users.
- Added KernelSU support.

## v0.4.1

- Added Android 10 support.
- Updated compatibility with the Magisk module template v20.4+.

## v0.3

- Removed user-installed certificates from the system store before copying
  current certificates, preventing removed certificates from being retained.

## v0.2

- Fixed a directory creation bug.
- Updated compatibility with the Magisk module template v15+.

## v0.1

- Initial release.
