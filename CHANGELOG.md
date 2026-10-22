# Changelog

## Unreleased

* Add `getContentBySelectorWithDetails` and `getContentByCampaignIdWithDetails`: the model plus the raw JSON of the same response
* Add `CampaignContent.rawVariables` and key access on `Variables` for keys with no typed counterpart

## 1.0.6

* Add presentation lock to suppress campaign display

## 1.0.5

* Remove force unwrap
* Use child controller for snackbar
* Make snackbar dismiss idempotent
* Add custom font
* Add background image
* Fix bottom sheet layout
* Add GravityWebView
* Add loader to inline view
* Add verticalAlignment to Style for content alignment
* Add element with type ITEMS_CONTAINER and campaign steps logic
* Support layoutWidth in GravityText
* Add GravityInlineListView
* Fallback products container type to row
* Fix products container layout
* Fix image sizing without height
* Fix custom font weight
* Fix image rendering

## 1.0.4

* Marked `GravityLogListener` as `@Sendable`

## 1.0.3

* Added `setLogListener` to forward SDK logs to a custom callback

## 1.0.2

* Improved SDK log visibility

## 1.0.1

* Removed trailing commas

## 1.0.0

* Public methods no longer crash when called before `GravitySDK.initialize()`
* Default `logLevel` is now `.error` instead of `.none`

## 0.1.0

* Replace `import SwiftUICore` with `import SwiftUI`

## 0.0.9

* Initial release
