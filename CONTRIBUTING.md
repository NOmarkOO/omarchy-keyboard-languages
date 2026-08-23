# Contributing

Thanks for helping make keyboard switching feel at home in Omarchy.

## Before opening a pull request

1. Reproduce the change on the latest Omarchy Quattro release.
2. Keep all writes inside user-owned Omarchy config and state locations.
3. Never introduce a full Hyprland reload for an ordinary keyboard change.
4. Reuse Quattro's shared components and semantic style values for UI work.
5. Run `./test.sh` and include screenshots for visible changes.

Keep pull requests focused. Describe the affected layout/variant, bar position, monitor arrangement, and theme when relevant. Do not include personal keyboard state, credentials, or generated backups.

## Release safety

Release installation is commit-bound. First commit the complete versioned payload and let CI pass. Then use its full 40-character SHA in a documentation-only commit for both the raw installer URL and `install.sh --commit` argument. Tag the payload commit and copy the same exact-SHA command into the GitHub release; never publish a branch or tag as the executable install source.

## Commit style

Use short imperative subjects, explain safety-sensitive decisions in the body, and add a changelog entry for user-visible behavior.
