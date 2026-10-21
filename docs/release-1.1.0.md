# iOS SDK 1.1.0 release

This branch combines EGO-247 (review preparation and targeted dismissal) and EGO-248 (automatic presentation deduplication and confirmed visible-impression delivery). It extends the existing initialization API without requiring existing clients to enable preparation. Backend endpoints and payload schemas are unchanged.

## Validation

- `sh scripts/test-core.sh`: 14 portable regression cases passed.
- Preparation validation: deadline/cancellation, 200 races, targeted dismissal and callback ordering passed.
- All 92 Swift files parse with the installed Swift compiler; `swift package dump-package` validates the package manifest.
- Full iOS build and XCTest execution still require Xcode; this machine has Command Line Tools only.

Before merging, on a Mac with Xcode, build the demo and run the GravitySDK package tests on an available iOS Simulator. Use `xcodebuild -list` to select the SDK test scheme and `xcrun simctl list devices available` to select the simulator. The portable checks do not replace an iOS build.

## Maintainer publication steps

1. Review and merge this aggregate release MR into `main`. It includes both feature MR heads; there is no need to merge the original feature branches separately afterward. The current agent account is Developer and cannot merge the protected `main` branch.
2. After validation succeeds, create an annotated `1.1.0` tag on the merged `main` commit. Never reuse or move a published version tag.
3. Verify that the public repository `https://github.com/Gravity-Field/gravity-sdk-ios.git` contains the merged code and the `1.1.0` tag. GitLab and GitHub currently share their main commit, but mirror configuration and its publication trigger are not visible to the current account.
4. Verify the client installation using the published version, then distribute release notes. Client app teams must update the dependency, rebuild, and ship an app release.

To tag the reviewed merge commit from a checkout with `origin` pointing to GitLab:

```sh
git fetch origin main
git tag -a 1.1.0 origin/main -m "Gravity SDK 1.1.0"
git push origin refs/tags/1.1.0
```

Do not tag this unmerged branch as the official release. If `main` advances with unrelated changes, validate the intended release commit before tagging.

## Client integration

Existing integrations can keep using the existing `initialize` signature. EGO-248 behavior applies after upgrading the SDK. To enable reviews, implement the client's batch eligibility check, connect `inAppPreparation` and the review product builder, route the action to the client's review screen, and update the local review status only after a successful submission. Demo status storage is an example, not a server review API.

Demo credentials are configured locally. They are not defaults for client applications and are not needed to build the SDK library. Rotate any formerly committed active API key: rewritten branch history does not erase old MR snapshots, other branches, or existing clones.

## Rollback

Client teams can pin the previous published version (`1.0.6`) and release their application again. Preserve published tags and Maven artifacts. For a source rollback, revert the release changes through a new MR and publish a new version instead of replacing `1.1.0`. No backend rollout or data migration is required by these SDK changes.
