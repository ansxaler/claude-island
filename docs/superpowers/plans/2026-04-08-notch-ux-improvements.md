# Notch UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix notch auto-expand detection, add Return-key approval with auto-minimize, and make the instances panel height responsive to session count.

**Architecture:** Three independent changes to the notch UI layer. Task 1 fixes a one-line bug in terminal detection. Task 2 adds keyboard event handling and selection state to ClaudeInstancesView. Task 3 pipes session count into NotchViewModel to compute dynamic panel height.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS 15.6+)

**No test target exists** — verification is build + manual testing.

---

## File Map

| File | Role | Tasks |
|------|------|-------|
| `ClaudeIsland/UI/Views/NotchView.swift` | Main notch view, event handlers | 1, 3 |
| `ClaudeIsland/Core/NotchViewModel.swift` | Notch state/sizing | 3 |
| `ClaudeIsland/UI/Views/ClaudeInstancesView.swift` | Session list, row rendering | 2 |

---

### Task 1: Fix Auto-Expand Terminal Detection

**Files:**
- Modify: `ClaudeIsland/UI/Views/NotchView.swift:424`

- [ ] **Step 1: Fix the terminal visibility check**

In `NotchView.swift`, in the `handlePendingSessionsChange` method (line 418), replace the `isTerminalVisibleOnCurrentSpace()` call with `isTerminalFrontmost()`:

```swift
// Before (line 422-424):
if !newPendingIds.isEmpty &&
   viewModel.status == .closed &&
   !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace() {

// After:
if !newPendingIds.isEmpty &&
   viewModel.status == .closed &&
   !TerminalVisibilityDetector.isTerminalFrontmost() {
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ClaudeIsland/UI/Views/NotchView.swift
git commit -m "fix: use frontmost app check for auto-expand gating

isTerminalVisibleOnCurrentSpace() includes occluded windows on the
same Space, so VS Code behind other apps blocked auto-expand.
isTerminalFrontmost() checks the active app, matching user intent."
```

---

### Task 2: Return Key to Approve and Minimize

**Files:**
- Modify: `ClaudeIsland/UI/Views/ClaudeInstancesView.swift`

- [ ] **Step 1: Add selection state and keyboard handling to ClaudeInstancesView**

Add a `selectedIndex` state property and key press handlers. In `ClaudeInstancesView`, add the state and modify `instancesList` to include keyboard handling:

```swift
struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: NotchViewModel

    @State private var selectedIndex: Int = 0
```

Replace the existing `instancesList` computed property with:

```swift
private var instancesList: some View {
    ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 2) {
            ForEach(Array(sortedInstances.enumerated()), id: \.element.stableId) { index, session in
                InstanceRow(
                    session: session,
                    isSelected: index == clampedSelectedIndex,
                    onFocus: { focusSession(session) },
                    onChat: { openChat(session) },
                    onArchive: { archiveSession(session) },
                    onApprove: { approveSession(session) },
                    onReject: { rejectSession(session) }
                )
                .id(session.stableId)
            }
        }
        .padding(.vertical, 4)
    }
    .scrollBounceBehavior(.basedOnSize)
    .onKeyPress(.upArrow) {
        selectedIndex = max(0, clampedSelectedIndex - 1)
        return .handled
    }
    .onKeyPress(.downArrow) {
        selectedIndex = min(sortedInstances.count - 1, clampedSelectedIndex + 1)
        return .handled
    }
    .onKeyPress(.return) {
        let index = clampedSelectedIndex
        guard index < sortedInstances.count else { return .ignored }
        let session = sortedInstances[index]
        guard session.phase.isWaitingForApproval else { return .ignored }
        approveAndMaybeClose(session)
        return .handled
    }
    .onChange(of: sortedInstances.map(\.stableId)) { _, _ in
        // Reset selection when list changes
        selectedIndex = 0
    }
}
```

Add the clamped index helper and the approve-and-close method:

