# Atria 1.4.1k4 test matrix

Run the smoke tests on supported iOS 15/16 devices and on each newer iOS
release targeted by the package. Test both a rootless installation and a
RootHide installation where those bootstraps are available. Run the layout
matrix once with Atria alone and once with any independently installed icon-
placement tweak that the tester is licensed to use. Treat that product as a
black box: do not copy, compile, redistribute, or depend on its implementation.

## Build and package checks

- `make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless`
- `make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide`
- Verify control fields: `me.ancal.atria`, `1.4.1k4`, and the expected package
  architecture (`iphoneos-arm64` or `iphoneos-arm64e`).
- Verify the preference bundle, PreferenceLoader plist, tweak dylib, editor
  assets, and script editor classes are present in each package. If an optional
  `Custom.ttf` is supplied for a release, verify it separately.
- Install each package on its matching bootstrap and confirm Preferences opens
  before respringing SpringBoard.
- In Preferences, choose `Dock 비우기`, cancel once, then confirm once. Every
  user-Dock app and folder must move to available Home Screen space without
  changing the pre-existing page order, free-placement coordinates,
  hidden/Focus metadata, folder contents, or custom folder names. Repeat with
  an already empty Dock and expect an explicit no-op result.
- During a Dock reset, begin and end icon editing/dragging and verify the action
  waits or fails closed. Restart SpringBoard after a successful reset and
  confirm the empty Dock and moved icons persist. Test with Atria both enabled
  and disabled, and on regular and floating user Docks.
- On RootHide, confirm SpringBoard completes its first launch after injection;
  no tweak constructor may ask UIKit for interface state while dyld initializers
  are still running.
- On iOS 17 and newer, open the home-screen editor by both triple tap and an
  icon shortcut, select every editor target, and verify no safe-mode transition.
- On iOS 16 and newer, apply nonzero positive and negative page-indicator X/Y
  offsets. The complete `SBFolderScrollAccessoryView` should move, as in
  upstream Atria, so its page control, Search/background geometry, animations,
  and hit area remain aligned. On iOS 15, only the direct page control moves.
- Relayout, rotate, lock/unlock, enter/leave page editing, and add/remove pages
  with a nonzero page-indicator offset. The offset must neither reset nor drift.
- Type a negative offset with the editor toolbar's minus button and verify the
  stored value and active editor control agree after closing and reopening.
- With `슬라이더 대신 −/+ 버튼 사용` off, verify all existing slider ranges,
  rotation swaps, reset, manual entry, and per-page behavior are unchanged.
- With it on, select each unit from the compact `1×` menu:
  `10, 5, 2, 1, 0.5, 0.1, 0.05, 0.01`,
  cross each former slider endpoint with −/+, and confirm the large current
  value persists. Rows and columns must skip fractional units, reject values
  below 1, round fractional manual input before layout, and stop at the
  SpringBoard-safe 64-per-axis guard. Alpha/intensity stay within `0...1` and
  scale/font/radius keep their semantic minimum. Export and re-import an
  extended geometry value that crossed its former slider endpoint.
- On iOS 26 and newer, force-enable the floating dock, edit it, and verify its
  controller and recents model use the context-provider initializer without
  losing background-opacity updates.
- On iOS 26.2 and newer, activate every Atria icon shortcut through
  `SBHIconViewApplicationShortcutsContextMenuProvider`; a removed legacy route
  must be skipped rather than installed.
- Scroll through App Library special indicators on iOS 26 and verify missing
  `application` and folder-background selectors are safely ignored.

## Layout and third-party coexistence checks

| Area | Action | Expected result |
| --- | --- | --- |
| Startup | Respring, unlock, and swipe through every page | No respring loop, disappearing icons, or rewrite of another tweak's saved positions |
| Root pages | Change rows, columns, spacing, insets, scale, and per-page overrides | Atria geometry applies; independently managed positions remain stable |
| Rotation | Rotate on root, folder, and floating dock | Correct orientation save is selected; no stale model location or icon jump |
| Drag | Drag single icons, groups, and widgets within and across pages | Drop index follows the current Atria grid and remains in bounds |
| App Library drag | Drag an app from App Library to root and back out of a pending drop | App Library models are untouched; the new root icon receives a valid position |
| Regular dock | Change rows, columns, spacing, and scale, then drag icons | User Dock icons lay out normally; no third-party preference domain is written by Atria |
| Floating dock | Test user icons, recents, suggestions, and App Library pod | Atria geometry applies to the user list; any requested view refresh leaves suggestion, recents, pod, admission, and saved-state models system-owned |
| Folder open | Open, close, rotate, edit, and add icons to a normal folder | Sparse positions and zoom animation agree; no preview crash |
| Folder preview | Compare first and later folder pages | Each page uses its own model and no stale layout state leaks between hosts |
| App Library “more apps” | Open a normal folder first, close it, then scroll every App Library category | The additional-items tile keeps all four mini app icons; none collapse to one, overlap, or inherit another host's frame |
| App Library pods | Scroll categories before and after opening a normal folder | Pod/category mini-icons keep their native image and frame |
| Today/widget UI | Open Today View and widget stack edit screens | Atria leaves transient and system grids unchanged |
| Page rebuild | Add/delete/reorder pages and toggle per-page mode | Weak model mapping refreshes and no deleted page remains classified |
| Disabled layout | Disable Atria layout and respring with another placement tweak enabled | Atria layout hooks do not alter normal SpringBoard behavior |

## Label-script checks

- Create, duplicate, reorder, nest, undo, and delete every visual block type.
- From a row menu, open both “insert below” and “change type” repeatedly; the
  next catalog must appear only after the action sheet finishes dismissing.
- Double-tap add/edit controls and confirm only one catalog opens; save both a
  modal time picker and weekday picker and confirm each sheet closes once.
- Copy and paste blocks up to each script limit; an over-limit edit must be
  cancelled immediately without replacing the last valid editor state.
- Switch visual/source modes repeatedly and confirm a no-op round trip produces
  equivalent JSON.
- Confirm invalid JSON, unknown block/condition types, excessive nesting,
  oversized strings, non-finite numbers, and out-of-range waits/repeats are
  rejected without replacing the last valid saved script.
- Run `loop: false` and confirm it stops after one root pass.
- Run `loop: true` and a repeat block with `times: 0`; confirm both yield to the
  run loop and remain cancellable without busy-looping SpringBoard.
- Exercise empty branches, zero-step repeats, battery/weather/text conditions,
  and a script that reaches the per-advance execution budget.
- Disable the script while a timer is pending and confirm no stale callback
  updates a removed page label.

## General smoke checks

- Import a valid exported settings string, then try a malformed, oversized, and
  wrong-typed import. Invalid imports must leave the current domain unchanged.
- Import an older export containing `_N_*`, `welcome_*`, and `background_*`
  keys. Multi-digit page prefixes must normalize to `PageN_`, a complete page
  layout must restore its marker, and a lone orphan key must not enable one.
- Edit a numeric field with both dot and comma decimal separators.
- Rapidly close and reopen the homescreen editor; the new editor must not be
  removed by the old animation completion.
- Toggle light/dark mode and verify the regular dock background is restored.
- Type in Atria's page-label editor and then in unrelated SpringBoard fields;
  only Atria's active label editor may suppress automatic scroll-to-visible.
- Load a named font, imported font, weather tokens, greeting tokens, battery,
  weekday, and time tokens on both package schemes.
