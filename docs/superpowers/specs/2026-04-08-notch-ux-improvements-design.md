# Notch UX Improvements Design

Three targeted improvements to Claude Island's notch behavior: fix auto-expand detection, add keyboard-driven approval, and make the instances panel height responsive.

## 1. Fix Auto-Expand on Approval

### Problem

`handlePendingSessionsChange` in `NotchView.swift` gates auto-expand on `!TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()`. This method uses `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`, which includes windows that are on the current macOS Space but occluded by other apps. Since VS Code ("Code") is in `TerminalAppRegistry.appNames`, having VS Code anywhere on the same Space blocks auto-expand — even when the user is in Safari, Slack, etc. and can't see the approval prompt.

### Fix

In `NotchView.swift`, `handlePendingSessionsChange`, replace:

```swift
!TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()
```

with:

```swift
!TerminalVisibilityDetector.isTerminalFrontmost()
```

`isTerminalFrontmost()` already exists and checks `NSWorkspace.shared.frontmostApplication` against `TerminalAppRegistry.bundleIdentifiers`. This matches the correct semantic: if the user is actively looking at a terminal app, they can see the approval prompt themselves; if they're in any other app, auto-expand.

### Files Changed

- `ClaudeIsland/UI/Views/NotchView.swift` — one line in `handlePendingSessionsChange`

## 2. Return Key to Approve and Minimize

### Behavior

When the notch is open and showing the instances list:
- A **selected session** is tracked (defaults to index 0 — the highest-priority session)
- **Arrow Up/Down** moves the selection through the sorted instances list
- **Return/Enter** on a `waitingForApproval` session approves it
- After approval, if no other sessions are `waitingForApproval`, the notch closes
- If other approvals remain, the selection moves to the next pending session and the notch stays open

### Visual Indicator

The selected row gets a brighter background highlight (e.g., `Color.white.opacity(0.1)`) distinct from the hover state. This is always visible when the instances view is showing — there's always exactly one selected row.

### Key Handling

Use `.onKeyPress` (macOS 14+, which is fine since the app requires macOS 15.6+) on the `ClaudeInstancesView` to handle:
- `.upArrow` — decrement `selectedIndex`, clamp to 0
- `.downArrow` — increment `selectedIndex`, clamp to `sortedInstances.count - 1`
- `.return` — if selected session is `waitingForApproval`, approve it

### State

- `@State private var selectedIndex: Int = 0` on `ClaudeInstancesView`
- Reset to 0 when `sortedInstances` changes (new sessions appear/disappear)
- Clamp to valid range on every access

### Approve-and-Close Flow

1. User presses Return on a `waitingForApproval` session
2. `approveSession(session)` is called (existing logic via `ClaudeSessionMonitor`)
3. After a 300ms delay (let the approval propagate), check if any remaining instances have `phase.isWaitingForApproval`
4. If none remain, call `viewModel.notchClose()`
5. If others remain, update `selectedIndex` to the next `waitingForApproval` session

### Files Changed

- `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` — add `selectedIndex` state, key handling, visual selection, approve-and-close logic
- `ClaudeIsland/UI/Views/NotchView.swift` — no changes needed (close is called from ClaudeInstancesView via viewModel)

## 3. Responsive Instances Panel Height

### Problem

The instances panel has a fixed height of 320px (`NotchViewModel.openedSize` for `.instances`). With 1-2 sessions, most of the panel is empty black space.

### Fix

Make the `.instances` case height dynamic based on session count.

**Row height calculation:** Each `InstanceRow` has 10px vertical padding top + bottom (20px total) plus ~34px of content (title line + subtitle line + spacing) = ~54px per row. Plus 4px vertical padding on the `LazyVStack` = 8px total.

```
height = rowHeight(54) * min(sessionCount, 5) + vStackPadding(8) + headerArea(40)
```

- **0 sessions (empty state):** 120px (enough for the "No sessions" message)
- **1 session:** ~102px
- **2 sessions:** ~156px
- **3 sessions:** ~210px
- **4 sessions:** ~264px
- **5+ sessions:** ~318px (effectively the old 320, scrollable)

Minimum height floor of 100px to avoid collapsing too small.

### Implementation

`NotchViewModel` needs access to the session count. Options:
- **A: Pass count in** — `ClaudeSessionMonitor` publishes `instances.count`; `NotchView` passes it to `NotchViewModel` (or the view model observes the monitor directly)
- **B: Computed in view** — Override `openedSize` in the view layer based on session count

**Choice: A** — `NotchViewModel` already drives sizing; add an `@Published var sessionCount: Int = 0` that `NotchView` keeps in sync from `sessionMonitor.instances.count`. The `openedSize` computed property uses it for the `.instances` case.

### Files Changed

- `ClaudeIsland/Core/NotchViewModel.swift` — add `sessionCount` property, dynamic height calc in `openedSize`
- `ClaudeIsland/UI/Views/NotchView.swift` — sync `sessionCount` from `sessionMonitor.instances.count`

## Summary of All File Changes

| File | Changes |
|------|---------|
| `NotchView.swift` | Fix `isTerminalFrontmost()` call; sync `sessionCount` to viewModel |
| `ClaudeInstancesView.swift` | Add keyboard selection, Return-to-approve, approve-and-close |
| `NotchViewModel.swift` | Add `sessionCount`, dynamic instances height |