```swift
private var clampedSelectedIndex: Int {
    guard !sortedInstances.isEmpty else { return 0 }
    return min(selectedIndex, sortedInstances.count - 1)
}

private func approveAndMaybeClose(_ session: SessionState) {
    approveSession(session)

    // Check after a short delay if any approvals remain
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        let stillPending = sessionMonitor.instances.contains { $0.phase.isWaitingForApproval }
        if !stillPending {
            viewModel.notchClose()
        } else {
            // Move selection to next pending approval
            if let nextIndex = sortedInstances.firstIndex(where: { $0.phase.isWaitingForApproval }) {
                selectedIndex = nextIndex
            }
        }
    }
}
```

- [ ] **Step 2: Add `isSelected` parameter to InstanceRow and apply visual highlight**

Update the `InstanceRow` struct to accept and display the selection state:

```swift
struct InstanceRow: View {
    let session: SessionState
    let isSelected: Bool
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    // ... rest unchanged
```

Update the background modifier on the row's outer `HStack` (currently at line 286-288):

```swift
// Before:
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
)

// After:
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(isSelected ? Color.white.opacity(0.1) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
)
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/UI/Views/ClaudeInstancesView.swift
git commit -m "feat: add Return key to approve selected session and minimize

Arrow up/down navigates sessions, Return approves the selected
session waiting for approval. Notch closes after approval if no
other approvals remain."
```

---

### Task 3: Responsive Instances Panel Height

**Files:**
- Modify: `ClaudeIsland/Core/NotchViewModel.swift:41-85`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift:201-207`

- [ ] **Step 1: Add sessionCount to NotchViewModel and compute dynamic height**

In `NotchViewModel.swift`, add a published property after the existing `@Published` properties (around line 44):

```swift
@Published var status: NotchStatus = .closed
@Published var openReason: NotchOpenReason = .unknown
@Published var contentType: NotchContentType = .instances
@Published var isHovering: Bool = false
@Published var sessionCount: Int = 0
```

Update the `.instances` case in the `openedSize` computed property (line 79-83):

```swift
// Before:
case .instances:
    return CGSize(
        width: min(screenRect.width * 0.4, 480),
        height: 320
    )

// After:
case .instances:
    let rowHeight: CGFloat = 54
    let vStackPadding: CGFloat = 8
    let headerArea: CGFloat = 40
    let rows = min(max(sessionCount, 0), 5)
    let dynamicHeight = CGFloat(rows) * rowHeight + vStackPadding + headerArea
    let height = sessionCount == 0 ? CGFloat(120) : max(100, dynamicHeight)
    return CGSize(
        width: min(screenRect.width * 0.4, 480),
        height: height
    )
```

- [ ] **Step 2: Sync sessionCount from NotchView**

In `NotchView.swift`, in the existing `.onChange(of: sessionMonitor.instances)` handler (line 204-207), add synchronization of the session count:

```swift
// Before:
.onChange(of: sessionMonitor.instances) { _, instances in
    handleProcessingChange()
    handleWaitingForInputChange(instances)
}

// After:
.onChange(of: sessionMonitor.instances) { _, instances in
    viewModel.sessionCount = instances.count
    handleProcessingChange()
    handleWaitingForInputChange(instances)
}
```

Also set the initial count in `.onAppear` (around line 191-197):

```swift
// Before:
.onAppear {
    sessionMonitor.startMonitoring()
    if !viewModel.hasPhysicalNotch {
        isVisible = true
    }
}

// After:
.onAppear {
    sessionMonitor.startMonitoring()
    viewModel.sessionCount = sessionMonitor.instances.count
    if !viewModel.hasPhysicalNotch {
        isVisible = true
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -scheme ClaudeIsland -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ClaudeIsland/Core/NotchViewModel.swift ClaudeIsland/UI/Views/NotchView.swift
git commit -m "feat: make instances panel height responsive to session count

Panel now sizes to fit up to 5 sessions, with scrolling beyond that.
Eliminates empty black space when only 1-2 sessions are active."
```

---

## Verification

After all three tasks, manually test:

1. **Auto-expand:** Run Claude Code in VS Code terminal. Switch to Safari. Trigger a tool that needs approval. Notch should auto-expand. Switch back to VS Code — notch should NOT auto-expand on next approval.
2. **Return key:** Open notch, see sessions. Arrow keys should move selection highlight. Return on a pending approval should approve it and close the notch.
3. **Responsive height:** With 1 session, panel should be compact. Add more sessions (run multiple Claude instances) — panel grows. At 5+, it scrolls.
