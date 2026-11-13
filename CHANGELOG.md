## v1.4

- Fixed zygote mount detection by checking the current zygote PID.
- Added support for both 32-bit and 64-bit zygote processes.
- Reapplies certificate mounts after zygote restarts and namespace changes.
- Added support for versioned Conscrypt APEX paths.
- Added mount and certificate-copy error handling.
- Added staged certificate collection and publication.
- Added backup and recovery for interrupted certificate publication.
- Added a bounded five-minute boot-completion timeout.
- Improved certificate namespace injection for newer Android versions.
- Added the `action.sh` module action.
- The module action reports system, user, and total certificate counts.
- The module action reports AdGuard Personal CA status.
- Added Android 17 support documentation.

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
- Added support for multiple users.
- Added KernelSU support.

## v0.4.1

- Added Android 10 support.
- Updated compatibility with the Magisk module template v20.4+.

## v0.3

- Removed user-installed certificates from the system store before copying current certificates, preventing removed certificates from being retained.

## v0.2

- Fixed a directory creation bug.
- Updated compatibility with the Magisk module template v15+.

## v0.1

- Initial release.
