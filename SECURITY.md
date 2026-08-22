# Security policy

## Supported versions

Security fixes are provided for the latest tagged release.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use GitHub's **Security → Report a vulnerability** flow for this repository. Include the affected version, reproduction steps, and the user-owned files or commands involved. You should receive an acknowledgement within seven days.

## Runtime boundary

The plugin runs unsandboxed as part of `omarchy-shell`, exactly as described by Omarchy's plugin model. It invokes only its bundled helper, `hyprctl`, `xkbcli`, `jq`, and standard local shell utilities. It performs no telemetry or runtime network requests and never requests root privileges.
