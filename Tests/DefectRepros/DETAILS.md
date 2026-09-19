# Defect details

Companion to [README.md](README.md). Same numbering.

## Confirmed (73)

### D1. Chunks are dropped and the result is truncated when a loader calls completion from a higher-QoS thread

_Severity: high · user impact: medium · public API: yes · found by: concurrency-stress, data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:153`

**Repro:** [NukeThreadSafetyTests/concurrency-stress--data-loader-callbacks-reordered.swift](NukeThreadSafetyTests/concurrency-stress--data-loader-callbacks-reordered.swift), [NukeTests/data-loading-tasks--completion-overtakes-last-chunk.swift](NukeTests/data-loading-tasks--completion-overtakes-last-chunk.swift)

**What:** Each `didReceiveData` and `completion` callback moves to the pipeline actor in its own unstructured `Task { @ImagePipelineActor in ... }` (lines 153-155, 162-166, 170-174). Each Task inherits the priority of the calling thread, and the actor runs higher-priority jobs first. The DataLoading docs allow calling both callbacks from any thread. If `completion` comes from a higher-QoS thread than the chunks, `finishDataLoad` runs first and clears `dataLoadContinuation`. `dataTaskDidReceive` then drops every late chunk (`guard dataLoadContinuation != nil`). The request either fails with `.dataIsEmpty`, or succeeds with truncated data that is also written to the disk cache. The repro loader delivers two chunks from `.background` threads and then completes from a `.userInteractive` thread; each call finishes before the next one starts, so the loader follows the contract.

**Expected:** `data(for:)` returns all 22789 bytes and the disk cache holds the full data.

**Actual:** The request fails with `ImagePipeline.Error.dataIsEmpty` because both chunks are dropped. This reproduced in every run.

**Reproduction check:** Failed 3/3 iterations with 'Caught error: Data loader returned empty data.' (ImagePipeline.Error.dataIsEmpty): both chunks were dropped (log: scratchpad/logs/repro-data-loading-tasks-2.log).

**Refutation attempt (failed):**

I could not refute this. It is a real defect, and it can be reached through the public API with a loader that follows the DataLoading contract.

Contract. Documentation/Nuke.docc/Customization/LoadingData/loading-data.md says "`didReceiveData` and `completion` can be called on any thread". It also says to call completion once and not to call didReceiveData after it. Nothing requires the same thread or the same QoS. The repro honors every rule.

History. Commit 1ae43841 ("Remove AsyncThrowingStream usage (and overhead)", shipped in 13.0.4+) caused this regression. Before it, both callbacks called `continuation.yield` and `continuation.finish` synchronously on the calling thread, so order was always kept. Now each callback in Sources/Nuke/Tasks/TaskFetchOriginalData.swift:150-172 creates its own `Task { @ImagePipelineActor in ... }`. Each task takes its priority from the calling thread's QoS. ImagePipelineActor is a plain default actor, and a default actor runs pending jobs highest priority first. So `finishDataLoad` can run before chunks that are still queued. It clears `dataLoadContinuation`, and `dataTaskDidReceive` then drops those chunks at `guard dataLoadContinuation != nil`. Nothing in the commit message or CHANGELOG says this is intended; the entry only says "Minor other performance improvements".

Checks I ran on a copy of Sources/Nuke in the scratchpad, using only the public API (no @testable):
1. The reporter's scenario: chunks from background threads, completion from a userInteractive thread, run 20 times. 3 were OK and 17 came back as truncated data reported as success. With utility chunks and a userInitiated completion: 6 OK, 12 `.dataIsEmpty`, 2 truncated. With equal QoS, or a lower-QoS completion: 20/20 OK.
2. A realistic loader: it wraps the stock `DataLoader` (incremental delivery, local HTTP server, 400 concurrent requests) and forwards completion with `DispatchQueue.main.async`, `.global(.userInitiated)` or `.global(.userInteractive)`. It returned truncated data as success in 1 to 6 of 400 requests, plus a few `.dataIsEmpty`. The controls hop to `.global(.default)` or `.global(.utility)`, which is the same QoS as the delegate queue or lower, and got 400/400 OK. The failures come from the priority reordering, not from the server or the hop itself.
3. The stock `DataLoader` on its own is not affected. It delivers both callbacks on one serial delegate queue at the same QoS (I measured qos_class 21 for both), and 100/100 loads were OK.

This is not a test artifact or API misuse. The worst outcome is silent: truncated bytes come back as a success, and `storeDataInCacheIfNeeded` writes them to the disk cache, so the broken image persists. Impact is medium rather than high because it needs a custom DataLoading whose completion runs at a higher QoS than its chunks. Hopping the completion to the main queue is a common pattern that does this. The stock loader and the Alamofire plugin (both callbacks on one queue) are not affected.

**Suggested fix:**

Keep callback order no matter what priority each hop gets. The smallest robust fix is a lock-protected FIFO mailbox. The nonisolated `didReceiveData` and `completion` closures append `.chunk(data, response)` or `.finish(error, metrics)` to an `OSAllocatedUnfairLock<[Event]>` synchronously on the calling thread. Then each spawns `Task { @ImagePipelineActor in self?.drainEvents() }`. `drainEvents()` takes the whole array under the lock and processes it in order: `dataTaskDidReceive` for each chunk and `finishDataLoad` for the finish. The first task to run handles everything enqueued so far, so a high-priority completion task drains the earlier chunks before it finishes, and later tasks find the mailbox empty. Apply this to both branches: the diagnostics/metrics completion (lines 159-163) and the plain one (lines 168-172). The platforms are iOS 16 / macOS 13, so use OSAllocatedUnfairLock rather than Atomic.

A cheaper alternative: count delivered chunks synchronously in `didReceiveData` and capture that count in the completion. `finishDataLoad` then waits until that many chunks have been processed.

Pinning every hop to one explicit `Task(priority:)` would also restore FIFO order, but it depends on runtime details and is fragile. Add a regression test that uses a loader delivering chunks on `.background` threads and completing on `.userInteractive`. Assert that the full data is returned and the full data is stored in the data cache.

- Also reported by **concurrency-stress** (unverified): Data from a DataLoading is dropped when didReceiveData and completion come from different QoS threads

### D2. Following the documented DataLoading cancellation contract permanently takes a dataLoadingQueue slot and eventually stops all downloads

_Severity: high · user impact: medium · public API: yes · found by: data-loader, data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:148`

**Repro:** [NukeTests/data-loader--cancel-contract-deadlocks-data-loading-queue.swift](NukeTests/data-loader--cancel-contract-deadlocks-data-loading-queue.swift), [NukeTests/data-loading-tasks--cancelled-download-leaks-queue-slot.swift](NukeTests/data-loading-tasks--cancelled-download-leaks-queue-slot.swift)

**What:** loading-data.md ("The DataLoading Protocol Contract") says cancel() must ensure "neither didReceiveData nor completion are called after cancellation". TaskFetchOriginalData.loadData(with:dataLoader:) waits in withUnsafeThrowingContinuation, and only the loader's completion resumes it. Cancelling the image task cancels the TaskQueue operation's Swift Task and calls dataLoadCancellable.cancel(), but neither resumes the continuation. performDataLoad therefore never returns, and TaskQueue.execute never gives the slot back (runningCount only goes down when work() returns). The task and its TaskFetchOriginalData also leak. After 6 downloads cancelled mid-flight (the default dataLoadingQueue limit), the pipeline never downloads anything again. DataLoader only avoids this because URLSession does call completion with URLError.cancelled after cancel(), which contradicts the article; DataLoading.swift's own doc comment says completion "must be called once". The in-repo MockDataLoader follows the article's contract (a cancelled operation never calls completion). The repro includes a control, with a loader that calls completion on cancel, which passes.

**Expected:** With dataLoadingQueue maxConcurrentTaskCount = 1 and a loader that follows the documented contract: after the first download is cancelled, a second download completes.

**Actual:** The second download never starts; the wait times out after 10 s and the response is nil.

**Reproduction check:** All 3 repetitions of cancelledDownloadReleasesDataLoadingQueueSlot() failed with "TestExpectation timed out after 10.0 seconds" followed by "Expectation failed: response != nil". The control cancelledDownloadReleasesSlotWhenCompletionIsCalled() passed all 3 repetitions in about 0.013 s. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-1.log

**Refutation attempt (failed):**

I could not refute this. It is a real regression that users can reach through the public API.

1. The repro fails as described. I copied HEAD into /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-dlcancel and ran it with the NukeTests scheme on macOS. `cancelledDownloadReleasesDataLoadingQueueSlot` fails after 10.09 s with the expectation timeout and a nil response. The control, whose loader calls completion on cancel, passes in 0.011 s.

2. The mechanism is what the report says. `loadData(with:dataLoader:)` (TaskFetchOriginalData.swift:147-175) suspends in `withUnsafeThrowingContinuation`, and only `finishDataLoad` resumes it, which runs only from the loader's completion or from the `didReceiveData` error path. The `onCancelled` closure in `performDataLoad` (lines 107-113) cancels `dataLoadTask` and `dataLoadCancellable`, but it never resumes the continuation. An unsafe continuation also ignores Swift Task cancellation. `TaskQueue.execute` (Pipeline/TaskQueue.swift:129-136) only calls `operationFinished()` after `work()` returns, so the slot is never given back. The queue Task holds `self` strongly, so the TaskFetchOriginalData leaks too.

3. The docs promise the behavior the repro relies on. Documentation/Nuke.docc/Customization/LoadingData/loading-data.md, "The DataLoading Protocol Contract", says: "Return a `Cancellable` whose `cancel()` method stops the underlying task and ensures neither `didReceiveData` nor `completion` are called after cancellation." This was added in c3d01d72 on 2026-03-22. The `DataLoading` doc comment says completion "Must be called once", which is ambiguous about cancellation. The article is the more specific rule, and a user who follows it hits this bug. The in-repo MockDataLoader also skips completion when it is cancelled before its BlockOperation runs.

4. This is a regression, not intended behavior.
   - Nuke 12.x `onCancelled` called `dataTask.cancel(); finish() // Finish the operation!` and did not depend on completion.
   - Nuke 13.0.0 used an `AsyncThrowingStream` wrapper. Cancelling the queue Task ended the `for try await` loop, which released the slot, and `onTermination` cancelled the loader.
   - Commit 1ae43841 "Remove AsyncThrowingStream usage (and overhead)" (2026-04-26, first shipped in 13.0.4) replaced it with a continuation that nothing resumes on cancellation. That quietly made "completion is called after cancel" a requirement.
   - The same slot leak was already treated as a bug for the `willLoadData` path: CHANGELOG line 135, "occupying a slot in `dataLoadingQueue`".

5. It is not a test artifact and not a misuse of the API.
   - The failing path is fully public: `ImagePipeline.Configuration.dataLoader` with a custom `DataLoading`, the default `dataLoadingQueue`, and `ImageTask.cancel()`.
   - `@testable` is used only for the `Test.data` and `TestExpectation` helpers.
   - The `maxConcurrentTaskCount = 1` setting only shortens the repro. With the default of 6, six mid-flight cancellations stall all downloads, which is routine when scrolling a list.
   - `DataLoader`/URLSession and Alamofire are unaffected only because they do call completion with a cancelled error.

Impact: it only affects custom loaders that follow the documented contract, but for those users the pipeline silently stops downloading after a handful of cancellations. I rated it medium: it is reachable and severe when hit, but the most common loader stacks (URLSession, Alamofire) do not hit it.

**Suggested fix:**

In TaskFetchOriginalData.performDataLoad, resume the pending continuation from `onCancelled` after cancelling the loader, so the queue work returns whether or not the loader calls completion:

onCancelled = { [weak self] in
    guard let self else { return }
    signpost(self, "LoadImageData", .end, "Cancelled")
    self.dataLoadTask?.cancel()
    self.dataLoadCancellable?.cancel()
    self.tryToSaveResumableData()
    self.finishDataLoad(error: CancellationError()) // release the dataLoadingQueue slot
}

Why this is safe:
- `isDisposed` is already true when `onCancelled` runs (AsyncTask.terminate sets it first). So `performDataLoad` goes to `catch`, and `dataTaskDidFinish` returns right away without sending anything and without saving resumable data a second time.
- `finishDataLoad` sets `dataLoadContinuation` to nil. A later completion from URLSession or Alamofire (`URLError.cancelled`) then does nothing, so there is no double resume.
- If cancellation happens during `willLoadData`, there is no continuation yet, so the call does nothing and the existing `guard !isDisposed` handles it.
- The same fix covers the `.skipDataLoadingQueue` path, which would otherwise leak the Task and the TaskFetchOriginalData.

Also:
- Add the repro as a regression test, e.g. in ImagePipelineTests or a DataLoading-contract test.
- Make the `DataLoading.completion` doc comment agree with the article, e.g. "Must be called once, unless the returned `Cancellable` was cancelled."

- Also reported by **data-loading-tasks** (confirmed): Cancelled download leaks its dataLoadingQueue slot (and the pipeline) when the DataLoading follows the documented cancel contract

### D3. A resumed download crashes with an Int64 overflow when the 206 response advertises a Content-Length near Int64.max

_Severity: high · user impact: medium · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:216`

**Repro:** [NukeTests/data-loading-tasks--review-resumed-content-length-overflow.swift](NukeTests/data-loading-tasks--review-resumed-content-length-overflow.swift)

**What:** In `dataTask(didReceiveResponse:)`, the resumed branch computes `let expectedSize = response.expectedContentLength + resumedDataCount` with a trapping Int64 `+`. Foundation clamps any Content-Length it can't represent (for example "99999999999999999999") to Int64.max. So a server that answers a resumed request with such a 206 crashes the app with an arithmetic overflow; `maximumResponseDataSize` can't help, because the trap comes first. The same unchecked sum appears again at lines 227 (size limit), 251 (progress total) and 257 (preview guard). Related problem in the same branch: `data.reserveCapacity(Int(expectedSize))` runs before the maximumResponseDataSize check at 226-231. The comment on that check says it exists to avoid a large reserveCapacity when the server reports a size above the limit, but a resumed 206 that advertises, say, 100 GB reserves it before being rejected. Downloads that aren't resumed add 0, so only the resumed path is affected. I confirmed the diagnosis with a temporary fix: a saturating add, with the limit check moved before the reserve, makes the repro pass. That fix was reverted.

**Expected:** The resumed request fails with `ImagePipeline.Error.dataDownloadExceededMaximumSize`, since the advertised size is far above the default limit. A pipeline with no limit should fail or load without trapping.

**Actual:** The xctest process crashes ("Restarting after unexpected exit, crash"; xcresult failure "Crash: xctest") at the addition in `TaskFetchOriginalData.dataTask(didReceiveResponse:)`.

**Reproduction check:** The xctest process crashed ('Restarting after unexpected exit, crash, or test timeout'; failing test resumedResponseAdvertisingAHugeLengthFailsInsteadOfCrashing). The crash report ~/Library/Logs/DiagnosticReports/xctest-2026-09-19-091226.ips shows EXC_BREAKPOINT/SIGTRAP, 'Swift runtime failure: arithmetic overflow', at TaskFetchOriginalData.dataTask(didReceiveResponse:) TaskFetchOriginalData.swift:216, called from dataTaskDidReceive(chunk:response:) :182 (log: scratchpad/logs/repro-data-loading-tasks-11.log).

**Refutation attempt (failed):**

This is a real bug, and I could not refute it. The crash comes from Nuke's own arithmetic, not from the platform, and a user can hit it through the public API with the default DataLoader.

1. The addition traps. In `TaskFetchOriginalData.dataTask(didReceiveResponse:)` (Sources/Nuke/Tasks/TaskFetchOriginalData.swift:216), `response.expectedContentLength + resumedDataCount` is a plain Int64 `+`. The same sum appears again at :227 (size-limit check), in `dataTask(didReceiveData:)` (progress total and preview guard), and in `dataTaskDidFinish` (`stage.expectedBytes`). Nothing guards any of them. Swift traps on overflow in both -Onone and -O.

2. Foundation passes huge values through. I checked on this machine:
   - `HTTPURLResponse(headerFields: ["Content-Length": "99999999999999999999"])` reports `expectedContentLength == Int64.max`. A value like "9223372036854775000" is kept as-is.
   - I ran a real `URLSession` against a local socket server that sent a 206 with each of those Content-Lengths. It delivered the response with those values (Int64.max for the first), followed by the body bytes.
   - Nuke's `DataLoader` forwards `(data, dataTask.response)` on the first chunk, which reaches `dataTask(didReceiveResponse:)`. So the default URLSession path gets there, not only a mock.

3. The code path is on by default. `isResumableDataEnabled` defaults to true. `ResumableData` is saved after any interrupted 200/206 response that has `Accept-Ranges: bytes` and an ETag or Last-Modified. The resumed branch runs on any later 206 for the same image.

4. I reproduced the crash outside the repo. I exported HEAD to the scratchpad and added a SwiftPM test target that uses only `import Nuke` (not @testable) and a custom DataLoader:
   - First load: a 200 with 10000 of 20000 bytes, then `URLError(.networkConnectionLost)`.
   - Second load: the `Range: bytes=10000-` request gets a 206 with `Content-Length: 9223372036854775000`, which is an in-range, syntactically valid value.
   - The test process died with signal 5 (SIGTRAP) right after printing the Range header.

5. The crash is not intended behaviour. The code already guards against huge lengths (`expectedSize <= Int.max`, `expectedContentLength <= Int.max`). The comment on the limit check says it exists to avoid a large `reserveCapacity` when the server reports a content length above the limit. Commits db1b86f3 and 0ae31f20 add those guards, and nothing in them or in the CHANGELOG suggests a trap is acceptable.

6. The secondary claim also holds. On the resumed path, `reserveCapacity` runs before the `maximumResponseDataSize` check, which contradicts that comment.

Impact: medium, not high. It needs a server that sends a bogus or hostile Content-Length on a 206, after an earlier download of the same URL was interrupted and saved resumable data. Well-behaved servers never do this. But a hostile or buggy image host can crash the host app on demand: it can cut the first response itself and then send the huge 206.

**Suggested fix:**

In `dataTask(didReceiveResponse:)` (Sources/Nuke/Tasks/TaskFetchOriginalData.swift):

1. Compute the expected total once with a saturating add. When `expectedContentLength` is negative (unknown), leave the total unknown:
   ```swift
   let (sum, overflow) = response.expectedContentLength.addingReportingOverflow(resumedDataCount)
   let expectedTotal = overflow ? Int64.max : sum
   ```
2. Store it in a property such as `expectedTotalSize`. Use that property everywhere the code now adds `expectedContentLength + resumedDataCount`:
   - the `maximumResponseDataSize` check
   - the `TaskProgress` total
   - the progressive-preview guard in `dataTask(didReceiveData:)`
   - `stage.expectedBytes` in `dataTaskDidFinish`
3. Move the `maximumResponseDataSize` check ahead of the resumed-branch `data.reserveCapacity(Int(expectedSize))`, so an oversized 206 is rejected before any reserve.
4. Add a regression test: a resumed 206 with `Content-Length: 99999999999999999999` should fail with `.dataDownloadExceededMaximumSize`. With `maximumResponseDataSize = nil`, the load should complete or fail without trapping.


### D4. A player joining frames that are already decoded never displays the frame it is on

_Severity: medium · user impact: medium · public API: yes · found by: animated-frames-view, animated-playback_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:137`

**Repro:** [NukeUITests/animated-frames-view--joining-player-shows-no-frame.swift](NukeUITests/animated-frames-view--joining-player-shows-no-frame.swift), [NukeUITests/animated-playback--joining-player-never-shows-decoded-first-frame.swift](NukeUITests/animated-playback--joining-player-never-shows-decoded-first-frame.swift)

**What:** display(frameAt:) is only reached from seek, tick and frameDidDecode. The store calls frameDidDecode only for frames decoded while the player was waiting for them. A player that joins a store which already holds the frame at currentFrameIndex is never offered that frame. This happens when another view of the same animation played it, or when a reused cell gets a new player for a cached animation. store.add finds nothing pending and schedules nothing, so the frame is never shown. A playing view stays blank (or shows the poster) until the first tick moves to the NEXT frame, so the frame it joined on is skipped. A view with isPlaybackEnabled = false and no poster stays blank forever. That includes SwiftUI with Auto-Play Animated Images turned off.

**Expected:** player.image is the frame at currentFrameIndex once that frame is in memory. The docs say "The image of the current frame, or nil until the first frame is decoded" and, for playback disabled, "The first frame is displayed".

**Actual:** second.image == nil even though second.isFrameBuffered(currentFrameIndex) is true. An AnimatedImageView with isPlaybackEnabled = false shows nothing.

**Reproduction check:** macOS, 3 of 3 iterations: `second.image != nil` failed while `second.isFrameBuffered(second.currentFrameIndex)` passed. `view.image != nil` failed for an AnimatedImageView with isPlaybackEnabled = false that joined a store another player had already filled. The same two assertions failed on a private iOS 26.5 simulator.

**Refutation attempt (failed):**

I could not refute this. The defect is real and reproduces through public API.

Code path (Sources/NukeUI/AnimatedImages):
- `AnimatedImagePlayer.init` (AnimatedImagePlayer.swift:137-145) sets `currentFrameIndex` to `store.leadingIndex() ?? 0`, then calls `store.add(self)` and `pool.rebalance()`. It never calls `display(frameAt:)`.
- `AnimatedImageFrameStore.add` (AnimatedImageFrameStore.swift:173-179) only calls `scheduleDecodeIfNeeded()`. When the frames the new player wants are already in `frames`, `nextNeededIndex` returns nil. No decode is scheduled, and `storeDidDecodeFrame`/`frameDidDecode` never reach the new player.
- `display(frameAt:)` has only three callers: `seek`, `tick` and `frameDidDecode`. So a player that joins a store already holding its current frame leaves `image == nil`.
- In `tick`, the guard `displayedFrameIndex == currentFrameIndex || !store.isPending(currentFrameIndex)` passes because the frame is not pending. Elapsed time is then charged against a frame that was never shown. The comment right above it says "Time counts only against a frame that is on screen", so this contradicts the stated intent. After the delay the playhead moves to k+1 and the joined frame k is skipped.

I ran it in an isolated copy of the tree in the scratchpad (macOS, xcodebuild, NukeUI scheme). Both writer tests fail as claimed. I added two probes:
- (a) A playing player joins at leading index 2. It shows nothing at join or after 50 ms. At 110 ms the first frame it shows is 3 (`shown=[3]`), so frame 2 is skipped.
- (b) Public API only: `AnimatedImagePlayer(source:)` created twice on the shared pool. After 300 ms the second player still has `image == nil` and `onFrame` has fired 0 times.

This is not intended, and the docs promise otherwise:
- `image` is documented as "nil until the first frame is decoded".
- AnimatedImages.md:94 says that with `isPlaybackEnabled = false` "The first frame is displayed".
- AnimatedImages.md:136 presents "a cell that scrolls off screen and comes back finds them still in memory" as the purpose of sharing. It was added in commit 0a2ab073 "Share the decoded frames between every player of an animation", which gives the same scroll-back reason.
- `AnimatedImageView.player.didSet` and `AnimatedImageModel.setPlayer` both read `player.image` to show a joined player's frame, so the author expected it to be set.
- The existing test `aSecondPlayerFindsTheFramesTheFirstDecoded` checks buffered and decoded counts but never `second.image`, which is why this was missed.

What mitigates it:
- LazyImage, LazyImageView and `loadImage(into:)` all pass the decoder's still as a poster, and it covers the gap. On those paths the only visible symptom is when a view joins a copy that is already playing at frame k: the poster (frame 0) shows for delay[k], then frame k+1 appears, a brief wrong-frame flash.
- On paths with no poster, the view is blank for one frame's delay each time a cell comes back while playing. It is blank forever while held still: `AnimatedImage(source)` with Auto-Play Animated Images off, `AnimatedImageView.animatedImage = source` with `isPlaybackEnabled = false`, or a player you own that is never played.
- It only happens when the same `AnimatedImageSource` instance was already decoded by another player. That is common: ImageCache hands out the same instance, and so does an app that keeps sources in its model.
- The feature is unreleased (CHANGELOG top section, #958).

Overall impact: medium.

**Suggested fix:**

Show the frame a player joins on as soon as it is in memory.

(1) At the end of `AnimatedImagePlayer.init`, after `store.add(self)` and `pool.rebalance()`, add:
`if store.frame(at: currentFrameIndex) != nil { display(frameAt: currentFrameIndex) }`
Guard it on the frame being present so `bufferMissCount` is not bumped. This sets `image`, which `AnimatedImageView.player.didSet` and `AnimatedImageModel.setPlayer` already read. That fixes the held-still case and the SwiftUI Auto-Play-off case.

(2) Make `tick` stop charging time to a frame that was never shown. Before the `isPending` guard, add:
`if displayedFrameIndex != currentFrameIndex, store.frame(at: currentFrameIndex) != nil { display(frameAt: currentFrameIndex); return }`
The joined frame then gets its whole delay, and an `onFrame` handler set after init still receives it.

Add a regression test to AnimatedImageFrameSharingTests: a second player joining decoded frames has `image != nil`, and a playing joiner's first `onFrame` is its `currentFrameIndex`.

- Also reported by **animated-playback** (confirmed): A player joining already-decoded frames never displays the frame it starts on

### D5. SwiftUI AnimatedImage shows the previous animation's frame instead of the new poster after reconfiguration

_Severity: medium · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImage.swift:219`

**Repro:** [NukeUITests/animated-frames-view--swiftui-stale-frame-on-switch.swift](NukeUITests/animated-frames-view--swiftui-stale-frame-on-switch.swift)

**What:** AnimatedImageRepresentable.update(_:) applies the poster only when view.player?.image == nil, and it checks this before switching the view to the new animation or player. view.player is therefore still the old player, whose image is the frame on screen, so the new poster is skipped. The new player has no image yet, and AnimatedImageView.player.didSet only replaces the image when the new player has one. The old animation's frame, which is a different picture, stays on screen until the new first frame is decoded. On UIKit the new player also takes the old frame's scale instead of the new poster's. The UIKit display(_:) path does this in the right order.

**Expected:** After the update the view shows the new poster ("the still frame to show until the first frame of the animation is decoded").

**Actual:** view.image is still the last frame of the previous animation. view.image === newPoster is false.

**Reproduction check:** macOS, 3 of 3 iterations: after host.update(new) with view.player === new and new.image == nil (both assertions passed), `view.image !== old.image` and `view.image === newPoster` failed. The view still showed the old player's frame. Same result on the iOS simulator.

**Refutation attempt (failed):**

I could not refute this. It is a real ordering bug, and a user can reach it through the public API. The effect is temporary, though. The repro's gated decoder makes it look permanent.

Code (Sources/NukeUI/AnimatedImages/AnimatedImage.swift:216-227): `update(_:)` checks `if let poster, view.player?.image == nil` before it assigns the new `player` or `source`. At that point `view.player` is still the old player, which has a frame, so the new poster is skipped. `AnimatedImageView.player.didSet` only sets an image when the new player already has one. The old animation's frame therefore stays on screen until the new first frame is decoded.

The other two renderers do this correctly:
- `AnimatedImageView.display(_:)` sets the animation first and applies the poster only after that.
- The watchOS renderer shows `model.image ?? poster`, and `setPlayer` resets `model.image` to the new player's image (nil), so the new poster shows.

Nothing documents this as intended. History: the check came in with 93cc9063 ("Show the still image until the first frame is decoded"). The comment "only while there is no frame to cover" is meant to stop a poster flash on the same animation, not to keep a different animation's frame on screen. The `AnimatedImage.init(_:poster:)` docs promise the poster is "the still frame to show until the first frame of the animation is decoded". The code already expects this view to be reused with new content: the `update` doc says SwiftUI reuses the view, and the watchOS `onChange` comment says the same. There is also an existing test, `playsTheNewAnimationWhenItIsReconfigured`.

Reachable without the repro's @testable helpers:
- `AnimatedImage(_:poster:)`, `AnimatedImage(player:poster:)` or `AnimatedImage(container:)` given new inputs while its identity stays the same.
- LazyImage's default content when the URL changes to an animated image already in the memory cache. `FetchImage.load` sets `imageContainer` directly "to avoid a nil flicker", so the same `AnimatedImage` is reconfigured instead of recreated.

Verified: I exported commit d9eb6690 to the scratchpad (the repo was not touched) and ran the tests with `xcodebuild` on macOS.
- The agent's repro fails as described.
- My own variant uses only the public `AnimatedImage(source, poster:)` and real decoders. Right after the update, `newPlayerImageNil=true showsOldFrame=true showsNewPoster=false`. The new first frame replaced the old one a few milliseconds later.
- With the fix below, both tests pass, and so do 112 tests across AnimatedImageRepresentableTests, AnimatedImageViewTests, LazyImageTests, AnimatedImageIntegrationTests and AnimatedImageLayoutTests (`showsNewPoster=true`).

Why the impact is low:
- Normally the wrong picture stays up only for as long as the new first frame takes to decode. That is milliseconds for small GIFs, and longer for large animations or when a feed has many decodes queued.
- It only stays up indefinitely if the new animation never produces a frame, which the gated decoder simulates.
- The UIKit scale point (the new player takes its scale from the old frame) has little visible effect in SwiftUI. The view is aspect-fit, and `sizeThatFits` uses `poster.scale` or `player.options.scale`.

**Suggested fix:**

In `AnimatedImageRepresentable.update(_:)` (Sources/NukeUI/AnimatedImages/AnimatedImage.swift:219), decide whether the input is a new animation before the switch. Apply the poster when it is new, or when the current player has no frame:

```swift
let isNewAnimation = player.map { view.player !== $0 } ?? (view.animatedImage !== source)
if let poster, isNewAnimation || view.player?.image == nil {
    // Not `image`, which would stop the animation.
    view.setImageKeepingAnimation(poster)
}
```

The poster is still set before `view.player` / `view.animatedImage` is assigned, so the scale is still read from the poster. If the new player already has a frame, `player.didSet` replaces the poster in the same turn, so it never flashes. `view.animatedImage` keeps reporting the same source when the view rebuilds its own player for downsampling, so reconfiguring with the same animation still does not flash the poster.

Add a regression test to AnimatedImageRepresentableTests: reconfigure `AnimatedImage(source, poster:)` with a different source and poster, then check that `view.image === newPoster` right after the update. The existing `playsTheNewAnimationWhenItIsReconfigured` test is the pattern to follow.


### D6. seek(toFrame:) / restart() called from onLoop are silently undone

_Severity: medium · user impact: low · public API: yes · found by: animated-playback_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:422`

**Repro:** [NukeUITests/animated-playback--seek-or-restart-from-onloop-undone.swift](NukeUITests/animated-playback--seek-or-restart-from-onloop-undone.swift)

**What:**

`advance(to:)` calls `onLoop?(completedLoopCount)` before it assigns `currentFrameIndex = index`, and `tick(_:)` then overwrites `elapsed` and displays `currentFrameIndex` once the handler returns. `finish()` (line 432) also calls `onLoop` before it sets `isFinished` and `isPlaying` and pauses the clock. So public playback calls made from the player's own `onLoop` callback are undone.

**Seek from `onLoop`.** A handler like "skip the intro on later loops" calls `seek(toFrame: 2)`. That frame is shown through `onFrame`, then the player snaps back to frame 0 and carries on from there.

**Restart from `onLoop` on the last loop.** `restart()` resets the loop count and seeks to 0. Its `play()` does nothing because `isPlaying` is still true, and `finish()` then marks the player finished.

**Expected:** After the wrap, `currentFrameIndex == 2`. After `restart()` in the final `onLoop`: `isFinished == false`, `isPlaying == true`, frame 0, loop count 0.

**Actual:** After the wrap, `currentFrameIndex == 0`. After `restart()`: `isFinished == true`, `isPlaying == false`, `currentFrameIndex == 0`, `completedLoopCount == 0`. That is an inconsistent finished state: a player that has "played all its loops" has completed none and is on its first frame rather than its last.

**Reproduction check:** All 3 iterations failed in the same way. seekFromOnLoopIsHonored: `player.currentFrameIndex == 2` failed because currentFrameIndex was 0. restartFromOnLoopOnTheLastLoopIsHonored: `player.isFinished == false` failed (isFinished was true) and `player.isPlaying` failed (isPlaying was false). The currentFrameIndex == 0 and completedLoopCount == 0 checks passed, so the player ends in the inconsistent finished state the report describes. A diagnostic run that recorded onFrame showed the frames [0, 1, 2, 3, 2, 0]: frame 2 is displayed by the seek and then immediately replaced by frame 0. Log: scratchpad/logs/repro-animated-playback-1.log (diagnostic: repro-animated-playback-1-diag.log).

**Refutation attempt (failed):**

I could not refute this. It reproduces through public API and breaks a documented invariant.

Reproduced: I ran the repro in a scratchpad clone of HEAD 2c2b23f6 on macOS with xcodebuild. The clone was needed because committed LazyImageTests.swift does not compile on the Xcode 27 SDK ("ambiguous use of 'Color'"), so I copied in the working-tree version. Both tests fail as claimed: `currentFrameIndex == 2`, `isFinished == false` and `isPlaying` are all false. Clone: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-onloop.

Mechanism, confirmed in Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:
- `advance(to:)` (line 422) calls `onLoop` before it sets `currentFrameIndex = index`.
- `tick(_:)` then overwrites `elapsed` (line 401) and calls `display(frameAt: currentFrameIndex)` (line 407).
- `frameDidDecode(at:)` (lines 480-483) goes through the same `advance`, sets `elapsed = 0`, then displays the index it was given. So a seek from `onLoop` is also undone when the wrap comes from a late-decoded frame.
- `finish()` (line 432) calls `onLoop` before it sets `isFinished`, `isPlaying` and `clock.isPaused`. So a `restart()` from there leaves the player finished and paused on frame 0 with `completedLoopCount == 0`.

The "is finished" doc (line 55) says it "has played the number of loops it was asked to and stopped on its last frame", so this end state violates it. After that, `play()` does nothing because `isFinished` is true, and the animation stays frozen on frame 0.

Why it isn't refuted:
- `onLoop`, `seek(toFrame:)` and `restart()` are all public and all run on the main actor, so there is no actor misuse.
- The test's ManualClock drives the same `tick` path as the production clock's `onTick`. The internal init is only used to inject the clock, so this is not a test-harness artifact.
- ImageIO and UIKit play no part.
- Nothing in the doc comments, Documentation/NukeUI.docc/AnimatedImages.md, CHANGELOG or commit messages says callbacks must not re-enter playback control. The author's intent actually leans the other way: commit bff0f649 is titled "Keep a late frame from undoing a seek".

Why impact is low:
- The API is unreleased (Nuke 14 WIP, PR #958). Nothing in Sources or Demo uses `onLoop`; the only use is one test that records loop counts.
- The restart case has a natural working alternative. `restart()` from `onFinish` works, because `onFinish` runs after the state is final.
- The seek case ("skip the intro on later loops") is plausible but niche. It can be worked around by deferring the seek (e.g. `Task { @MainActor in ... }`) or seeking from `onFrame`.

Minor side effect: in the seek case, frame 2 is displayed and then replaced by frame 0 in the same main-thread turn, so `onFrame` fires twice.

**Suggested fix:**

Fire the callbacks only once the player's state is final, so that playback calls made from inside them win.

1. Make `advance(to:)` a pure state change. It sets `currentFrameIndex = index` and `isWaitingForNextFrame = false`, increments `completedLoopCount` when `index == 0`, and returns whether it wrapped. It no longer calls `onLoop`.

2. In `tick(_:)`, set `var didLoop = false` and set it from `advance`'s result. After `store.didUpdateWindow(...)` and `display(frameAt: currentFrameIndex)`, call `if didLoop { onLoop?(completedLoopCount) }`. Do the same in `frameDidDecode(at:)`: call `onLoop` after `display(frameAt: index)`. If `onLoop` then calls `seek` or `pause`, nothing overwrites it.

3. Reorder `finish()`:
```swift
completedLoopCount += 1
isFinished = true
isPlaying = false
clock.isPaused = true
onLoop?(completedLoopCount)
guard isFinished else { return } // the handler restarted or seeked
onFinish?()
```
Now `restart()` from `onLoop` calls `seek`, which clears `isFinished`, and then `play()`, which works because `isPlaying` is already false. `onFinish` is skipped because the player did not finish. `tick` already `break`s after `finish()` and returns with `advanced == false`, so it does not touch the restarted state.

Add regression tests for both scenarios in the repro:
- after a seek from `onLoop` at the wrap, `currentFrameIndex == 2` and playback continues from 2;
- after `restart()` from the final `onLoop`: `isPlaying`, `!isFinished`, frame 0, loop count 0, and `onFinish` is not called.

Also add one test where `pause()` is called from `onLoop`.


### D7. removeData(for:) deletes the whole cache folder, or the folder above it, when the filename generator returns "" or ".."

_Severity: medium · user impact: low · public API: yes · found by: data-cache_

**Where:** `Sources/Nuke/Caching/DataCache.swift:318`

**Repro:** [NukeTests/data-cache--filename-escapes-directory.swift](NukeTests/data-cache--filename-escapes-directory.swift)

**What:**

`url(for:)` appends whatever the filename generator returns to `path` and never checks that the result names a file inside the cache folder. `appendingPathComponent("")` returns `path` itself and `appendingPathComponent("..")` returns its parent. As a result:
- `containsData(for:)` reports an entry that was never stored.
- `removeData(for:)` reaches `FileManager.removeItem(at:)` at line 483 and deletes the entire cache folder (for "") or its parent (for ".."). For `DataCache(name:)`, the parent is the app's whole Caches directory.

The default generator guards against the empty key, but a custom generator that keeps filenames readable does not: the identity `{ $0 }` (Nuke's own tests use it) or percent-encoding both map "" to "". The pipeline produces the empty key by itself: `makeDataCacheKey(for:)` returns "" for `ImageRequest(url: nil)`. So `pipeline.cache.removeCachedImage(for: ImageRequest(url: nil))` wipes the disk cache. The repro confirms this with a percent-encoding generator.

**Expected:** A generated filename that doesn't name a file inside the cache folder ("", ".", "..", or anything that resolves outside `path`) is treated like nil: no entry and nothing to remove.

**Actual:** `containsData(for: "")` returns true. `removeData(for: "")` followed by `flush()` deletes every entry. `removeData(for: "..")` deletes the folder that contains the cache folder, including sibling files. `removeCachedImage(for: ImageRequest(url: nil))` erases a previously stored entry.

**Reproduction check:** All 3 tests failed in each of the 3 iterations: 15 issues, 5 per iteration. (1) `!cache.containsData(for: "")` is false, and after `removeData(for: "")` + `flush()`, `cache["a"]` is nil because the cache folder is gone. (2) `!cache.containsData(for: "..")` is false, and after `removeData(for: "..")` + `flush()` the sibling file next to the cache folder no longer exists. (3) With a percent-encoding generator, `pipeline.cache.removeCachedImage(for: ImageRequest(url: nil))` + `flush()` makes `cachedData(for: request)` nil for an entry that was stored earlier. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-cache-1.log

**Refutation attempt (failed):**

I could not refute it. I reproduced it using only the public API, with no @testable import: I copied Sources/Nuke into a scratch package at scratchpad/refute-datacache and built a small executable.

What the run showed:
- **Default SHA1 generator:** safe. `url(for: "")` is nil, `containsData(for: "")` is false, and removing "" leaves the other entries alone. `filename(for:)` has mapped "" to nil on purpose since before commit f8665ab2, and the "Invalid Keys" tests in DataCacheTests only cover this default generator.
- **Percent-encoding generator with the pipeline:** `makeDataCacheKey(for: ImageRequest(url: nil))` returns "". `containsCachedImage(for: ImageRequest(url: nil))` returns true, and `removeCachedImage(for: ImageRequest(url: nil))` followed by `flush()` deletes the whole cache folder (`fileExists(path)` is false afterwards). The folder does come back on the next write through the `fileNoSuchFile` path in `perform(_:)`.
- **Identity generator `{ $0 }` with key "..":** `containsData` returns true, and `removeData` plus `flush()` deletes the parent folder and a sibling file in it.
- **Other generators:** a `lastPathComponent`-style generator returns "/" for "https://example.com/", which also resolves to the cache folder.

Why I don't dismiss it as API misuse:
- Nothing documents that a custom `FilenameGenerator` has to reject "" or "..". The doc comment only says it "generates a filename" and suggests SHA1.
- Nuke produces the "" key itself from a public, non-optional path: `ImageRequest(url: URL?)`, and the documented `cacheKey` delegate example returns `request.imageID`, which falls back to the default key when it is nil.
- `url(for:)` is shown in the docs as the way to "Access file directly", and here it hands back the folder itself.
- A library that calls `FileManager.removeItem` on a path it built should check that the path stays inside its own folder. This is Nuke's own code, not a platform behavior.

Why the impact is low:
- The default generator is immune, so only users with a custom generator can hit it.
- No automatic pipeline path triggers it. It takes an explicit `removeCachedImage`/`removeCachedData` for a request with no URL, no processors and no thumbnail, or a direct `removeData` with a key that maps to ""/"."/".."/"/".
- In the "" case the damage is the same as `removeAll()` (the cache is wiped and later rebuilt). Deleting the parent folder, such as the app's Caches directory for `DataCache(name:)`, needs a generator that maps a key to "..", which pipeline keys don't produce in practice.
- Side effect: `containsCachedImage` wrongly returns true for requests with no URL.

**Suggested fix:**

In `DataCache.url(for:)` (Sources/Nuke/Caching/DataCache.swift:318), treat a generated name that is not a single path component the same as nil. Every read, write, touch and remove goes through this method, so this one guard covers all of them:

```swift
public func url(for key: String) -> URL? {
    guard let filename = filename(for: key),
          !filename.isEmpty, filename != ".", filename != "..",
          !filename.contains("/"), !filename.contains("\0") else { return nil }
    return path.appendingPathComponent(filename, isDirectory: false)
}
```

Rejecting "/" breaks nothing that works today: nested names already fail to write, because only `path` is re-created. Optionally, `ImagePipeline.Cache` could also skip disk-cache operations when `makeDataCacheKey` returns "", which also covers custom `DataCaching` implementations. Add a doc line on `FilenameGenerator` saying it gets empty keys and should return nil for keys it can't map. Regression tests: with the `{ $0 }` and percent-encoding generators, `containsData(for: "")` and `containsData(for: "..")` are false, and `removeData` for those keys followed by `flush()` leaves the existing entries and any sibling files in place.


### D8. Replacing DataLoader.delegate while loads are running crashes (unsynchronized write to _DataLoader.delegate)

_Severity: medium · user impact: low · public API: yes · known: defects.md #41 · found by: data-loader_

**Where:** `Sources/Nuke/Loading/DataLoader.swift:39`

**Repro:** [NukeTests/data-loader--delegate-setter-data-race.swift](NukeTests/data-loader--delegate-setter-data-race.swift)

**What:** `delegate { didSet { impl.delegate = delegate } }` writes a plain stored var. Every URLSession callback in _DataLoader reads it, on the delegate queue, and urlSession(_:didCreateTask:) reads it synchronously on whatever thread calls loadData. DataLoader is @unchecked Sendable, so the compiler doesn't flag this. Setting the delegate while loads are running (for example, the documented Pulse snippet run from a debug menu) races with those reads, and a read can retain an object that's already been freed. #928 fixed the same pattern on prefersIncrementalDelivery by putting it behind a lock.

**Expected:** The delegate can be replaced at any time without a crash or a data race.

**Actual:** Without any sanitizer, the repro test crashes the test process ("Crash: xctest"). A standalone binary that does the same crashes on every run with EXC_BAD_ACCESS (SIGSEGV) in objc_retain, called from _DataLoader.urlSession(_:didCreateTask:) ← DataLoader.loadData(with:collectsMetrics:didReceiveData:completion:). With -enableThreadSanitizer YES, TSan reports a data race: the read is in _DataLoader.urlSession(_:didCreateTask:) and the previous write is in DataLoader.delegate.didset.

**Reproduction check:** Without a sanitizer, the test process crashed in 3 of 3 separate xcodebuild runs (xcresult failure "Crash: xctest", followed by "Restarting after unexpected exit, crash"). Each crash was on the first repetition, so -test-iterations 3 ran only one repetition per invocation. CrashReporter was rate-limited, so there is no symbolicated stack for the crash itself. With -enableThreadSanitizer YES, TSan reports "data race": a read in _DataLoader.urlSession(_:didCreateTask:), called from CFNetwork's didCreateTask inside DataLoader.loadData on the caller's thread, and a previous write in DataLoader.delegate.didset. Logs: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-2.log (and 2b, 2c), plus repro-data-loader-2-tsan.log

**Refutation attempt (failed):**

The claim holds. In /Users/kean/Developer/Nuke/Sources/Nuke/Loading/DataLoader.swift, `public var delegate` (line 38) has `didSet { impl.delegate = delegate }`, and it writes `_DataLoader.delegate` (line 168), which is a plain stored `var` with no lock. That field is read in two places: on the session's delegate OperationQueue by every forwarding callback, and synchronously in `urlSession(_:didCreateTask:)` (line 193). URLSession calls that one inside `session.dataTask(with:)`, so it runs on whatever thread called `loadData`. `DataLoader` is declared `@unchecked Sendable`, which tells users its public API is thread-safe, and so the compiler never flags the race.

Nothing documents this as intended. The doc comment, loading-data.md and getting-started.md all show the Pulse one-liner and never say the delegate must be set before the first load. The CHANGELOG, commit eadcd576 and the blame history say nothing about it either.

The maintainer has also fixed this exact pattern on the same class. Commit b6bc5b3c / #928 ("Fix a data race on `DataLoader/prefersIncrementalDelivery`") moved that property into an OSAllocatedUnfairLock. Its note says the value "is read when each task is created, which can happen on any thread, so the access is synchronized". The same release fixed the same kind of race in #901 (isSignpostLoggingEnabled), #925 (DataCache config) and #929 (ImagePrefetcher.didComplete). The repro copies the #928 regression test, so it follows an accepted testing pattern rather than misusing the API.

It is not a mock artifact. I copied DataLoader.swift unchanged into a standalone binary with small stubs for the protocols. One thread kept replacing `delegate` while 2000 `loadData` calls ran on GCD. It crashed on 3 of 3 runs (exit 139 SIGSEGV and exit 133). The same binary with only `_DataLoader.delegate` moved behind `OSAllocatedUnfairLock` finished 3 of 3 runs without crashing.

User impact is low in practice. Most apps set the delegate once at launch, before any loads, and that is safe. A single toggle from a debug menu during loading has only a tiny window in which to hit the freed-object read. Still, it is a real memory-safety race that uses only the public API and the documented snippet, and TSan will flag it.

**Suggested fix:** Follow the #928 approach. In `_DataLoader`, replace `var delegate: URLSessionDelegate?` with `private let _delegate = OSAllocatedUnfairLock<URLSessionDelegate?>(uncheckedState: nil)` plus a computed `var delegate: URLSessionDelegate? { get { _delegate.withLockUnchecked { $0 } } set { _delegate.withLockUnchecked { $0 = newValue } } }`. In each callback, read it once into a local (`let delegate = self.delegate`). In `DataLoader`, make `public var delegate` a computed property that forwards to `impl.delegate` (`get { impl.delegate } set { impl.delegate = newValue }`) instead of a stored var with `didSet`, so that concurrent writers don't race on the outer storage either. Add a note to the doc comment like the one on prefersIncrementalDelivery, a CHANGELOG line "Fix a data race on `DataLoader/delegate`", and a regression test modeled on `prefersIncrementalDeliveryIsToggledWhileLoadingData`.


### D9. DataLoader.delegate never receives the session-level authentication challenge, so certificate pinning implemented there is silently skipped

_Severity: medium · user impact: medium · public API: yes · found by: data-loader_

**Where:** `Sources/Nuke/Loading/DataLoader.swift:245`

**Repro:** [NukeTests/data-loader--session-level-challenge-not-forwarded.swift](NukeTests/data-loader--session-level-challenge-not-forwarded.swift)

**What:** _DataLoader implements only the task-level urlSession(_:task:didReceive:completionHandler:), and forwards it only to the user delegate's task-level method. Because _DataLoader doesn't implement the session-level method, URLSession sends server-trust challenges to the task-level one. A user delegate that implements only urlSession(_:didReceive:completionHandler:) never hears about them, and the loader falls back to .performDefaultHandling. That session-level method is the only challenge method on URLSessionDelegate, which is the type of DataLoader.delegate, and it's the usual place to pin certificates. The docs say the delegate can be used for "handling authentication challenges", and the Nuke 11 CHANGELOG says the delegate "now gets called for all URLSession/delegate methods". The repro includes a control: the same delegate on a plain URLSession is asked about the challenge and cancels the load, and that test passes.

**Expected:** A delegate implementing only the session-level challenge method is asked about a server-trust challenge. It rejects it, and the load fails with URLError.cancelled.

**Actual:** The delegate is never called (challengeCount == 0). The challenge gets default handling and the load succeeds with the body.

**Reproduction check:** All 3 repetitions of sessionLevelChallengeReachesDataLoaderDelegate() failed. delegate.challengeCount is 0 (expected 1), outcome.errorCode is nil (expected .cancelled), and outcome.body is 7 bytes ("trusted"). The control sessionLevelChallengeReachesPlainURLSessionDelegate() passed all 3 repetitions. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-3.log

**Refutation attempt (failed):**

I could not refute this. It reproduces through public API only, and the routing is Nuke's, not URLSession's.

Reproduction: I copied Sources/Nuke into a scratch package and changed the repro's `@testable import` to a plain `import`, because it only uses public DataLoader API (init(configuration:), delegate, loadData(with:didReceiveData:completion:)). The DataLoader test fails with challengeCount 0, errorCode nil and a 7-byte body. The control test on a plain URLSession passes. The repo was not modified.

Why it happens: URLSession sends session-wide challenges (ServerTrust, ClientCertificate, NTLM, Negotiate) to the session delegate's `urlSession(_:didReceive:completionHandler:)`. It uses the task-level method only when the session delegate doesn't implement that one, and Apple documents this routing. `_DataLoader` implements only the task-level method (Sources/Nuke/Loading/DataLoader.swift:245). It forwards only to `(delegate as? URLSessionTaskDelegate)?.urlSession?(_:task:didReceive:...)` and otherwise calls `.performDefaultHandling`. So a user delegate that implements only the session-level method is never asked. The control test shows the URLProtocol-driven challenge takes the same routing as real TLS, so this is not a mock artifact.

Intent and promises: commit e6d27fe7 ("Extend a set of method when URLSession delegate is called", Nuke 11.5) added the task-level forwarders and never mentions the session-level method. Nothing documents it as deliberately left out. Against the claim, the DocC page (Customization/LoadingData/loading-data.md) shows the task-level method on a `URLSessionTaskDelegate`, and that documented path works; my extra test confirmed a task-level delegate is asked and the load cancels. For the claim:
- The CHANGELOG says the delegate "now gets called for all URLSession/delegate methods … e.g. for handling authentication challenges".
- The property doc also mentions "handling authentication challenges".
- `DataLoader.delegate` is typed `URLSessionDelegate?`, and that protocol's only challenge method is the session-level one. It is also where Apple's manual server-trust sample puts the check.

Consequence: a user reusing a standard pinning delegate gets no error or warning. Pinning is skipped and the system's default trust check still runs. There is no worse MITM exposure than the defaults, but the pinning the user set up silently does nothing.

Impact is medium: it's silent and bypasses a security feature, but it only hits delegates that implement the session-level method alone, and the documented example is not affected.

**Suggested fix:**

In `_DataLoader.urlSession(_:task:didReceive:completionHandler:)` (Sources/Nuke/Loading/DataLoader.swift:245), copy URLSession's own routing:
- If the delegate responds to the task-level selector, forward to it.
- Otherwise, if the challenge's authenticationMethod is ServerTrust, ClientCertificate, NTLM or Negotiate and the delegate responds to `#selector(URLSessionDelegate.urlSession(_:didReceive:completionHandler:))`, call `delegate.urlSession?(session, didReceive: challenge, completionHandler:)`.
- Otherwise, call `completionHandler(.performDefaultHandling, nil)`.

I checked this in a scratch copy: the repro passes, and the documented task-level delegate still works.

Do NOT implement the session-level method on `_DataLoader` itself. URLSession would then stop sending session-wide challenges to the task-level method, which breaks delegates written the documented way.

Also add a DataLoaderTests case for each of the two delegate shapes.


### D10. data(for:) / disk-cache prefetch never reads back the original data it stored for thumbnail or processed requests

_Severity: medium · user impact: medium · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskLoadData.swift:10`

**Repro:** [NukeTests/data-loading-tasks--data-task-never-reads-back-original-data.swift](NukeTests/data-loading-tasks--data-task-never-reads-back-original-data.swift)

**What:** `TaskLoadData.start()` looks up the disk cache with the full request key: URL plus thumbnail ID, or URL plus processor IDs. On a miss it fetches the original data with `request.withProcessors([])`, and `storeDataInCacheIfNeeded` stores it under the sanitized key (plain URL). The next identical request misses again and downloads again. `TaskLoadImage.start()` handles this case for thumbnails with a second lookup (`request.withoutThumbnail()`); `TaskLoadData` doesn't, and `TaskFetchOriginalData` never reads the cache. This also affects `ImagePrefetcher` with the `.diskCache` destination, which uses the same data tasks: re-prefetching thumbnails downloads them again every time.

**Expected:** The second identical `data(for:)` call (thumbnail request, or a processed request under the default `.storeOriginalData`) is served from the disk cache the first call filled, so there is 1 download.

**Actual:** 2 downloads (`createdTaskCount == 2`) in all three repro cases, even though `dataCache.store[url]` holds the data.

**Reproduction check:** All 3 tests (thumbnail data(for:), processed data(for:), prefetch-to-disk data task) failed 3/3 iterations with dataLoader.createdTaskCount → 2. In all 3 the check that dataCache.store[url] held the data after the first call passed (log: scratchpad/logs/repro-data-loading-tasks-3.log).

**Refutation attempt (failed):**

This is a real bug. The code, the project history and a public-API reproduction all confirm it.

The read key and the write key disagree. `TaskLoadData.start()` (Sources/Nuke/Tasks/TaskLoadData.swift:10) reads only the full key from `makeDataCacheKey`: imageID + thumbnail id + processor ids. On a miss it fetches with `request.withProcessors([])`. `storeDataInCacheIfNeeded` (TaskFetchOriginalData.swift, `makeSanitizedRequest`) removes both processors and thumbnail, then stores under the plain URL key. Nothing in the data path reads that key back, and `TaskFetchOriginalData` never reads the disk cache at all.

The history shows the maintainer treats this as a bug:
- CHANGELOG, fix for #705: original data is "now stored without a thumbnail key".
- CHANGELOG, fix for #837 (commit 67fbf4ed): "Fix thumbnail requests re-downloading original image data when it is already stored in the disk cache". That commit added the `withoutThumbnail()` fallback, but only to `TaskLoadImage`. `TaskLoadData` was not touched.
- For processed requests, `TaskLoadImage` still reaches the original data by recursing through `dropLast()` processors. `TaskLoadData` has no equivalent path.
- Nothing documents that `data(for:)` or the `.diskCache` prefetcher should skip the disk cache for these requests. `ImagePrefetcher.Destination.diskCache` only warns about `.automatic` with processors and about `.storeEncodedImages`. The default `.storeOriginalData` is the supported case, and it is the one that fails.

It is not a test artifact. I copied HEAD into the scratchpad, added a SwiftPM test target and ran:
- The 3 original repro tests: all fail with `createdTaskCount == 2`.
- A public-API-only test: `ImagePrefetcher(pipeline:, destination: .diskCache)` prefetches a thumbnail request twice, waiting for `didComplete` each time. It downloads twice, although `dataCache.store[url]` already holds the data.
- `data(for: thumbnailRequest)` after `image(for: plainRequest)` also downloads again.
- `.storeAll` with a processed `data(for:)` downloads twice.
- A correctness failure, not just wasted work: `data(for:)` on a thumbnail request with `.returnCacheDataDontLoad` throws `dataMissingInCache` while the data is on disk. `image(for:)` on the same request succeeds offline.
- Controls pass: plain `data(for:)` twice gives 1 download, and thumbnail or processed `image(for:)` twice gives 1 download. Prefetch-to-disk followed by an `image(for:)` display also gives 1 download, so the main display path is not affected.

Where it applies: only pipelines that have a `DataCache`. `ImagePipeline.shared` uses URLCache with no DataCache, so there the HTTP cache hides the problem. `Configuration.withDataCache` sets `urlCache = nil`, so every repeat is a real network download. That configuration is common.

Impact: medium. Repeated `data(for:)` calls, and repeated `.diskCache` prefetches of thumbnail or processed requests (for example on scroll back-and-forth after memory-cache eviction), download the full original every time. Offline `data(for:)` with `.returnCacheDataDontLoad` wrongly fails. Images still display correctly.

The fix below makes all 11 scratch tests pass. The repository was not modified.

**Suggested fix:**

In TaskLoadData.start(), when the full-key lookup misses, also look up the sanitized request, which is the key TaskFetchOriginalData stores under. This mirrors the #837 fallback in TaskLoadImage:

    override func start() {
        if let data = lookUpCachedData(for: request) ?? lookUpOriginalData() { ... } else { loadData() }
    }
    /// The fetch below stores the original data under the sanitized key.
    private func lookUpOriginalData() -> Data? {
        guard request.thumbnail != nil || !request.processors.isEmpty else { return nil }
        return lookUpCachedData(for: request.withProcessors([]).withoutThumbnail())
    }

With this patch all 11 tests pass in a scratch copy: the 3 original repros, the controls, a public ImagePrefetcher(.diskCache) test and an offline .returnCacheDataDontLoad test. Worth adding regression tests to ImagePipelineLoadDataTests for thumbnail and processed data requests, and to ImagePrefetcherTests for .diskCache re-prefetch. Diagnostics tests may now see a second diskLookup stage on a miss for these requests.


### D11. A resumed (206) download that fails again loses all resumable data

_Severity: medium · user impact: medium · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:352`

**Repro:** [NukeTests/data-loading-tasks--resumed-download-failure-loses-resumable-data.swift](NukeTests/data-loading-tasks--resumed-download-failure-loses-resumable-data.swift)

**What:** `tryToSaveResumableData()` builds `ResumableData(response: urlResponse, data: data)`. After a resume, `urlResponse` is the 206 response, whose `expectedContentLength` covers only the remaining bytes, while `data` already holds the earlier bytes plus the new ones. `ResumableData.init` requires `data.count < expectedContentLength`, so it returns nil once earlier + received >= remaining. The old `resumableData` was already set to nil in `dataTask(didReceiveResponse:)`, so nothing is stored. `ResumableDataTests.createWithStatusCodePartialContent` states the intent to keep 206 data "in case the resumed download fails". The same earlier-vs-remaining mismatch was already fixed for the preview guard.

**Expected:** Attempt 3 sends `Range: bytes=20000-` (attempt 1 failed at 8000 bytes; attempt 2 resumed and failed at offset 20000).

**Actual:** Attempt 3 sends no Range header and downloads the whole image again.

**Reproduction check:** Failed 3/3 iterations at the last assertion: server.requests.last Range → nil, expected "bytes=20000-". The earlier checks passed: attempt 2 sent bytes=8000-, and attempt 3 returned the full data after downloading from scratch (log: scratchpad/logs/repro-data-loading-tasks-4.log).

**Refutation attempt (failed):**

I could not refute this. The code does what the report says, and the repro fails on HEAD (2c2b23f6).

How the code behaves:
- `dataTask(didReceiveResponse:)` (TaskFetchOriginalData.swift:213-222) copies the resumed prefix into `data` and records it in `resumedDataCount`. It then sets `resumableData = nil`.
- `urlResponse` is the 206 response. Its `expectedContentLength` is the Content-Length of the partial body, which is only the remaining bytes. This is how HTTPURLResponse normally reports a 206, so a mock is not causing it.
- `tryToSaveResumableData()` (line 346) calls `ResumableData(response: urlResponse, data: data)`. `ResumableData.init` checks `data.count < response.expectedContentLength` without adding the prefix. Once prefix + received >= remaining, it returns nil.
- The `else if let resumableData` fallback does not run because that property is already nil. Nothing is stored, and the next attempt downloads the whole image again.
- Other checks in the same file already add `resumedDataCount`: progress, the size limit, the diagnostics expected bytes, and the preview guard (fixed in 4120ea5f / PR #903). This one call was missed.

Is the behavior promised?
- Documentation/Nuke.docc (loading-data.md, performance-guide.md) says: "If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous one left off." A resumed download that stops again is still a partially loaded image.
- The NukeUI docs for LazyImage say a view that disappears and reappears "picks up where it left off." Cancellation goes through the same `onCancelled -> tryToSaveResumableData()` path. So scrolling a cell away a second time loses the bytes too.
- `ResumableDataTests.createWithStatusCodePartialContent` exists "in case the resumed download fails", so 206 data is meant to be kept.
- Commit a8b1d896 (#389) added the `data.count < expectedContentLength` guard so that a completed download is not saved as resumable. That guard was written with 200 responses in mind, not a resumed 206.

Does the repro misuse the API? No. It only uses the public `pipeline.data(for:)` and a public `DataLoading` mock that follows the HTTP rules: it honors If-Range with the ETag, sends Accept-Ranges, and gives the 206 a correct Content-Length and Content-Range.

Test results (in a copy of HEAD in my scratchpad; the repo was not changed):
- Without a fix: `resumedDownloadThatFailsAgainKeepsItsBytes` fails. The second attempt correctly sends `Range: bytes=8000-`, but the third attempt sends no Range header.
- With the fix below: the repro and all 22 existing ResumableDataTests and ImagePipelineResumableDataTests pass. That includes `thatResumableDataIsntSavedIfCancelledWhenDownloadIsCompleted`, because a complete buffer (count == total) still fails the `<` check.

Impact: no wrong image and no crash. It costs bandwidth and time, and it happens silently. It hits flaky networks and the common cancel / reappear / cancel pattern in scrolling lists and prefetching. Downloads that are furthest along lose the most: if the prefix is at least half the file, any second interruption drops everything.

**Suggested fix:** Include the resumed prefix in the "still partial" check. In Sources/Nuke/Internal/ResumableData.swift, change the initializer to `init?(response: URLResponse, data: Data, resumedDataCount: Int64 = 0)` and the guard to `Int64(data.count) < response.expectedContentLength + resumedDataCount`. In TaskFetchOriginalData.tryToSaveResumableData(), call `ResumableData(response: response, data: data, resumedDataCount: resumedDataCount)`. I tested this in a scratch copy: the repro passes and all existing resumable-data tests still pass. Optional follow-up: some servers leave Accept-Ranges off a 206. In that case the initializer still returns nil even with this fix. You could keep the previous validator, or treat a 206 as range-capable, so the data is still kept.


### D12. skipDataLoadingQueue request joins an equivalent queued fetch and waits in the queue, contrary to its docs

_Severity: medium · user impact: low · public API: yes · known: defects.md #16 · found by: data-loading-tasks, request-model, task-engine_

**Where:** `Sources/Nuke/Internal/ImageRequestKeys.swift:106`

**Repro:** [NukeTests/data-loading-tasks--skip-data-loading-queue-joins-queued-fetch.swift](NukeTests/data-loading-tasks--skip-data-loading-queue-joins-queued-fetch.swift), [NukeTests/request-model--skip-data-loading-queue-coalesced.swift](NukeTests/request-model--skip-data-loading-queue-coalesced.swift), [NukeTests/task-engine--skip-queue-coalesced-into-queued-load.swift](NukeTests/task-engine--skip-queue-coalesced-into-queued-load.swift)

**What:** The docs for `Options.skipDataLoadingQueue` say it performs data loading immediately, ignoring the queue, and that "if there is an outstanding task for loading the same resource but without this option, a new task will be created". `TaskFetchOriginalDataKey` and `TaskFetchOriginalImageKey` don't include the options. So the new TaskLoadImage subscribes to the existing TaskFetchOriginalImage and TaskFetchOriginalData, whose operation is waiting in the dataLoadingQueue. The option is read from the first request and ignored for the one that joins.

**Expected:** With the queue suspended and an equivalent request queued, the `.skipDataLoadingQueue` request loads immediately.

**Actual:** It waits for the queue (here forever); the repro records a 10 s timeout and `urgentTask.status.result == nil`.

**Reproduction check:** Failed 3/3 iterations: 'TestExpectation timed out after 10.0 seconds' and urgentTask.status.result != nil failed. The .skipDataLoadingQueue request waits behind the suspended queue (log: scratchpad/logs/repro-data-loading-tasks-5.log).

**Refutation attempt (failed):**

I could not refute this. The bug is real, it reproduces, and the public API reaches it.

**What the docs promise.** `Options.skipDataLoadingQueue` (Sources/Nuke/ImageRequest.swift:339-344) says "Perform data loading immediately, ignoring dataLoadingQueue. It can be used to elevate priority of certain tasks." It also says "If there is an outstanding task for loading the same resource but without this option, a new task will be created." Nothing in CHANGELOG.md, Documentation/*.docc or any commit message limits this or says that joining a queued fetch is intended. The option was added in commit 1f510f62 (Nuke 11, 2022). At that time `DataLoadKey` also left out the options, so the key never matched the doc. The later refactors kept that. It is an oversight carried forward, not a design decision.

**How it happens.**
- `TaskLoadImageKey` includes `options`, so the urgent request gets its own `TaskLoadImage`. That is the only "new task" that gets created.
- It then calls `makeTaskFetchOriginalImage`, keyed by `TaskFetchOriginalImageKey`, which is imageId/cachePolicy/cellular plus scale/thumbnail and no options. The pool returns the existing `TaskFetchOriginalImage`.
- That task depends on the existing `TaskFetchOriginalData`. Its `loadData` read `.skipDataLoadingQueue` from the first request, which lacked it, so its operation sits in `dataLoadingQueue`.
- `TaskLoadData` goes through the same data key.

**Verification.** I ran this in a scratch copy at /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-skipq-join with xcodebuild on macOS.
- The original repro fails. The expectation times out after 10 s and `urgentTask.status.result == nil`.
- I added a test with no suspended queue, using only public API: `dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 1)`, with the only slot held by an unrelated `ImageRequest(id: "blocker", data:)` whose closure waits on a gate. Then I queued `ImageRequest(id: "a", data:)` and requested id "a" again with `.skipDataLoadingQueue`. The urgent request did not finish within 3 s while the blocker held the slot. The fetch closure ran only once in total, so the urgent request did not get a download of its own. It waited in the queue.
- In the reverse order the behavior flips. When the skip request comes first, a plain request that joins it also bypasses a suspended queue. The option's effect depends on which request arrives first.
- With both requests in flight, `createdTaskCount == 1`. The deduplication the doc says is lost still happens, and the queue-bypass the doc promises does not.

**Checking for other explanations.**
- It is not a harness artifact. A suspended queue only makes the wait last forever. In real use it is a delay that lasts until the queued slot frees up.
- It does not misuse the API. `ImagePipeline`, `ImageRequest.Options`, `TaskQueue.isSuspended` and `maxConcurrentTaskCount` are all public.
- It does not come from URLSession or the platform.

**Impact.** The realistic case is a prefetcher or list request without the option queuing an image, then the on-screen request adding `.skipDataLoadingQueue` to jump the queue. The on-screen request silently waits for a free data-loading slot. Its subscription priority can move the queued operation ahead of other queued work, but it cannot skip the queue. The cost is extra latency, not a failure or hang. There are workarounds: use the option on every request for that image, or cancel the queued one. So I rate the impact low.

**Suggested fix:**

The smallest fix that matches the docs: add `private let skipsDataLoadingQueue: Bool` to `TaskFetchOriginalDataKey` in Sources/Nuke/Internal/ImageRequestKeys.swift, set from `request.options.contains(.skipDataLoadingQueue)` and combined into `_hashValue`. `TaskFetchOriginalImageKey` embeds the data key, so image fetches split the same way. A skip-queue request then gets its own `TaskFetchOriginalData`, which runs `loadData` with the option and starts immediately. As the doc warns, this can mean a duplicate download of the same resource, and queued requests without the option still join each other. The cached-hash key stays cheap because it only adds one Bool.

A better but larger alternative: when a subscriber whose request has `.skipDataLoadingQueue` joins a `TaskFetchOriginalData` whose operation has not started yet, cancel or remove the queued operation and call `performDataLoad` or `performAsyncDataLoad` directly. That keeps a single download.

Either way, add a regression test like the saturated-queue one: queue with max 1, slot held by an unrelated request, the same id queued, then a `.skipDataLoadingQueue` request for that id should finish while the slot is still held. If the maintainers prefer to keep coalescing, fix the doc comment instead: say the option has no effect when an equivalent request without it is already waiting in the queue, and drop the "a new task will be created" note.

- Also reported by **request-model** (confirmed): skipDataLoadingQueue waits in the queue when the same resource is already queued
- Also reported by **task-engine** (confirmed): .skipDataLoadingQueue is ignored when a request for the same resource is waiting in dataLoadingQueue

### D13. A queued stage that never started is counted as the work of its kind (e.g. network), not as queue time, and is drawn as a solid bar

_Severity: medium · user impact: low · public API: yes · found by: diagnostics_

**Where:** `Sources/Nuke/Diagnostics/ImageTask+Metrics.swift:280`

**Repro:** [NukeTests/diagnostics--never-started-stage-counted-as-work.swift](NukeTests/diagnostics--never-started-stage-counted-as-work.swift)

**What:**

`timeShares` only splits off a stage's queue wait when `stage.startedAt` is set; the same check exists in `ImageTask+MetricsFormat.swift:434` (`split`). A stage with `queuedAt` set and `startedAt == nil` has a span that runs from `queuedAt` to the end of the task, so the whole span goes to `category(of: stage.kind)`. The timeline gets no `dataLoadingQueue`/`imageProcessingQueue` wait row and draws a solid bar next to "never started".

Case 1: a task cancelled while its download is still in `dataLoadingQueue`, the usual case when fast scrolling cancels tasks behind a busy queue.

Case 2, a successful task: with progressive decoding and a processor, the preview's process is cancelled while still queued when the final image arrives (`TaskLoadImage.process`, `operation?.cancel()`). That never-started stage is then charged as `process` over the decode, cache writes and hops that followed.

This contradicts the docs: `Category.queue` is "The wait for one of the queues"; `Options.chart` says waits are drawn light; `formatted(_:)` says a stage that waited on its queue gets a wait row named after the queue.

**Expected:** A task cancelled after waiting ~30 ms for `dataLoadingQueue` reports `queue ~30 ms` and a light `dataLoadingQueue` wait row. In a successful progressive task, the `process` share is no larger than the process work that actually ran.

**Actual:** `time: network 30.4 ms (100%) · other <0.1 ms` and `└─ download 30.4 ms ████████████████████ 100% never started`. In the progressive case, `process 3.0 ms` for a single process that ran 2.4 ms, next to a solid `process … never started` bar. A hand-built 1 s record with only a never-started queued download gives `timeShares == [network]`.

**Reproduction check:** All three tests failed in all 3 iterations. (1) Cancelled while queued: `time: network 0.3 ms (21%) · other 1.2 ms (79%)`, `└─ download 0.3 ms ████ 21% never started`, and no `.queue` in timeShares. The wait was sub-millisecond in my runs, not 30 ms, but it was still charged to network. (2) Progressive task with a processor: `process 2.29 ms in the breakdown, 1.89 ms of processing`, and the timeline has a solid `├─ process 3.7 ms ██ never started` row next to the real one. (3) Hand-built 1 s record: `Unexpected shares: ["network 1.0"]`, the row is `└─ download 1000.0 ms ████████████████████ never started`, and there is no `dataLoadingQueue` row.

**Refutation attempt (failed):**

I could not refute this. It is a real defect in public diagnostics output.

1. The code does what the report says. In `timeShares` (Sources/Nuke/Diagnostics/ImageTask+Metrics.swift:280) and in `split` (Sources/Nuke/Diagnostics/ImageTask+MetricsFormat.swift:434), the queue wait is only split off when `stage.startedAt` is set. A stage that is queued but never started has `startedAt == nil`, and therefore `duration == nil` and `endedAt == nil`. `span(of:in:)` (ImageTask+Metrics.swift:358-361) then gives it an open end, so its span runs from `queuedAt` to the end of the task, and the whole span goes to `category(of: stage.kind)`. `Stage.end(at:)` (DiagnosticsRecorder.swift:363-366) returns early when a stage never started, so `JobRecord.finish` never closes one. When `TaskLoadImage.process`/`didReceiveImageResponse` (TaskLoadImage.swift:72, 127) or `TaskFetchOriginalImage` (line 53) call `operation?.cancel()` on a pending progressive operation, they do not tell the diagnostics, so that stage stays open until the task ends.

2. I reproduced it. I exported HEAD with `git archive` to scratchpad/refute-neverstarted, added the repro file, and ran `xcodebuild test -only-testing:NukeTests/DiagnosticsNeverStartedStageRepro` on macOS. All 3 tests fail (6 issues):
   - Cancelled in `dataLoadingQueue`: the line reads `time: network 0.3 ms (21%) · other ...` next to `└─ download 0.3 ms ████ 21% never started`. There is no queue share and no `dataLoadingQueue` row.
   - Successful progressive task with a processor: the line reads `process 3.1 ms` for a process that ran 2.5 ms. The row `├─ process 3.6 ms █ 3% never started` is drawn solid and runs to the end of the task, over the final decode, the real process and the memory store.
   - Hand-built record: the shares come out as `network` only, the row is solid, and there is no wait row.

3. The behavior is not intentional or documented, and it contradicts the docs:
   - The code comment says "The wait for a queue is not the work it held up".
   - `Stage.startedAt` is "`nil` if the stage never left its queue", so a never-started queued stage is all wait.
   - `Category.queue` is "The wait for one of the queues ... where the time goes when the pipeline is busy".
   - `Options.chart` says a wait is drawn light.
   - `formatted(_:)` promises a wait row named after the queue.
   Commit fee87ca5 ("Rework the metrics report") says the categories partition the task. It does not mention never-started stages, and no test covers them. Tests such as `queueWaitIsARowOfItsOwn` and `cancellationIsRecorded` only cover stages that started.

4. The API is not misused, and this is not a test artifact or a platform effect. The live repros use public API only: `isDiagnosticsEnabled`, `TaskQueue.isSuspended` (public), `cancel()`, `metrics`, `timeShares` and `description`. Suspending the queue only stands in for a busy queue, which is common: fast scrolling cancels tasks that are still waiting behind the 6-slot `dataLoadingQueue`. The logic is deterministic. The hand-built record uses the internal init, but only to get exact numbers.

Impact is limited. Diagnostics are opt-in and only in the unreleased Nuke 14 WIP (CHANGELOG, PR #960), and image loading itself is unaffected. The "never started" label is printed, so a careful reader can spot the problem. Still, `timeShares` and the `time:` line wrongly count queue waits as network time, which is exactly the busy-pipeline case the `queue` category exists for. They also inflate process/decode time for successful progressive tasks. A telemetry pipeline that adds up shares would mislead.

**Suggested fix:**

1. Treat a queued stage that never started (`queuedAt != nil && startedAt == nil`) as all wait:
   - In `timeShares`, append `(.queue, span)` for it instead of `(category(of: stage.kind), span)`.
   - In `split`, return `(queue: span, body: nil)` and make `body` optional, or draw the stage row with `isWait: true`, so the row is light and named after the queue (e.g. `dataLoadingQueue ... never started`).

2. Bound the span of such a stage. Otherwise the fix just moves the error: the preview's leftover wait would claim the final decode and process as `queue`, because `queue` ranks above both. Two options:
   - Record when the queued stage was abandoned. Add a `JobRecord.cancelStage(_:)` that stores an end time for never-started stages. Call it where `operation?.cancel()` replaces a pending progressive operation (TaskLoadImage.swift:72 and 127, TaskFetchOriginalImage.swift:53), and in `JobRecord.finish`.
   - Or, with no schema change, clamp a never-started stage's span in `span(of:in:)` to `job.endedAt` and to the `queuedAt` of the next stage of the same kind in the same job, which is the one that replaced it.

3. Add unit tests for the three repro shapes.


### D14. .disableDiskCacheWrites is ignored when storing encoded/processed images

_Severity: medium · user impact: medium · public API: yes · found by: image-decode-process-tasks, pipeline-caching, request-model_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:206`

**Repro:** [NukeTests/image-decode-process-tasks--disable-disk-cache-writes-ignored-for-encoded-images.swift](NukeTests/image-decode-process-tasks--disable-disk-cache-writes-ignored-for-encoded-images.swift), [NukeTests/pipeline-caching--disable-disk-writes-ignored-for-encoded-images.swift](NukeTests/pipeline-caching--disable-disk-writes-ignored-for-encoded-images.swift), [NukeTests/request-model--disable-disk-cache-writes-ignored-for-encoded-images.swift](NukeTests/request-model--disable-disk-cache-writes-ignored-for-encoded-images.swift)

**What:** shouldStoreResponseInDataCache checks dataCachePolicy but never request.options. storeImageInDataCache then writes with dataCache.storeData directly, which bypasses the option check in ImagePipeline.Cache.storeCachedData. The check was removed in 19423094 when options became part of the task key, and nothing checked request.options in its place. TaskFetchOriginalData does honor the option for original data.

**Expected:** A request with .disableDiskCacheWrites never writes to DataCaching. The option is documented as "Disables disk cache writes".

**Actual:** With .automatic, .storeAll or .storeEncodedImages, the processed image is encoded and written anyway: writeCount is 1 and the key url+"1" is stored.

**Reproduction check:** Failed on all 3 iterations, for each of .automatic, .storeAll and .storeEncodedImages: `dataCache.writeCount == 0 → false` and `dataCache.store.isEmpty → false`. That is 9 failures per expectation in repro-image-decode-process-tasks-1.log.

**Refutation attempt (failed):**

The bug is real, and I couldn't refute it.

1. It happens through the public API, not just in the mock. In a HEAD snapshot at scratchpad/refute-ddcw-encoded/repo, I added a test that uses only `import Nuke` with a real `DataCache`, `dataCachePolicy = .automatic`, a local fixture file URL, `processors: [.resize(width: 40)]` and `options: [.disableDiskCacheWrites]`. After `pipeline.image(for:)`, draining the encoding queue and `await cache.flush()`, `pipeline.cache.containsData(for: request)` returned true. The same request without the option (the control) also writes. The agent's repro fails for `.automatic`, `.storeAll` and `.storeEncodedImages`: `writeCount` is 1 and the "url1" key is stored.

2. The behavior is promised and relied on.
- `ImageRequest.Options.disableDiskCacheWrites` is documented as "Disables disk cache writes (see DataCaching)".
- The `ImageRequest(id:data:)` doc says the fetched data will be stored in the disk cache and to "Use disableDiskCache to prevent this".
- Everywhere else the option is honored: `ImagePipeline.Cache.storeCachedData` and `TaskFetchOriginalData.shouldStoreDataInDiskCache` both check it.
- Nothing in CHANGELOG.md or the docs says the option skips processed images.

3. The history points to an oversight. cdbc3e9d added the "Storing directly ignoring `ImageRequest.Options`" comment at a time when `shouldStoreFinalImageInDiskCache` already checked subscribers for `.disableDiskCacheWrites`. Forty minutes later, 19423094 ("TaskLoadImage no longer needs to check subscribed tasks") added options to the task key and deleted the whole guard. It never swapped in a check of the task's own `request.options`. `TaskLoadImageKey` still includes options (Internal/ImageRequestKeys.swift:58), so every subscriber of a `TaskLoadImage` shares the same options, and a single `request.options` check is exact.

4. It isn't an artifact of the test harness. Neither the actor usage nor the mock matters, and it isn't platform behavior.

5. The existing tests miss it. `policyGivenCoalescedRequests` only checks the original-data key, never the processed "url+p1" key.

Impact is medium, not high. The default `dataCachePolicy` is `.storeOriginalData`, which doesn't trigger the bug. It only shows up when a user picks `.automatic`, `.storeAll` or `.storeEncodedImages` and also uses processors or thumbnails, or uses `.storeEncodedImages` with any request. For those users, images they explicitly asked not to persist, possibly sensitive content, are encoded and written to disk anyway, wasting CPU and disk space.

The fix passes. I applied the one-line guard in the snapshot and ran the repro, the public-API test, and the ImagePipelineDataCachingTests, ImagePipelineDataCachePolicyTests, ImagePipelineCacheTests and ImagePipelineImageCacheTests suites: all passed (68 tests in the first run, 22 in the second). The real repo at /Users/kean/Developer/Nuke was not modified.

**Suggested fix:**

In `shouldStoreResponseInDataCache` in Sources/Nuke/Tasks/TaskLoadImage.swift (around line 206), add the option to the existing guard:

    guard !response.container.isPreview,
          !(response.cacheType == .disk),
          !request.options.contains(.disableDiskCacheWrites) else {
        return false
    }

This is enough because options are part of `TaskLoadImageKey`, so all subscribers share them. Also update or remove the "Storing directly ignoring `ImageRequest.Options`" comment in `storeImageInDataCache`. Then add a regression test: a parameterized run over `.automatic`, `.storeAll` and `.storeEncodedImages` with a processor and `.disableDiskCacheWrites`, expecting `writeCount == 0`. Optionally, extend `policyGivenCoalescedRequests` so it also checks the processed "url+p1" key.

- Also reported by **pipeline-caching** (confirmed): .disableDiskCacheWrites is ignored when the pipeline stores encoded processed images or thumbnails
- Also reported by **request-model** (confirmed): .disableDiskCacheWrites is ignored for encoded images (processed, thumbnails, storeEncodedImages)

### D15. .returnCacheDataDontLoad fails processed requests even when the original image is cached

_Severity: medium · user impact: medium · public API: yes · found by: image-decode-process-tasks, pipeline-caching_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:52`

**Repro:** [NukeTests/image-decode-process-tasks--return-cache-data-dont-load-ignores-cached-original.swift](NukeTests/image-decode-process-tasks--return-cache-data-dont-load-ignores-cached-original.swift), [NukeTests/pipeline-caching--return-cache-data-dont-load-ignores-cached-original.swift](NukeTests/pipeline-caching--return-cache-data-dont-load-ignores-cached-original.swift)

**What:** fetchImage() checks .returnCacheDataDontLoad before it subscribes to the TaskLoadImage for the request without the last processor. As a result, the cached intermediate and original images are never looked up. With the default .storeOriginalData policy, processed images are never on disk, so after a relaunch a processed request with this option can never succeed. Thumbnail requests already fall back to the original data correctly. The check moved here from the data-loading task in 4f2ce69f.

**Expected:** Doc: "Use existing cache data and fail if no cached data is available." The processed image should be built from the cached original, without going to the network.

**Actual:** The request throws .dataMissingInCache both when the original data is on disk and when the original image is in the memory cache.

**Reproduction check:** Both tests failed on all 3 iterations with `Caught error: Failed to load data from cache and download is disabled.`, the description of ImagePipeline.Error.dataMissingInCache. One test has the original data on disk (default .storeOriginalData policy), the other has the original image in the memory cache.

**Refutation attempt (failed):**

I could not refute this. The bug is real, it can be reached through the public API, and it is a regression, not a design choice.

1. I reproduced it on a scratch copy of the repo; the real repo was not touched. Both repro tests fail with "Failed to load data from cache and download is disabled." (.dataMissingInCache). I added control tests in the same setup:
   - Without the option, the processed request is built from the cached original with zero data-loader tasks, both from disk (cacheType .disk) and from memory (.memory). So everything the request needs is in the cache.
   - A thumbnail request with .returnCacheDataDontLoad succeeds from the original data on disk. This is the fallback added for #837 in commit 67fbf4ed.
   - With a real DataCache and the default .storeOriginalData policy, I loaded a Resize-processed image once and flushed the cache. A new pipeline on the same cache then issued the same request with .returnCacheDataDontLoad. It throws .dataMissingInCache even though the original data is on disk. So cache-only (for example offline) loading of processed images can never succeed after a relaunch with the default configuration.

2. Nothing documents this as intentional:
   - The option's doc says "Use existing cache data and fail if no cached data is available."
   - Documentation/Nuke.docc says "Only return a cached result; don't go to the network" and "perform cache lookup without downloading the image from the network".
   - Nothing says processed requests only consult the final processed image.
   - The CHANGELOG has no entry that narrows the behavior.

3. The history shows it is a regression:
   - The option was added in d0717be7. There the check was in TaskLoadImageData.loadData(), after that task's disk lookup, which served the original data processed requests are built from. So a processed request could use the cached original.
   - Five days later, 4f2ce69f ("Add TaskLoadData") moved the check into TaskLoadImage.loadImage(), before the recursive subscription to the request without processors. The commit message gives no reason for the change, and it came with no test. The existing tests (ImagePipelineDataCacheTests loadFromCacheOnly*) only cover requests without processors, so the change went unnoticed.
   - The current fetchImage() keeps that ordering at TaskLoadImage.swift:52. The later thumbnail fallback shows the maintainer considers "derive from the cached original" correct.

4. The repro does not misuse the API. It uses the public ImageRequest(url:processors:options:) and imageTask(with:).response. The mocks only stand in for the caches and the loader, and the real-DataCache variant fails the same way. Nothing here is platform or URLSession behavior.

5. I checked that the fix is safe. TaskLoadImageKey includes `options`, so the child TaskLoadImage made for a .returnCacheDataDontLoad request is never shared with normal requests. AsyncTask.Publisher.subscribe(_:onValue:) forwards the child's errors, so a miss at the bottom of the chain still comes back as .dataMissingInCache. With the check moved (see suggestedFix), the repro and control tests pass, and so does the full NukeTests target: 1110 tests in 79 suites.

The data(for:) path has a related gap. TaskLoadData.loadData() fails with .dataMissingInCache before falling back to the original data when a request has processors. That is out of scope here.

Impact is medium. Using .returnCacheDataDontLoad for offline or cache-only display (for example with LazyImage) is documented. Combining it with processors, such as a resize for a thumbnail cell, is common. With the default dataCachePolicy these requests always fail after a relaunch, and in-session they fail whenever only the original image is in memory. There is no crash or data loss; the image just isn't shown.

**Suggested fix:**

In Sources/Nuke/Tasks/TaskLoadImage.swift fetchImage(), apply the .returnCacheDataDontLoad check only where the network would actually be used, which is the branch with no processors. With processors, let the recursive TaskLoadImage for the request without the last processor do its own memory and disk lookups; if they all miss, its .dataMissingInCache error propagates up.

    private func fetchImage() {
        if let processor = request.processors.last {
            let request = request.withProcessors(request.processors.dropLast())
            dependency = pipeline.makeTaskLoadImage(for: request).subscribe(self) { [weak self] in
                self?.process($0, isCompleted: $1, processor: processor)
            }
        } else {
            guard !request.options.contains(.returnCacheDataDontLoad) else {
                return send(error: .dataMissingInCache)
            }
            dependency = pipeline.makeTaskFetchOriginalImage(for: request).subscribe(self) { [weak self] in
                self?.didReceiveImageResponse($0, isCompleted: $1)
            }
        }
    }

This is safe because TaskLoadImageKey includes options, so child tasks for cache-only requests are never shared with normal ones. I verified it on a scratch copy: the full NukeTests target passes, 1110 tests in 79 suites. Also add regression tests in ImagePipelineDataCacheTests for a processed request built from (a) original data on disk, (b) the original image in memory, and (c) a cached intermediate image, each with dataLoader.createdTaskCount == 0; plus a test that the request still fails with .dataMissingInCache when nothing is cached. Optionally apply the same change to TaskLoadData.loadData() so data(for:) with processors falls back to the cached original data.

- Also reported by **pipeline-caching** (confirmed): .returnCacheDataDontLoad fails for processed requests even when the original or an intermediate image is cached

### D16. Processed GIFs are never stored in the disk cache

_Severity: medium · user impact: medium · public API: yes · known: defects.md #52 · found by: image-decode-process-tasks, processing-graphics-encoding_

**Where:** `Sources/Nuke/Encoding/ImageEncoding.swift:28`

**Repro:** [NukeTests/image-decode-process-tasks--processed-gif-never-stored-in-disk-cache.swift](NukeTests/image-decode-process-tasks--processed-gif-never-stored-in-disk-cache.swift), [NukeTests/processing-graphics-encoding--animated-container-encoded-as-still.swift](NukeTests/processing-graphics-encoding--animated-container-encoded-as-still.swift)

**What:** Since #958, processing (ImageContainer.map) keeps type == .gif but drops data. The default ImageEncoding.encode(_:context:), which ImageEncoders.Default doesn't override, returns container.data for .gif containers, and that is nil here. So TaskLoadImage.storeImageInDataCache stores nothing. Under .automatic the original isn't stored either, because the request has processors. A processed GIF is therefore downloaded again on every cold start.

**Expected:** Under .automatic, .storeAll or .storeEncodedImages, the processed image is encoded and stored under the processed request's key, as it is for other formats.

**Actual:** dataCache.store[key] is nil for all three policies.

**Reproduction check:** `dataCache.store[key] != nil` failed on all 3 iterations for .automatic, .storeAll and .storeEncodedImages. The test's own checks `response.container.type == .gif` and `response.container.data == nil` passed.

**Refutation attempt (failed):**

I could not refute this. It is a real regression on main, in unreleased Nuke 14 work, and a user can hit it through the public API alone.

Why it happens:
- Commit 7d9de586 ("Drop the attached data when a processor maps the image", part of #958) made `ImageContainer.map` set `data = nil`. Map is used by the default `ImageProcessing.process(_:context:)` and by `CoreImageFilter`, and it does not change `type`, so a processed GIF comes out as `type == .gif` with `data == nil`.
- The default `ImageEncoding.encode(_:context:)` (ImageEncoding.swift:28) returns `container.data` for any `.gif` container. `ImageEncoders.Default` does not override it, so the encoder returns nil.
- `storeImageInDataCache` then returns at `guard let data, !data.isEmpty` and nothing is written.
- Under `.automatic`, the original data isn't stored either, because `shouldStoreDataInDiskCache` requires `processors.isEmpty`. `.storeEncodedImages` never stores the original.

Before #958, the default processor kept `data`, so the original GIF bytes were stored under the processed key. That was imprecise, but it did avoid a download. The data-less GIF container is new since #958, and nobody updated the encoder's GIF pass-through for it.

Is it intended or documented? No:
- The CHANGELOG and AnimatedImages.md say processing turns an animation into a still on purpose. Nothing says a processed image then skips the disk cache.
- The `DataCachePolicy` docs promise the opposite: `.automatic` should "Store _only_ processed images for requests with processors", and `.storeEncodedImages` should "Encode and store images".
- The only thing that pins the nil result is the unit test `ImageEncodingTests.gifContainerWithoutDataReturnsNil`. It was added in March, before #958, when a data-less GIF container never came out of the pipeline. It fixes incidental behavior in place; it is not a design decision.

Is it a test artifact? No. The agent's repro fails for all three policies. I also wrote an end-to-end test that uses only public API: a real `DataCache` in a temp directory, `ImageProcessors.Resize(width: 16)`, and a second pipeline sharing that disk cache to stand in for a cold start. Results on macOS:

| Case | Policy | Loads on 2nd pipeline | Entries on disk |
|---|---|---|---|
| Processed GIF | `.automatic` | 1 (downloaded again) | 0 |
| Processed GIF | `.storeEncodedImages` | 1 (downloaded again) | 0 |
| Processed GIF | `.storeAll` | 0 (re-processed from the stored original) | 1, original only |
| Processed PNG (control) | all three | 0 | stored normally |
| Unprocessed GIF (control) | all | 0 | stored normally |

With a one-line fix applied, all processed-GIF cases load 0 times on the second pipeline. The existing ImagePipelineDataCachingTests, ImagePipelineFormatsTests, ImageProcessorsAnimatedImageDataTests and ImageEncodingProtocolTests still pass, apart from the one pre-958 test that expects nil.

How bad it is:
- The default policy, `.storeOriginalData`, is not affected.
- `.storeAll` only costs a re-process.
- Users who chose `.automatic` or `.storeEncodedImages` with a `DataCache` lose disk caching for every processed or `CoreImageFilter`-ed GIF. That includes the common `LazyImage`/`ImageRequest` with `.resize`. `.withDataCache` turns off `URLCache`, so there is no HTTP cache to fall back on, and the GIF is downloaded again on every cold start.
- Nothing is lost or wrong on screen. The effect is wasted bandwidth and slower loads.

My test file and the patched copy of the repo are in `/private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-procgif/` (logs `log1.txt`–`log3.txt`). I made no changes to the repo itself.

**Suggested fix:**

In `Sources/Nuke/Encoding/ImageEncoding.swift`, pass the GIF bytes through only when they are actually there; otherwise encode the still:

```swift
public func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
    if container.type == .gif, let data = container.data {
        return data
    }
    return self.encode(container.image)
}
```

The processed image is a still by design, so storing it as JPEG/PNG/HEIC under the processed key gives back exactly what the pipeline returned. Update `ImageEncodingTests.gifContainerWithoutDataReturnsNil` to expect non-nil encoded still data. Add a pipeline test in which a processed GIF under `.automatic` and `.storeEncodedImages` is stored and then served from disk by a fresh pipeline. Add a one-line CHANGELOG entry under Nuke 14 WIP if the fix ships after #958 is released.

A related gap, which is not this bug: since #958, data is also attached to APNG, WebP and HEIC/AVIF sequences. The pass-through only checks `.gif`, so under `.storeEncodedImages` an unprocessed animated APNG or HEICS is still flattened to a single frame. Keying the pass-through on `container.data != nil`, or on `animation != nil`, would cover those too.

- Also reported by **processing-graphics-encoding** (confirmed): Default ImageEncoding.encode(_:context:) passes data through by type == .gif: animated APNG/WebP/HEICS/AVIF are stored as stills, and GIF thumbnails aren't stored at all

### D17. A processed image built from disk-cached data is never stored on disk (cacheType .disk carries over through processing)

_Severity: medium · user impact: medium · public API: yes · found by: image-decode-process-tasks, pipeline-caching, request-model_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:208`

**Repro:** [NukeTests/image-decode-process-tasks--processed-image-from-disk-original-not-stored.swift](NukeTests/image-decode-process-tasks--processed-image-from-disk-original-not-stored.swift), [NukeTests/pipeline-caching--processed-image-from-disk-original-not-stored.swift](NukeTests/pipeline-caching--processed-image-from-disk-original-not-stored.swift), [NukeTests/request-model--review-processed-image-from-cached-original-not-stored.swift](NukeTests/request-model--review-processed-image-from-cached-original-not-stored.swift)

**What:** process() copies the input response, cacheType included, into the processed response. shouldStoreResponseInDataCache skips any response with cacheType == .disk, a check meant for an image read from the request's own disk entry. So a processed image derived from the disk-cached original is recomputed on every cold start. The same image derived from a memory-cached original (cacheType .memory) is stored; a committed test covers that case.

**Expected:** Under .automatic or .storeAll, the processed image is stored under the processed key when it isn't already there.

**Actual:** The processed key is never written.

**Reproduction check:** `dataCache.store[pipeline.cache.makeDataCacheKey(for: request)] != nil` failed on all 3 iterations for both .automatic and .storeAll. The processor IDs and `createdTaskCount == 0` expectations passed.

**Refutation attempt (failed):**

I couldn't refute it. The bug is real and reachable through the public API, and it's a regression from a refactor, not intended behavior.

**Reproduced on unmodified HEAD (2c2b23f6).** I exported it with git archive to the scratchpad; the repo itself is untouched. The agent's repro fails for both .automatic and .storeAll. I also wrote a cold-start test that uses only public API:
- Session 1 loads ImageRequest(url:), so the original data lands on disk.
- Session 2 is a fresh pipeline with the same DataCaching. It loads the same URL with a processor, and the processed key is never written.
- Session 3 does the same thing again and re-processes from the original.

The only keys ever stored are ["http://test.com/example.jpeg"].

**History shows it was not intended.**
- The skip was added in b9bf2274 (PR #500, Nuke 10.3.3, "Fix data cache overwrite issue"). It was an `isFromDiskCache` flag set to true only in `didDecodeCachedData`, which is the task's own disk entry. Its purpose was to avoid re-encoding and overwriting the entry the image had just been read from.
- The processing path explicitly passed `isFromDiskCache: false`. So up to 12.5, a processed image built from a disk-cached original was stored.
- a1a640b2 ("Cleanup TaskLoadImage", 2024-04-20, shipped in 12.6) replaced the flag with `response.cacheType != .disk`. That is broader than the flag because `process()` copies the input response (`var response = response`, line 86), including its cacheType. 38672c04 then moved the check into `shouldStoreResponseInDataCache` (line 208).
- No commit message or CHANGELOG entry says processed images derived from disk should be skipped.

**Documentation promises the opposite.** The DataCachePolicy.automatic doc says "Store _only_ processed images for requests with processors". The performance guide says .automatic "stores ... processed images for requests with processors".

**Existing tests don't pin the current behavior.** `ImagePipelineCacheLayerPriorityTests.givenOriginalImageInDiskCache` asserts writeCount == 1, but it runs under the default .storeOriginalData, which never stores processed images anyway. `policyAutomaticGivenOriginalImageInMemoryCache` on main already asserts the memory-original twin gets stored, which is the asymmetry the report describes.

**Not a test or platform artifact.** MockDataCache just conforms to the public DataCaching protocol. There is no ImageIO or URLSession involvement.

**Other ways to hit the same line:**
- A final processed image derived from an intermediate processed entry on disk (the 12.6 intermediate-lookup feature).
- A thumbnail decoded from the original's disk data (the #837 path, `decodeCachedData` on `request.withoutThumbnail()`) is never stored under the thumbnail key under .automatic or .storeAll.

**Impact is performance only, and permanent for affected entries.** The image is still correct. On every cold start, those entries decode the full original and run the processors again, instead of decoding the small processed entry. It only affects the non-default .automatic and .storeAll policies. It needs the original, or an intermediate, on disk while the final key is missing. Typical triggers:
- A new processor size, e.g. rotation or a changed cell size, for an image already shown full-size.
- The processed entry was evicted.
- A multi-processor chain whose intermediate entry is on disk.

**Fix verified.** In the scratch copy, I threaded an `isFromOwnDiskEntry` flag through the store path and removed the cacheType check (see suggested fix). With that change, both repro tests pass and all 1106 NukeTests pass. Public `cacheType` still reports .disk for processed-from-disk responses, which the existing tests assert. In session 3, the processed image is read from the "…p1" key with no processing.

**Suggested fix:**

In Sources/Nuke/Tasks/TaskLoadImage.swift, bring back the pre-12.6 semantics: skip the disk write only when the image was decoded from this request's own disk entry, not whenever the response's cacheType is .disk.

1. In `start()`, call `decodeCachedData(data, isOwnEntry: true)` only for `lookUpCachedData(for: request)`. The thumbnail fallback that reads `request.withoutThumbnail()` stays `isOwnEntry: false`.
2. Pass `isOwnEntry` through `didFinishDecoding`, then as `isFromOwnDiskEntry` through `didReceiveImageResponse`, `didReceiveDecompressedImage` and `storeImageInCaches`, where the write becomes `if !isFromOwnDiskEntry, shouldStoreResponseInDataCache(response) { storeImageInDataCache(response) }`.
3. In `shouldStoreResponseInDataCache`, remove `!(response.cacheType == .disk)` from the guard and keep only the `isPreview` check.

Don't clear `response.cacheType` in `process()`. The public cacheType propagation (.disk or .memory for processed images) is asserted by existing tests.

Regression tests to add:
- The agent's repro for .automatic and .storeAll: original data seeded in MockDataCache, a request with one processor, then expect the processed key in the store.
- An intermediate-on-disk variant with processors [p1, p2] and [p1] on disk.
- The thumbnail-from-original-data variant under .storeAll.

With this patch, the scratch copy passes the full NukeTests suite (1106 tests).

- Also reported by **pipeline-caching** (confirmed): A processed image or thumbnail made from disk-cached original data is never stored in the disk cache
- Also reported by **request-model** (confirmed): A processed image or thumbnail made from original data in the disk cache is never written to the disk cache

### D18. A new image stored in a full cache is evicted by its own insertion when every existing entry has been read

_Severity: medium · user impact: medium · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:157`

**Repro:** [NukeTests/memory-cache--new-entry-evicts-itself.swift](NukeTests/memory-cache--new-entry-evicts-itself.swift)

**What:** _add appends the new entry to the tail of the list with its reference bit clear, and set() calls _trim() only after that. The sweep in _trim(while:) (line 225) starts at the head. It clears each referenced entry's bit and moves it to the tail, behind the new entry. Once every old entry has been read, the sweep rotates all of them past the new one, which is then at the head, unreferenced, and gets evicted. In classic CLOCK the victim is picked before the new page takes its slot, so a page can never evict itself. In an app, this is the normal state of a full cache whose images are all being displayed: the next image the pipeline stores is dropped immediately, and the next lookup for it misses. The same happens when the cost limit, not the count limit, is what triggers eviction. This goes against the docs: "An LRU memory cache" that "discards the least recently cached images".

**Expected:** After cache[d] = image in a full cache (countLimit 3) whose entries a, b, c were all read, cache[d] returns the image and one of the older entries is gone. With countLimit 1, reading a and then storing b replaces a with b.

**Actual:** cache[d] is nil right after it was stored, and a, b and c all remain. With countLimit 1, b is dropped and a is kept.

**Reproduction check:** All 3 iterations failed with the claimed defect. imageStoredInAFullCacheIsKept: `cache[key("d")] != nil` failed, while `totalCount == 3` passed, so a, b and c were kept. imageStoredOverTheCostLimitIsKept (the cost-limit path): `cache[key("d")] != nil` failed. imageStoredInACacheWithACountLimitOfOneReplacesTheReadOne: both `cache[key("b")] != nil` and `cache[key("a")] == nil` failed. 12 issues in total, 4 per iteration. Log: scratchpad/logs/repro-memory-cache-1.log

**Refutation attempt (failed):**

I could not refute this. The bug is real, it happens every time, and it's a regression that shipped in 13.0.5.

**How the eviction happens** (Sources/Nuke/Caching/Cache.swift)
- `set()` calls `_add(entry)` first. `_add` appends a new key at the tail with `referenced = false`.
- Only then does `set()` call `_trim()`.
- The sweep in `_trim(while:)` (line 225) starts at the head. It clears each referenced entry's bit and moves the entry to the tail, behind the new one.
- Take [a*, b*, c*] and add d. The list goes [a*, b*, c*, d] → [b*, c*, d, a] → [c*, d, a, b] → [d, a, b, c]. Then d is evicted.

**Confirmed by running the real code**
I compiled copies of the real `Cache.swift` and `LinkedList.swift` with a driver in the scratchpad (`cache-verify/`); the repo was not touched.
- **Count limit 3:** after all three entries are read, the newly stored d is gone right away, and a, b and c remain.
- **Count limit 1:** reading a and then storing b keeps a and drops b.
- **Cost limit 35, cost 11 each:** d is dropped.
- **Sliding-window simulation** (the visible images are re-read at each step, then the new one is stored):

| Capacity | Visible | Stored images evicted by their own insertion | Misses | Misses with the fix |
|---|---|---|---|---|
| 20 | 10 | 16 | 225 | 209 |
| 20 | 20 | 100 | 318 | 219 |
| 20 | 21 | 200 of 200 | 419 | 220 |
| 100 | 30 | 2 | — | — |

**Intentional? No.**
- Commit a01bcfb3 ("Switch to CLOCK LRU in Cache", shipped in 13.0.5 as "Optimize `ImageCache` reads and writes for concurrent access patterns") was a lock-contention optimization. It says nothing about changing which entry gets evicted.
- Its code comment says only "Each entry can survive at most one full pass before becoming a candidate."
- The docs still promise LRU:
  - `ImageCache`: "An LRU memory cache".
  - `defaultCostLimit`: "custom LRU eviction policy".
  - cache-layers.md: "discards the least recently cached images".
  - performance-guide.md: "LRU (least recently used) replacement algorithm".
- As of 13.0.4, reads did `remove` + `append` and the trim evicted from the head. The newest entry could never evict itself unless it was the only entry. So the behaviour changed.
- Classic CLOCK picks the victim before the new page takes its slot. Evicting the most recent insertion while keeping every older entry is the opposite of LRU, not an acceptable approximation of it.

**Misuse, platform behaviour or test artifact? None of these.**
- The repro uses only public API: `ImageCache` subscript, `ImageCacheKey(key:)`, `PlatformImage` and `entryCostLimit`. It is deterministic and uses no mocks or timing.
- The pipeline and `ImagePipeline.Cache` write through the same `impl.set`, so normal apps reach this path.
- No existing test covers the case where every entry has been read. `recentlyUsedEntriesGetASecondChance` and `itemsAreTouched` read only some of the entries.

**Impact**
- It's a cache-efficiency problem, not a crash and not a wrong image. The dropped image has to be read from the disk cache and decoded again, or downloaded again, and the view shows its placeholder when it is reconfigured.
- The claim that this is "the normal state" of an app is overstated for the default cost limit (15% of RAM, capped at 768 MB): self-evictions there are rare, as the 100/30 simulation shows.
- It hits hard when the images being displayed roughly fill or exceed the cache: small `countLimit` or `costLimit`, full-screen photo pagers, grids of large images. In that regime, up to every newly stored image is dropped and misses nearly double.
- Images the prefetcher loads into a full cache whose entries have all been read are thrown away the same way.

**Fix**
I checked this in the scratch copy: it removes every self-eviction, and a trace of the existing CLOCK tests shows they still pass. Details are in suggestedFix.

**Suggested fix:**

In `Cache.set` (Sources/Nuke/Caching/Cache.swift), choose the victims before the new entry is added, the way classic CLOCK does, so the sweep can't pick the entry being stored:

```swift
let entry = Entry(value: value, key: key, cost: cost, expirationTimestamp: expirationTimestamp)
// Pick victims before the new entry takes its slot so it can't evict itself.
_trim(while: {
    let existing = map[key]
    let count = map.count + (existing == nil ? 1 : 0)
    let total = _totalCost - (existing?.value.cost ?? 0) + cost
    return (count > _conf.countLimit || total > _conf.costLimit) && !list.isEmpty
})
_add(entry)
_trim() // still needed for countLimit 0 / costLimit 0, where the new entry alone exceeds the limit
```

`_add` already handles the case where the pre-trim evicted the node being overwritten, because `map[key]` is then nil. Keep the fast path: skip the pre-trim when the cache is under its limits.

Add regression tests to Tests/NukeTests/CacheTests.swift and ImageCacheTests.swift for three cases:
- Count limit 3, all entries read, store d: d is present and a is evicted.
- Count limit 1: reading a and then storing b replaces a with b.
- The same scenario triggered by the cost limit.


### D19. Overwriting a key with an image over the entry cost limit leaves the old image in the cache

_Severity: medium · user impact: low · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:134`

**Repro:** [NukeTests/memory-cache--oversized-overwrite-keeps-stale.swift](NukeTests/memory-cache--oversized-overwrite-keeps-stale.swift)

**What:** set() returns early on `guard cost < _conf.entryMaxCost` before it looks at the entry the key already has. So `cache[key] = small; cache[key] = large` keeps serving `small`, a value the caller explicitly replaced, and its cost stays charged. The same happens through ImagePipeline.Cache: pipeline.cache[request] = bigImage leaves the previous image in place. An image reloaded with .reloadIgnoringCachedData that grew past the entry limit therefore leaves the outdated image to be returned by every later memory-cache lookup.

**Expected:** After an overwrite the cache holds the new image or nothing for that key. It may refuse the new image, but it must not keep the one being replaced.

**Actual:** cache[key] returns the old image (data.count 10) and totalCost is still 11. pipeline.cache[request] also returns the old image.

**Reproduction check:** All 3 iterations failed. overwritingWithAnOversizedImageDoesNotKeepTheOldOne: `cache[key]?.data?.count != 10` and `cache.totalCost != 11` failed, so the old 11-cost image is still served and still charged. pipelineCacheSubscriptKeepsTheOldImage: `pipeline.cache[request]?.data?.count != 10` failed. 9 issues in total. Log: scratchpad/logs/repro-memory-cache-2.log

**Refutation attempt (failed):**

The bug is real. I couldn't refute it.

Code: in Sources/Nuke/Caching/Cache.swift, `set()` hits `guard cost < _conf.entryMaxCost else { return }` at line 134 before `_add()` runs. `_add()` is the only place that replaces the node already stored for the key and subtracts its cost. So a write that is too big to cache does nothing at all, and the value it was meant to replace stays in the cache. `value(forKey:)` keeps returning it, and its cost stays in the total.

History and intent: the entry-size check came in with 879fb183 "Add entryCostLimit" (Nuke 10.1.0, 2021). It then moved into the internal Cache in 79d85e20 and was precomputed in 2fb459e8. None of these commit messages, the `entryCostLimit` doc comment ("The maximum cost of an entry in proportion to the costLimit"), CHANGELOG.md line 903, or the docc caching pages say that an oversized write leaves the previous value in place. Before 10.1 an oversized write replaced the old value, and the trim then evicted it, so the key ended up empty. Keeping the stale value looks like an accident of where the guard sits, not a design choice. The docs point the other way:
- accessing-caches.md presents `.reloadIgnoringCachedData` as the way to "keep the image in caches but reload it".
- cache-layers.md shows `ImageCache.shared[request] = ...` followed by a read, i.e. read-after-write.

No existing test covers overwriting an entry with an oversized one. CacheTests only covers overwrites within the limit and oversized writes to new keys.

Misuse or test artifact: neither. Every API in the repro is public (ImageCache, ImageCacheKey(key:), the ImageContainer init, ImagePipeline.Cache subscript). The `@testable` import isn't needed. I copied Sources/Nuke into a scratch SwiftPM package and ran the repro: all 3 expectations fail. The cache returns data.count 10 and totalCost is still 11.

End-to-end check through the pipeline, public API only:
- Setup: ImageCache(costLimit: 10 MB), so entries up to about 1 MB are accepted. A custom DataLoading serves a 400x400 PNG first, then an 800x800 PNG from the same URL.
- `pipeline.image(for: url)` returns 400 px.
- A reload with `.reloadIgnoringCachedData` returns 800 px.
- A later plain `pipeline.imageTask(with: url).response` returns **400 px with cacheType == .memory**.

So after a reload, the old image keeps being served as a complete, final image, not a preview, until it is evicted or a memory warning clears the cache. Meanwhile the disk and URL caches hold the new data.

Impact is low. It only happens when a new value for the same memory-cache key crosses the per-entry threshold while the old one was under it. That threshold is 10% of costLimit. With the default limit that means about 50–77 MB decoded (roughly 12–19 MP). With the custom limits the docs show (100 MB → 10 MB → about 1600x1600), it is easier to reach. The trigger is a mutable URL whose image grows, or a manual `pipeline.cache[request] = biggerImage`. The failure is silent: stale content is served, but nothing crashes and no memory leaks. The old entry keeps its own cost, which is within the limit.

Progressive previews that stay behind are handled: the pipeline keeps loading after a hit on a preview. So the realistic harm is the reload / manual-overwrite case.

**Suggested fix:**

In Sources/Nuke/Caching/Cache.swift `set(_:forKey:cost:ttl:)`, drop any existing entry for the key before refusing an oversized value, so the key ends up empty, as it did before 10.1:

    guard cost < _conf.entryMaxCost else {
        if let node = map[key] { _remove(node: node) }
        return
    }

This adds one dictionary lookup, and only on the rare path where a value is refused, so the fast path is unchanged. Add tests:
- CacheTests: set("a", cost: 5), then set("b", cost: 50) with costLimit 100 and entryCostLimit 0.1. Expect value == nil, totalCost == 0, totalCount == 0.
- ImageCacheTests / ImagePipelineCacheTests: overwrite through the subscript and expect nil.
- Optionally, a pipeline test: a reload with `.reloadIgnoringCachedData` that returns an oversized image must not leave the previous image to be served from memory later.


### D20. LazyImage applies pipeline/onStart/onCompletion/transaction only in onAppear; requests started by a view update use stale values

_Severity: medium · user impact: low · public API: yes · known: defects.md #29 · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/LazyImage.swift:181`

**Repro:** [NukeUITests/nukeui-swiftui--lazyimage-stale-modifiers.swift](NukeUITests/nukeui-swiftui--lazyimage-stale-modifiers.swift)

**What:** onAppear() copies pipeline, onStart, onCompletion and transaction into the FetchImage only when the view appears. onChange(of: context) at LazyImage.swift:162 then calls viewModel.load(...) with whatever was copied at first appearance. So when a parent re-renders the view with a new request and new modifier values in the same update, the new request goes through the old pipeline and is reported to the old closures. For example, a detail view with `onCompletion { vm.didLoad(item.id, $0) }` reports the new item's image under the previous item's id.

**Expected:** A request started by a view update uses the modifiers from that same update. The new URL is loaded through the new pipeline (the doc says pipeline(_:) 'Changes the underlying pipeline used for image loading') and is reported to the new onCompletion.

**Actual:** The old pipeline's data loader is hit twice (createdTaskCount == 2) and the new pipeline's is never hit (0). The completion for urls[1] is delivered to the closure captured for view index 0.

**Reproduction check:** Failed on all 3 iterations. requestStartedByAnUpdateUsesTheUpdatedPipeline: 'Expectation failed: loaders[0].createdTaskCount == 1' with loaders[0].createdTaskCount → 2 in the xcresult, and 'loaders[1].createdTaskCount == 1' also failed. requestStartedByAnUpdateReportsToTheUpdatedOnCompletion: 'Expectation failed: last.viewIndex == 1' with last.viewIndex → 0. The url == urls[1] check passed, so the new URL's completion went to the closure captured for view index 0.

**Refutation attempt (failed):**

The bug is real: I reproduced it. I copied the repo to /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-lazyimage-stale/repo and ran the repro on macOS (NukeUITests scheme, signing disabled). Both tests fail as described: the old pipeline's loader creates 2 tasks and the new one's 0, and the completion for urls[1] reaches the closure captured for view index 0.

Cause: Sources/NukeUI/LazyImage.swift:181-190. `onAppear()` is the only place that copies transaction, pipeline, onStart and onCompletion into the `@StateObject` FetchImage. `.onChange(of: context)` at line 162 only calls `viewModel.load(...)`, so any load started by a view update uses the values from the last appearance. FetchImage reads `self.pipeline` and `self.onCompletion` at load and completion time, so the stale values really are used.

Intentional or documented? No.
- `git log -S` shows the pattern started in f4d9b957 ("Add onCompletion closure to LazyImage"). Then 8be9080f ("Fix onStart", the CHANGELOG entry for #763) moved onStart out of the modifier and into onAppear. The only reason was to stop touching the StateObject before it is installed. Latching the values at first appearance was never a stated goal.
- The docs promise the opposite. `pipeline(_:)` says it "Changes the underlying pipeline used for image loading". `onCompletion` "Gets called when the current request is completed". Neither the NukeUI.docc articles nor the CHANGELOG say modifiers are latched at appear.
- The behavior is also inconsistent: the values do refresh when the view disappears and reappears, just not on a view update.

Not a misuse or test artifact. The repro only uses public API (`LazyImage(url:)`, `.pipeline`, `.onCompletion`) inside a normal hosting view/window (ViewHost). The failure comes from Nuke's own state handling, not from a mock or from ImageIO/URLSession.

Realistic user scenario: any LazyImage that keeps its identity while its URL changes. Examples are a NavigationSplitView or detail pane showing `DetailView(item:)` for a changing selection, or a carousel/header bound to state. Its `onCompletion`/`onStart` closures that capture plain per-item values (e.g. `item.id`) will report the new image under the old item. A closure that goes through @State or a reference type reads current values anyway, and switching pipeline per item is rare. So the damage is limited to wrong attribution in callbacks (analytics, a VM's `didLoad(id:)`) and to the rarer pipeline or transaction swap. Hence medium-low impact.

The obvious fix does not work, which I checked. Re-applying the options from `self` inside the `onChange` action changes nothing. `onChange(of:perform:)` runs the action closure of the previous view, so `self` there is still the old view. The repro still failed with that change.

A fix that does work: pass the options in the value that onChange delivers.

**Suggested fix:**

In Sources/NukeUI/LazyImage.swift, carry the current options inside the value passed to `onChange`, and compare only by the request, so the action receives the new view's options. Tried in the scratch copy: the 2 repro tests and the 24 existing LazyImageTests all pass.

```swift
private struct LazyImageOptions {
    var transaction: Transaction
    var pipeline: ImagePipeline
    var onStart: (@MainActor @Sendable (ImageTask) -> Void)?
    var onCompletion: (@MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void)?
}

/// Compared by the request alone; carries the options of the view it came from.
private struct LazyImageUpdate: Equatable {
    var context: LazyImageContext?
    var options: LazyImageOptions
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.context == rhs.context }
}

// body
.onChange(of: LazyImageUpdate(context: context, options: options)) {
    // The action is the previous view's closure, so take the options from the new value, not self.
    apply($0.options)
    viewModel.load($0.context?.request)
}

private var options: LazyImageOptions { .init(transaction: transaction, pipeline: pipeline, onStart: onStart, onCompletion: onCompletion) }
private func apply(_ o: LazyImageOptions) {
    viewModel.transaction = o.transaction; viewModel.pipeline = o.pipeline
    viewModel.onStart = o.onStart; viewModel.onCompletion = o.onCompletion
}
// onAppear(): apply(options) instead of the four assignments
```

Before merging, re-run the #969 body-update benchmark, since the onChange value is now a slightly larger struct. The equality check itself stays request-only.

Scope: this does not handle changing only the pipeline or closures without a request change. That case starts no load, and the next load or appear picks the new values up.


### D21. LazyImage does not reload when only the request's thumbnail options or scale change

_Severity: medium · user impact: medium · public API: yes · known: defects.md #28 · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/LazyImage.swift:206`

**Repro:** [NukeUITests/nukeui-swiftui--lazyimage-ignores-thumbnail-scale-changes.swift](NukeUITests/nukeui-swiftui--lazyimage-ignores-thumbnail-scale-changes.swift)

**What:** LazyImageContext.== compares only imageID, priority, processors and options. It ignores ImageRequest.thumbnail and ImageRequest.scale, even though both are part of MemoryCacheKey and change the image the pipeline produces. When a request changes only its thumbnail size (for example a cell growing from 16 px to 64 px) or its scale, the two contexts compare equal, onChange never fires, and the view keeps showing the old image. The CHANGELOG's 'Fix an issue where the image won't reload if you change only LazyImage processors or priority' has the same gap for thumbnail and scale.

**Expected:** Changing thumbnail maxPixelSize from 16 to 64, or scale from 1 to 2, starts a new request (onStart count 2) and shows a 64 px or scale-2 image.

**Actual:** onStart count stays at 1, no request starts, and the 16 px thumbnail (or the scale-1 image) stays on screen.

**Reproduction check:** Failed on all 3 iterations: 'changingTheThumbnailSizeReloads() ... Expectation failed: starts.value == 2' (line 60) and 'changingTheScaleReloads() ... Expectation failed: starts.value == 2' (line 86). The precondition passed: the first image is a 16 px thumbnail (line 55). No second request starts after the update.

**Refutation attempt (failed):**

I could not refute this. It is a real defect, reachable through the public API only.

Code: `LazyImageContext.==` (Sources/NukeUI/LazyImage.swift:206-219) first checks `isIdentical` and then compares only `imageID`, `priority`, `processors` and `options`. `ImageRequest.imageID` (Sources/Nuke/ImageRequest.swift:106) is `customImageID ?? originalImageID`, so it does not include `scale` or `thumbnail`. Both are public, settable properties stored on the request's Container. `MemoryCacheKey` (Sources/Nuke/Internal/ImageRequestKeys.swift) hashes and compares both, so they do change which image the pipeline produces. `body` reloads only through `.onChange(of: context)`, and `onAppear` does not run again, so an update that changes only the thumbnail or scale is dropped.

History and intent: the comparison started as `HashableRequest` (3f873153). `fb7d12de` ("Fix priority updates") added `processors`, which gave the CHANGELOG entry "Fix an issue where the image won't reload if you change only LazyImage processors or priority". The clear intent is to reload whenever the request would produce a different image. `35e951d2` ("Add type-safe imageID, scale, thumbnail keys") promoted scale and thumbnail from userInfo keys to first-class properties but only renamed `preferredImageId` to `imageID` in the comparison. The gap existed before as well, when these were userInfo keys, and I found nothing that documents it or says it is intended. No doc comment, DocC article or CHANGELOG entry says thumbnail or scale changes are ignored. A user writing `LazyImage(request:)` with a thumbnail sized from the view's layout would reasonably expect it to reload.

Repro validity: the test uses only public API (`LazyImage(request:)`, `.pipeline`, `.onStart`, `.onCompletion`) and the repo's real `ViewHost` window harness, which is the same one the existing LazyImageTests use. `@testable` is used only for test helpers (`MockDataLoader`, `Test.url`), not to reach internal paths.

Verification, run in a scratch copy at /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-thumb/Nuke on macOS. The repo itself was not modified.
- Unmodified sources: both `changingTheThumbnailSizeReloads` and `changingTheScaleReloads` fail with `starts.value == 2` (actual 1).
- With `scale` and `thumbnail` added to the comparison: both pass, including the check that the second image is 64 px on its longest side. All 24 existing LazyImageTests still pass, among them `noNewRequestWhenRequestIsUnchanged`, `newRequestStartedWhenProcessorsChange` and `newRequestStartedWhenPriorityChanges`.

So this is not a harness or mock artifact, and it is not platform behavior.

Impact: medium. The failure is silent, so no error is reported. A cell or view whose thumbnail size follows its layout (rotation, split view, window resize, Dynamic Type), or a view whose request scale follows `displayScale` (for example a macOS window moving between displays), keeps showing the stale low-resolution image until the view is rebuilt or its `id` changes. The workaround is `.id(...)` or changing the URL. The trigger (a request that changes only thumbnail or scale while the view stays alive) is less common than a URL change, but it is a normal way to use the thumbnail API.

**Suggested fix:**

In Sources/NukeUI/LazyImage.swift, `LazyImageContext.==`, add the two remaining image-affecting fields that `MemoryCacheKey` uses:

    return lhs.imageID == rhs.imageID &&
    lhs.priority == rhs.priority &&
    lhs.processors == rhs.processors &&
    lhs.options == rhs.options &&
    lhs.scale == rhs.scale &&
    lhs.thumbnail == rhs.thumbnail

`ThumbnailOptions` is already `Hashable`, and both comparisons are cheap scalar or struct compares that run after the `isIdentical` fast path, so the #969 fast path is not slowed down. Add the repro's two tests next to `newRequestStartedWhenProcessorsChange` in Tests/NukeUITests/LazyImageTests.swift, and add a CHANGELOG line such as "Fix `LazyImage` not reloading when only the request's `thumbnail` or `scale` changes".


### D22. FetchImage.cancel() leaves isLoading == true forever

_Severity: medium · user impact: low · public API: yes · known: defects.md #27 · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/FetchImage.swift:224`

**Repro:** [NukeUITests/nukeui-swiftui--fetchimage-cancel-leaves-isloading.swift](NukeUITests/nukeui-swiftui--fetchimage-cancel-leaves-isloading.swift)

**What:** cancel() cancels the pipeline task (which then 'guarantees that no more callbacks will be delivered') or the async task and its generation. It never clears isLoading. The only place isLoading goes back to false is handle(result:), which a cancelled load never reaches. A custom FetchImage view that shows a spinner while isLoading therefore spins until the next load or reset. isLoading is documented as 'Returns true if the image is being loaded.'

**Expected:** isLoading is false after cancel(), for both the pipeline-based and the async load.

**Actual:** isLoading stays true after cancel() on both paths.

**Reproduction check:** Failed on all 3 iterations: 'cancelEndsLoadingForAPipelineLoad() ... Expectation failed: !image.isLoading' (line 40) and 'cancelEndsLoadingForAnAsyncLoad() ... Expectation failed: !image.isLoading' (line 59). A separate probe (temporary, since removed) showed isLoading was still true 300 ms after the cancelled async action returned. On the pipeline path it was still true about 60 s later: the probe's DidCancelTask wait timed out because cancel landed before the data task started, and that timeout is a probe artifact.

**Refutation attempt (failed):**

The bug is real, and it happens on both paths. I could not refute it.

Code: FetchImage.cancel() in Sources/NukeUI/FetchImage.swift (lines 224-234) cancels imageTask and asyncTask and bumps loadGeneration. It never touches isLoading. Only three things set isLoading back to false: handle(result:), clearLoadingState() through reset(), and the cache-hit branch of load(). After cancel(), none of them can run. ImageTask.cancel() guarantees that no more callbacks arrive. The async path's result is dropped by the generation guard added in dc56dfdc (13.1.0).

Reproduced: I exported HEAD to the scratchpad, applied the macOS-only `SwiftUI.Color` fix to LazyImageTests that is already in the working tree, and ran the repro with xcodebuild (NukeUITests, macOS). Both tests fail with "Expectation failed: !image.isLoading", once for the pipeline load and once for the async load.

Is it intentional? The history says no:
- Originally cancel() ended with `if isLoading { isLoading = false }`.
- Commit f04147ee (Jan 2022, 10.7.1, CHANGELOG entry "Fix intermittent SwiftUI crash in NukeUI/FetchImage") removed it. Its message is "Remove isLoading change on dealloc from cancel". At the time, deinit called cancel(), so the goal was to stop publishing during dealloc. Removing the line also changed what an explicit cancel() does.
- deinit no longer calls cancel(). It calls imageTask?.cancel() and asyncTask?.cancel() directly, so the crash that removal fixed cannot come back.
- For the async path this is also a 13.1.0 regression. Before dc56dfdc, an action that honored cancellation (for example `try await pipeline.image(for:)` or Task.sleep) threw CancellationError. That reached handle(result:), which set isLoading to false. The generation guard now discards that result.
- The docs don't promise this state either. isLoading is documented as "Returns `true` if the image is being loaded." cancel() says only "Continues to display a downloaded image", which is about imageContainer, not isLoading.
- The existing test asyncLoadDeliversNoResultAfterCancel doesn't check isLoading. The reset variant of the same test does check `!image.isLoading`.

The repro is fair. It calls only public API (load, cancel, isLoading) on the main actor, the same way the existing FetchImageTests do. The suspended MockDataLoader and the AsyncGate only keep the load in flight. They are not what causes the result.

Impact is low:
- LazyImage calls viewModel.cancel() for `.onDisappear(.cancel)`, but onAppear calls load() again, and load() clears the stale flag through reset() or clearLoadingState(). Stock LazyImage users therefore don't see it.
- The documented FetchImage examples use reset() on disappear, not cancel().
- Who is affected: people who use FetchImage directly, call cancel() (for example from a Cancel button, or from onDisappear while the view stays visible or keeps its state), and show a spinner or "loading" UI based on isLoading. That UI stays in the loading state, with result == nil, until the next load() or reset().
- LazyImageState exposes the same isLoading, so a custom LazyImage content closure observed right after disappearing would also read true, but by then it is off screen.

**Suggested fix:**

Restore the line removed in f04147ee. It is safe now because deinit no longer calls cancel():

```swift
public func cancel() {
    imageTask?.cancel() // Guarantees that no more callbacks will be delivered
    imageTask = nil
    asyncTask?.cancel()
    asyncTask = nil
    loadGeneration &+= 1
    if isLoading { isLoading = false } // The cancelled load will never reach handle(result:)
}
```

This adds no extra publishes on the load() path. load() already calls reset() or clearLoadingState(), which sets isLoading to false before setting it back to true. Leave _progress and imageContainer as they are, to keep the "continues to display a downloaded image" behavior.

Add `#expect(!image.isLoading)` after cancel() in two tests: the existing asyncLoadDeliversNoResultAfterCancel, and a pipeline-path test that uses a suspended MockDataLoader. Add a CHANGELOG line: "Fix `FetchImage.isLoading` remaining `true` after `cancel()`".


### D23. loadImage(into:) shows a memory-cached progressive preview, then immediately clears it or replaces it with the placeholder

_Severity: medium · user impact: low · public API: yes · known: defects.md #26 · found by: nukeui-views_

**Where:** `Sources/NukeUI/ImageViewExtensions.swift:310`

**Repro:** [NukeUITests/nukeui-views--cached-preview-wiped.swift](NukeUITests/nukeui-views--cached-preview-wiped.swift)

**What:** ImageViewController.loadImage finds a preview in the memory cache, displays it, and doesn't return early because it is a preview. It then runs the placeholder step: `if let placeholder { display(placeholder) } else if isPrepareForReuseEnabled { imageView.nuke_display(nil) }`. That step overwrites the preview that was just shown. LazyImageView and FetchImage both keep the cached preview on screen while the final image loads.

**Expected:** The cached preview stays displayed while the final image loads.

**Actual:** With the default options, imageView.image is nil right after loadImage returns. With a placeholder set, the placeholder is shown instead of the preview.

**Reproduction check:** macOS, 3/3 iterations: both tests fail with `Expectation failed: imageView.image === preview.image`. With default options imageView.image is nil right after loadImage returns. With a placeholder, the placeholder image is shown instead of the preview. The one-shot iOS run fails the same way.

**Refutation attempt (failed):**

I could not refute the core claim. Its stated consequence ("empty until the final image arrives") holds only in one of the two paths.

Intent: commit ac40fc4f ("Store progressive images (previews) in memory cache", 2020, CHANGELOG #352) changed the memory-hit branch to display the cached image and return early only when `!image.isPreview`. The purpose was to show the cached preview and keep loading. The placeholder / `nuke_display(nil)` block that follows was never adjusted, and git blame shows it is older. Nothing documents or tests the current behavior. The docs promise "The default image view loading extensions also support displaying progressive previews". LazyImageView (LazyImageView.swift:308) and FetchImage (FetchImage.swift:147) both keep the cached preview, and so do their tests (memoryCachePreviewDisplayedThenFinalImage, memoryCachedPreviewIsDisplayedWhileLoading). The repro uses only public API: loadImage(with:options:into:), a public ImageContainer(isPreview:), and a custom pipeline. The mocks do not change the outcome.

Empirical check: I exported HEAD to a scratch copy (/private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-cached-preview) and ran on macOS. A recording ImageDisplaying view logged these synchronous sequences: ["preview","nil"] with default options and ["preview","placeholder"] with a placeholder. The two repro tests fail as claimed.

Mitigation that weakens the claim: TaskLoadImage.start() does its own memory lookup and sends a cached preview as a non-final value. For a NEW pipeline task, the preview therefore comes back through the progress callback one DispatchQueue.main.async hop later and is displayed again. Logs: ["preview","nil","preview"] and ["preview","placeholder","preview"]. In the common cell-reuse case after a cancelled download, the effect is a flash of blank or placeholder. When `options.transition` is set, the preview then fades back in (partial images use isFromMemory:false). The preview is not lost.

Case where the claim fully holds: when a request joins an in-flight task (task coalescing is on by default), AsyncTask.subscribe does not replay the last value and start() is not run again. The second view's cached preview is wiped and nothing is redelivered. I verified this: a second image view loading the same request while the first is in flight showed image == nil after 300 ms, with 0 previews delivered. It stays blank or on the placeholder until the next scan or the final image.

Preconditions: progressive decoding is opt-in (isProgressiveDecodingEnabled = false by default), and previews are only produced for progressive JPEG/GIF by default. isStoringPreviewsInMemoryCache is true by default. So this is a real, deterministic UI defect, but in a narrow opt-in scenario, and in the most common path it is a brief flicker. With isProgressiveRenderingEnabled=false the end result (no preview) matches the option; the synchronous preview display that ignores the option is only a minor wasted display.

The fix sketched below passes the two repros, the join test, and the existing ImageViewExtensionsTests, ImageViewLoadingOptionsTests, ImageViewIntegrationTests and ImagePipelineProgressiveDecodingTests suites (37 tests).

**Suggested fix:**

In ImageViewController.loadImage (Sources/NukeUI/ImageViewExtensions.swift ~310), track whether a cached preview was displayed and skip the placeholder/clear step in that case. Also only show the preview when progressive rendering is on:

    var isDisplayingPreview = false
    if let image = pipeline.cache[request] {
        if !image.isPreview {
            display(image, true, .success)
            completion?(.success(ImageResponse(container: image, request: request, cacheType: .memory)))
            return nil
        }
        if options.isProgressiveRenderingEnabled {
            display(image, true, .success)
            isDisplayingPreview = true
        }
    }
    if isDisplayingPreview {
        // keep the cached preview on screen while the final image loads
    } else if let placeholder = options.placeholder {
        display(ImageContainer(image: placeholder), true, .placeholder)
    } else if options.isPrepareForReuseEnabled {
        imageView.nuke_display(nil)
    }

Add tests for three cases: the synchronous state after loadImage returns, the join-in-flight case (a second view for the same request while the first is loading keeps the preview), and a placeholder not overriding a cached preview.


### D24. LazyImageView sets a newly assigned placeholder/failure view's visibility from imageView.isHidden (or always hides it) instead of from the view's actual state

_Severity: medium · user impact: low · public API: yes · found by: nukeui-views_

**Where:** `Sources/NukeUI/LazyImageView.swift:419 (setPlaceholderView: `newView.isHidden = !imageView.isHidden`) and Sources/NukeUI/LazyImageView.swift:455 (setFailureView: `newView.isHidden = true`)`

**Repro:** [NukeUITests/nukeui-views--review-lazyimageview-late-subview-visibility.swift](NukeUITests/nukeui-views--review-lazyimageview-late-subview-visibility.swift)

**What:** When a placeholder view is assigned, it is shown whenever the built-in imageView is hidden, as if that meant 'loading'. But imageView is also hidden after a failure, after reset(), and while a makeImageView view is displaying the image. A failure view is always inserted hidden, even when the view is currently showing a failure. handle(result:) un-hides the old failure view before calling onFailure, so choosing the failure image from the error inside onFailure (`view.failureImage = image(for: error)`) leaves the new failure view hidden and the view blank.

**Expected:** The docs say a placeholder is 'shown while the request is in progress' and a failure view is 'shown if the request fails', whenever they are assigned. So: a failure image set in onFailure is visible; a placeholder set after a failure, or while a custom view shows the image, stays hidden.

**Actual:** The failure image set in onFailure stays hidden, so nothing is displayed. A placeholder set after a failure is visible together with the failure view. A placeholder set after a load that a custom view displays is visible under that view. Repro fails on both macOS and iOS.

**Reproduction check:**

macOS and iOS, 3/3 iterations each (9 issues per platform).
- failureImageAssignedInOnFailureIsShown: `!failureView.isHidden` fails, so the failure view is hidden and nothing is displayed.
- placeholderAssignedAfterFailureIsHidden: `placeholder.isHidden` fails, so the placeholder is visible together with the failure view.
- placeholderAssignedWhileCustomViewDisplaysImageIsHidden: `placeholder.isHidden` fails, so the placeholder is visible under the custom view.

**Refutation attempt (failed):**

I could not refute the failure-view half of the claim. I could only partly refute the placeholder half.

Reproduced on macOS. I ran the repro from a `git archive HEAD` copy in the scratchpad, not the repo. Its three tests fail as described. Two more probes that only use public API also fail:
- `view.url = nil; view.failureImage = img` leaves `failureView.isHidden == true`, so the view is blank. With the lines in the other order, the image shows.
- `view.failureImage = img; view.url = nil; view.placeholderView = p` shows the placeholder and the failure view together.

Code path (Sources/NukeUI/LazyImageView.swift):
- `handle(result:)` un-hides the current `failureView` (a no-op if it is nil), then calls `onFailure`.
- `setFailureView` (line 455) always sets `newView.isHidden = true`. So a failure view assigned while the failure is showing stays hidden. That happens in `onFailure`, after a synchronous `url = nil` failure, or when the app swaps the failure image for a trait or theme change.
- The repro runs on the main actor, uses only public API and breaks no documented precondition. The mocks only supply a failing or succeeding load, so this is not a test artifact.

Mitigating factors:
- History: line 419 (`newView.isHidden = !imageView.isHidden`) came from PR #586 (commit 52a2fedc, CHANGELOG: "Fix an issue with placeholder not being shown by LazyImage when the initial URL is nil").
- It deliberately treats "no image shown" as "show the placeholder". The SwiftUI `LazyImage` default content also shows the placeholder after a failure. So a placeholder that appears when assigned after a failure is arguably intended.
- Even when visible, that placeholder sits at subview index 0, behind the failure view. The custom-view case (`makeImageView`) looks like an oversight in that proxy, but you only see it with a transparent or partial custom view, or a spinner placeholder.
- The documented pattern (class doc example, existing tests) sets the placeholder and failure views before loading, and that works.
- There is a workaround: assign one `failureView` up front (for example an image view) and change its image in `onFailure`.

Verdict: a real bug in what you see on screen. It needs an uncommon order of calls (failure view assigned after the failure), so impact is low. The placeholder half is weaker and partly by design.

**Suggested fix:**

Track the failure state explicitly instead of inferring it from `imageView.isHidden`:
- Add `private var isDisplayingFailure = false`.
- In `handle(result:)`, set it to true in the `.failure` branch before un-hiding the failure view or placeholder (so before `onFailure` runs). Set it to false in `reset(clearImage:shouldCancel:)` and in `display(_:isFromMemory:)`.
- In `setFailureView`, use `newView.isHidden = !(isDisplayingFailure && !showPlaceholderOnFailure)`.
- In `setPlaceholderView`, to keep the #586 initial-state behavior, use `newView.isHidden = !(imageView.isHidden && customImageView == nil && (!isDisplayingFailure || showPlaceholderOnFailure))`.

Add tests for:
- `failureImage` assigned in `onFailure` is visible.
- `url = nil` followed by `failureImage` shows the failure image.
- A placeholder assigned after a failure, or while a `makeImageView` view is showing the image, stays hidden.


### D25. ImagePrefetcher starts queued requests in reverse order at its default .low priority

_Severity: medium · user impact: medium · public API: yes · found by: prefetch-internals_

**Where:** `Sources/Nuke/Prefetching/ImagePrefetcher.swift:157`

**Repro:** [NukeTests/prefetch-internals--low-priority-prefetches-run-in-reverse.swift](NukeTests/prefetch-internals--low-priority-prefetches-run-in-reverse.swift), [NukeTests/prefetch-internals--review-low-priority-pipeline-work-runs-in-reverse.swift](NukeTests/prefetch-internals--review-low-priority-pipeline-work-runs-in-reverse.swift)

**What:** `_startPrefetching(with:)` enqueues the operation with `queue.add { ... }`, and `TaskQueue.add` always enqueues at `.normal`. The prefetcher then lowers it with `operation.priority = request.priority.taskPriority`. When a priority is lowered, `TaskQueue.operationPriorityChanged` (TaskQueue.swift:150-152) prepends the operation to the lower bucket, on the grounds that it was once higher priority. So every prefetch that can't start right away jumps ahead of the ones queued before it, and the queue runs LIFO instead of the FIFO that TaskQueue documents for work of the same priority. At `.normal` and `.high` the order is kept, which shows the reversal comes from adding at .normal and then lowering, not from a design choice. Impact: UICollectionView gives the prefetch index paths nearest to the viewport first, so the default prefetcher loads the farthest images first.

**Expected:** With the default configuration (maxConcurrentRequestCount 2), prefetching URLs [0...5] creates image tasks in the order [0, 1, 2, 3, 4, 5].

**Actual:** At .low and .veryLow the order is [0, 1, 5, 4, 3, 2]: the first two start right away and the rest are reversed. .normal and .high give the expected order. 5 out of 5 runs.

**Reproduction check:** Over 3 iterations, .low and .veryLow failed every time (6 of 6 cases) with `order.withLock { $0 } → [0, 1, 5, 4, 3, 2]`, where [0, 1, 2, 3, 4, 5] was expected. .normal and .high each ran 3 times and passed. The failure matches the claim. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-prefetch-internals-1.log

**Refutation attempt (failed):**

I couldn't refute it. The bug is real, it's a regression from Nuke 12, and the public API reaches it.

Mechanism, checked in the code:
- `ImagePrefetcher._startPrefetching(with:)` (Sources/Nuke/Prefetching/ImagePrefetcher.swift:149-155) calls `queue.add { ... }`.
- `TaskQueue.add` (Sources/Nuke/Pipeline/TaskQueue.swift:82-87) always enqueues at `.normal` and runs `drain()` right away.
- The prefetcher then sets `operation.priority = .low`. `operationPriorityChanged` (TaskQueue.swift:145-152) moves any operation whose priority went down to the front of the lower bucket.
- So every prefetch that can't start at once goes in front of the ones queued before it, and the bucket runs LIFO. TaskQueue's own doc comment promises "FIFO within the same priority".

Intent and history:
- The prepend rule came in with `TaskQueue` in edaf7978 ("Add TaskQueue", released in Nuke 13.0). Its tests (TaskQueueTests `decreasedPriorityGoesAheadOfExistingLowerPriorityItems`, `twoDecreasesPrependInOrder`) justify it as "A was once higher priority". A freshly added prefetch was never really higher priority; `.normal` is just the default of `add`.
- Before that commit, the prefetcher set `operation.queuePriority` before `queue.addOperation` on an `OperationQueue`, which is FIFO within one priority. So Nuke 12 started prefetches in the order given, and the TaskQueue migration changed that.
- Nothing in the CHANGELOG, the docs, or the commit messages presents LIFO as intended.
- Documentation/Nuke.docc/Performance/prefetching.md describes the exact scenario: UIKit asks to prefetch `[32-55]`, nearest item first. `.low` is the documented default priority.

Reproduced on macOS by running the tests in a scratch copy of HEAD (repo not modified):
- The agent's repro gives [0,1,5,4,3,2] at `.low` and `.veryLow`, and the expected order at `.normal` and `.high`.
- My own test uses only public API: `ImagePipeline` with a custom `DataLoading` that records URLs, `ImagePrefetcher(maxConcurrentRequestCount: 1)`, `startPrefetching(with: 32..<40)`. The data loader saw [32, 39, 38, 37, 36, 35, 34, 33] at `.low` and the right order at `.normal`. So neither `@testable` hooks nor the mock observer are involved.
- The same cause also hits the pipeline beyond the prefetcher. `AsyncTask.operation`'s `didSet` lowers the priority right after `dataLoadingQueue.add`. With `dataLoadingQueue` at 1 slot, six `.low` `ImageRequest`s reached the loader as [0, 5, 4, 3, 2, 1]; `.normal` kept the order. The decode, process and decompress queues use the same add-then-set-priority pattern.

This is Nuke's own scheduling. It isn't a platform behavior, a timing artifact of the test harness, or a misuse of the API.

Impact: with the default prefetcher, a batch loads the first `maxConcurrentRequestCount` items and then the rest farthest-first. All images still get prefetched, and a visible cell's own request at `.normal` still goes ahead of queued prefetches. So the harm is worse prefetch effectiveness and wasted bandwidth on far items during fast scrolling, not wrong results. It also reorders any app's `.low`/`.veryLow` requests once the data loading queue (6 slots) is full. I rate it medium: default configuration, a silent regression, but no correctness or data loss.

**Suggested fix:** Set the operation's priority before it is enqueued, instead of adding it at `.normal` and lowering it afterwards. In Sources/Nuke/Pipeline/TaskQueue.swift, change `add` to take a priority: `func add(priority: TaskPriority = .normal, _ work: ...) -> Operation { let op = Operation(queue: self); op.priority = priority /* node is nil, so operationPriorityChanged is a no-op */; op.work = work; enqueue(op); return op }`. Then in ImagePrefetcher.swift:149 call `queue.add(priority: request.priority.taskPriority) { ... }` and delete the `operation.priority = ...` line. For the pipeline, pass the task's current priority at the call sites (`pipeline.configuration.dataLoadingQueue.add(priority: priority) { ... }` in TaskFetchOriginalData, TaskFetchOriginalImage, AsyncPipelineTask.decode, and TaskLoadImage process/decompress/encode), and keep `AsyncTask.operation`'s `didSet` only as a fallback. The prepend-on-lower rule in `operationPriorityChanged` stays as it is, because it is correct for operations that really did wait at a higher priority. Add a regression test: a prefetcher at `.low` with `maxConcurrentRequestCount: 1`, prefetch 32..<40, and expect the data loader to see 32..<40 in order. Add a matching one for `.low` pipeline requests behind a 1-slot `dataLoadingQueue`.

- Also reported by **prefetch-internals** (confirmed): Pipeline queues run work below .normal priority in reverse order (AsyncTask adds the operation, then lowers its priority)

### D26. GaussianBlur with radius >= ~1544 returns a corrupted near-black image and allocates GBs of scratch memory

_Severity: medium · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift:58`

**Repro:** [NukeTests/processing-graphics-encoding--gaussian-blur-large-radius-corrupts-output.swift](NukeTests/processing-graphics-encoding--gaussian-blur-large-radius-corrupts-output.swift)

**What:** The kernel is radius*3*sqrt(2π)/4 pixels on a side. Once kernel² × 255 overflows Int32 (a kernel of 2903 or more, so a radius of about 1544), vImageBoxConvolve_ARGB8888 still returns kvImageNoError but produces garbage. At the same threshold its scratch buffer jumps from about 16 MB to 2.5 GB for a 1000x1000 image. At radius 10000 it reaches 7 GB even for a 40x40 image; I measured 2.8 GB resident, and an unbounded radius (100 000) passed 17 GB before I killed it. Nothing checks the vImage error codes (lines 80–82), so the corrupted image is returned as a success and cached. A fix could clamp the kernel (with edge extension, anything beyond twice the image size is equivalent) and check vImage_Error.

**Expected:** Blurring a solid-colour image with any radius leaves every pixel unchanged, with bounded memory.

**Actual:** A 40x40 solid blue image comes back near black: about (4, 7, 15) instead of (4, 51, 255), a max per-channel difference of about 240, at radius 1600 and 2000. Radius 1500 (kernel 2821) is still correct.

**Reproduction check:** Radius 1600 and radius 2000 failed `maxDifference <= 1` in all 3 iterations (macOS). A probe suite I added temporarily printed the first pixel for each radius. 1400, 1500 and 1540 gave (4,51,255,255), which is correct. 1550 gave (4,6,8,255) and 1600 gave (4,7,15,255), both corrupt. A standalone vImage probe queried the scratch size with kvImageGetTempBufferSize. For a 1000x1000 image: 15.7 MB at radius 1500, 2462 MB at 1544, 2621 MB at 1600. For a 40x40 image: 0.18 MB at 1500 and 7089 MB at 10000. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-3.log

**Refutation attempt (failed):**

I couldn't refute this. I reproduced it both at the vImage level and through the public API alone. The repro was a scratch SPM package that depends on Nuke by path and calls ImageProcessors.GaussianBlur(radius:).process(_:) on an NSImage, with no @testable import. The Nuke repo was not modified.

Results on a solid blue image, sampling the centre pixel:
- Radius 1500 (kernel 2821) and radius 1543 (kernel 2901) come back unchanged at (4, 51, 255).
- Radius 1544 (kernel 2903) gives (4, 6, 7), radius 1600 gives (4, 7, 15) and radius 2000 gives (4, 16, 11).
- A standalone copy of the three vImageBoxConvolve_ARGB8888 calls returns error 0 on all three passes, so the image comes back as a success.
- Only the channel whose value is 4 survives, because 4*k^2 still fits in an Int32. The 51 and 255 channels wrap. That is consistent with vImage's Int32 accumulator overflowing once kernel^2*255 > 2^31, which puts the last safe kernel at 2901.

Memory:
- The scratch size vImage reports (kvImageGetTempBufferSize) at 40x40 goes from 0.19 MB at kernel 2901 to 171 MB at kernel 2903.
- At 1000x1000 it goes from 15.7 MB at radius 1500 to 2.6 GB at radius 1600, though only about 100 MB of that became resident.
- Radius 10000 on a 40x40 image had a 2.84 GB peak footprint and took 7.2 s, so the 2.8 GB claim holds.
- A 3000x3000 image at radius 1600 had a 295 MB peak and was also corrupted.

Why this counts as a real defect:
- The radius is documented only as ">= 0, where 0 is the identity". No upper bound is documented or enforced.
- The overflow itself is in vImage, but Nuke picks the kernel size and doesn't check the return codes.
- This is a regression from Nuke 12. Before commit 428828e0 (the #308 vImage rewrite, shipped in 13.0.0) the processor used CIGaussianBlur, which handles any radius correctly.
- The corrupted output is returned as a success, so the pipeline caches it under a valid key.

I rate the impact low rather than medium because a radius of 1544 px or more is unusual; typical values are 8 to 100. It's still reachable in apps that derive the radius from image size, for example radius = width / 2 on a 4000 px photo. On iOS, the multi-GB scratch allocation at very large radii could get the app killed for exceeding its memory limit.

A correction to the suggested fix: clamping only to twice the image size is not enough. For any image wider than about 1450 px, twice the size is still above the 2901 overflow limit, as the 3000x3000 case shows. It's also only approximately equivalent under edge extension, because the result keeps moving slowly toward the average of the edge pixels as the kernel grows. And checking vImage_Error alone would not catch this, because vImage returns kvImageNoError here.

**Suggested fix:**

In CGImage.blurred(radius:) in Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift, after the kernel is made odd, cap it at the Int32 overflow limit and at the image size, then keep it odd:
  let maxKernel = min(2901, UInt32(2 * max(width, height) + 1))  // 2901^2 * 255 < Int32.max
  kernelSize = min(kernelSize, maxKernel) | 1
Also check the result of each of the three vImageBoxConvolve_ARGB8888 calls, e.g. `guard err == kvImageNoError else { return nil }`, so that allocation failures surface as nil. That check wouldn't catch this overflow, but it's cheap. If blurs above the cap need to stay faithful, downscale by a factor of ceil(kernel / 2901), blur, then scale back up; the cap alone keeps memory bounded and the output correct. Add a regression test: a solid colour stays unchanged at radius 1544, 2000 and 10000, and a 2000x2000 image at radius 2000 isn't corrupted.


### D27. macOS: ThumbnailOptions(size:contentMode:) sizes the thumbnail of an EXIF-rotated image against the stored pixels, so it comes out too large

_Severity: medium · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Internal/Graphics.swift:541`

**Repro:** [NukeTests/processing-graphics-encoding--review-macos-thumbnail-ignores-orientation.swift](NukeTests/processing-graphics-encoding--review-macos-thumbnail-ignores-orientation.swift)

**What:** getMaxPixelSize(for:options:) computes kCGImageSourceThumbnailMaxPixelSize from the stored PixelWidth/PixelHeight. It turns the target for the orientation only under #if canImport(UIKit). With createThumbnailWithTransform, which is on by default, Image I/O turns the thumbnail upright on every platform, macOS included. So on macOS the fit or fill is computed against the portrait frame as stored, while the image returned is the landscape one as displayed. Verified: on iOS the same request returns 320x240.

**Expected:** right-orientation.jpeg is stored as 480x640 and displayed as 640x480. Fitted into 320x1000 px, the thumbnail should be 320x240. Filled into 400x100 px, it should be 400x300.

**Actual:** On macOS the fit gives 427x320, wider than the 320 px requested, and the fill gives 533x400.

**Reproduction check:** On macOS, 3/3 iterations: the fit into 320x1000 px gave 427x320 (expected 320x240), and the fill into 400x100 px gave 533x400 (expected 400x300). The same suite passed 3/3 on a private iOS 26.5 simulator, which confirms the bug is macOS-only. Logs: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-11.log and repro-processing-graphics-encoding-11-ios.log

**Refutation attempt (failed):**

I could not refute this. It is a real macOS defect, reachable through public API.

1) The code matches the report. In getMaxPixelSize (Sources/Nuke/Internal/Graphics.swift:540-547), kCGImageSourceThumbnailMaxPixelSize is computed from the stored PixelWidth/PixelHeight. The target is rotated for the EXIF orientation only under `#if canImport(UIKit)`.

2) The guard was not a deliberate macOS choice. `git blame` puts it in fda68375 ("Fix tests and typos", 2023). At that point `CGSize.rotatedForOrientation` was declared `private` inside `#if os(iOS) || os(tvOS) || os(watchOS)`, so the guard was only there to make macOS compile. The helper is now cross-platform (Graphics.swift:302), and AnimatedImageSource.swift:261 already calls it on every platform.

3) Image I/O behaves the same on macOS. I ran a standalone script on this Mac against Tests/Resources/right-orientation.jpeg (stored 480x640, orientation 6) with Nuke's default flags, including kCGImageSourceCreateThumbnailWithTransform. Max pixel size 320 returned 320x240, 427 returned 427x320, 400 returned 400x300 and 533 returned 533x400. The thumbnail comes back upright on macOS too.

4) The arithmetic confirms the numbers. Aspect-fit into 320x1000 without rotating the target: the scale is min(320/480, 1000/640) = 0.667, giving 320x427, so the max is 427 and the result is 427x320, wider than the 320 px asked for. With the rotation (iOS): 1000x320 gives a scale of 0.5 and a max of 320, so 320x240. Aspect-fill into 400x100 without rotation gives a max of 533 (533x400); with rotation, 400x300.

5) The expected behavior is already asserted. ImageDownsampleTests.resizeImageWithOrientationRight checks exactly 320x240 for this fixture and request. It sits inside `#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)`, because it also checks UIImage.imageOrientation, so macOS never exercised this path.

6) The repro is not misusing anything. It calls only the public `ThumbnailOptions(size:unit:contentMode:)` and `makeThumbnail(with:)`, and the same path runs for pipeline requests that use `ImageRequest.thumbnail`.

Impact is low. The image is correctly oriented, just larger than requested: about 1.33x per side for 4:3 camera photos (orientation 6 is common for phone photos), with matching extra memory. An aspect-fit result can go past the requested bounds. There is no crash and nothing looks wrong on screen, since views scale the image.

**Suggested fix:**

In getMaxPixelSize (Sources/Nuke/Internal/Graphics.swift:541-543), rotate the target whenever Image I/O will return an upright thumbnail, not only on UIKit. Replace the `#if canImport(UIKit)` block with:

```swift
#if canImport(UIKit)
    targetSize = targetSize.rotatedForOrientation(orientation)
#else
    if thumbnailOptions.createThumbnailWithTransform {
        targetSize = targetSize.rotatedForOrientation(orientation)
    }
#endif
```

UIKit keeps rotating either way, because with the transform off the UIImage still carries the EXIF orientation. On macOS with the transform off, NSImage shows the raw stored pixels, so the target should not be rotated there. Then move the 320x240 size assertions of resizeImageWithOrientationRight, and the proposed 400x300 aspect-fill case, out of the UIKit-only `#if` so they also run on macOS. The imageOrientation checks stay under UIKit.


### D28. imageTaskCreated hands the delegate an ImageTask whose response can't be awaited yet (crash)

_Severity: medium · user impact: medium · public API: yes · known: defects.md #19 · found by: task-engine_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline.swift:183`

**Repro:** [NukeTests/task-engine--task-created-before-wired.swift](NukeTests/task-engine--task-created-before-wired.swift)

**What:** `makeStartedImageTask` calls `imageTaskCreated(task, isDataTask:)`, which calls the delegate synchronously, before it assigns `task._task` (ImagePipeline.swift:183-184). `_task` is a `nonisolated(unsafe)` implicitly unwrapped optional whose doc comment says it is "set once during creation, before the task is handed to anyone". A delegate that starts a Task from `imageTaskCreated` to await `task.response` (for example for logging or analytics) races the unsynchronized write. When the spawned Task wins, the `response` getter traps on the nil IUO at ImageTask.swift:165. Otherwise it is still a data race.

**Expected:** Every ImageTask handed to the delegate can be awaited: `task._task` is non-nil when `imageTaskCreated` runs, and awaiting `response` from a Task spawned there returns the outcome.

**Actual:** `task._task` is nil during `imageTaskCreated`, which the repro checks directly and deterministically. Awaiting `response` from a detached Task started there crashes with "ImageTask.swift:165: Fatal error: Unexpectedly found nil while implicitly unwrapping an Optional value". The repro reproduces the crash by having the delegate do 0.5 s of synchronous work after spawning the Task.

**Reproduction check:** taskIsWiredWhenTheDelegateReceivesIt() fails on all 3 repetitions with `delegate.wasWired.value == true → false` at line 54 (log repro-task-engine-1-wired.log). awaitingResponseFromImageTaskCreatedDoesNotCrash() crashes the xctest process with "Nuke/ImageTask.swift:165: Fatal error: Unexpectedly found nil while implicitly unwrapping an Optional value" in 3 of 3 separate xcodebuild runs (repro-task-engine-1-crash-{1,2,3}.log). A crash ends the run, so each crash run gives only one iteration. The combined suite run (repro-task-engine-1.log) crashed the same way, and both tests were marked failed because they run in parallel.

**Refutation attempt (failed):**

I could not refute it. The bug is real and reachable through the public API.

The code breaks its own invariant. In `makeStartedImageTask` (Sources/Nuke/Pipeline/ImagePipeline.swift:183-184), `imageTaskCreated(task, isDataTask:)` calls the public delegate synchronously, and only after that does it assign `task._task = Task { ... }`. The doc comment on `_task` (Sources/Nuke/ImageTask.swift:247-251) says it is "Set once during creation, before the task is handed to anyone, then read-only from the `response` getter, so it needs no synchronization". Commit 50eb4af5 kept `nonisolated(unsafe)` on that basis, but the delegate is someone the task is handed to.

Nothing in the public contract rules out using the task. The `response` doc says: "It is safe to await the response more than once and at any point in the task lifetime". The delegate doc only says `imageTaskCreated` is "called immediately, in the context that created the task". The CHANGELOG's own example says "You can capture the task instance here to change priority later, etc". Nothing tells a delegate not to await `response`, or pass the task to another thread, from this callback.

It does not depend on the repro's timing tricks. I confirmed it three ways in a copy of HEAD in the scratchpad, without touching the repo:
1. The repro test crashes as described: ImageTask.swift:165, "Unexpectedly found nil while implicitly unwrapping an Optional value".
2. A delegate with no sleep, `Task.detached { _ = try? await task.response }`, is flagged by the scheme's Thread Sanitizer on the first task. It reports a data race between the write in `makeStartedImageTask` and the read in the `ImageTask.response` getter.
3. A standalone SwiftPM executable using only the public API (no `@testable`, no TSan, no sleeps) has a delegate whose `imageTaskCreated` just does `Task { _ = try? await task.response }`. In both debug and `-c release` it crashes on every run (exit 133 / SIGTRAP, same fatal error in debug), always within the first 2,000 tasks, 5 of 5 release runs.

The ordering has been there since Nuke 12 (commit 37a9b7038) and shipped in the 13.x tags. It is not a mock, ImageIO or URLSession artifact.

The call order has a reason: "Important to call it before `imageTaskStartCalled`", and ImagePipelineObserver's test expectations assume `.created` comes before `.started`. So simply swapping the two lines would let `imageTaskDidStart` race ahead of `imageTaskCreated`. That explains the order, but it does not make the current behavior correct.

Impact is medium. Only apps with a custom delegate that awaits `response`, or passes the task to another thread, from `imageTaskCreated` are affected. For those apps the result is a hard crash in production, and the rate is high.

**Suggested fix:**

Publish `_task` before handing the task to the delegate, and hold off the start until the delegate returns, only on the custom-delegate path. The default-delegate and data-task paths stay as they are, so they cost nothing extra:

```swift
nonisolated func makeStartedImageTask(...) -> ImageTask {
    let task = ImageTask(...)
    guard !isDataTask && !isDefaultDelegate else {
        task._task = Task { @ImagePipelineActor in
            await withUnsafeContinuation { c in task._continuation = c; self.startImageTask(task, isDataTask: isDataTask) }
        }
        return task
    }
    let created = OneShotGate() // OSAllocatedUnfairLock<(isOpen: Bool, waiter: UnsafeContinuation<Void, Never>?)>
    task._task = Task { @ImagePipelineActor in
        await created.wait()   // keeps imageTaskCreated strictly before imageTaskDidStart
        return await withUnsafeContinuation { c in task._continuation = c; self.startImageTask(task, isDataTask: false) }
    }
    delegate.imageTaskCreated(task, pipeline: self)  // _task is set and visible here
    created.open()
    return task
}
```

Any Task spawned in the delegate, and any thread the task is passed to through a lock, then sees `_task` through a happens-before edge, so the `_task` doc comment becomes true. Add a regression test: a delegate that awaits `task.response` from a `Task` spawned in `imageTaskCreated`, looped a few thousand times under TSan. Keep the existing `.created`-before-`.started` observer assertions.

An alternative is to move `imageTaskCreated` onto the actor just before `imageTaskDidStart`. That changes the documented "called immediately, in the creating context" behavior and breaks `cancelFromTaskCreated`-style usage, so the gate is the smaller change.


### D29. A store whose last player is released while a frame is landing drops every frame it holds

_Severity: low · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:486`

**Repro:** [NukeUITests/animated-frames-view--release-during-decode-drops-frames.swift](NukeUITests/animated-frames-view--release-during-decode-drops-frames.swift)

**What:** didDecode ends with evict(memberWindows()). evict only spares an idle store when members.isEmpty. A released player's Member entry (a nil weak reference) stays in members until the deferred sweep on the next turn, because deinit can only call setNeedsRebalance(). When the decode's continuation runs before that sweep, members is non-empty and there are no windows, so every frame is evicted, including the one just decoded. This happens when the decode finished while the main thread was busy releasing cells. The repro makes the ordering deterministic with a main-actor decoder (which the protocol docs allow) that releases the player inside the job that delivers the frame.

**Expected:** "The frames outlive the players holding them: a cell that scrolls off screen and comes back finds them still in memory". evict's own comment says "An idle store keeps everything". The store should hold all 4 frames.

**Actual:** store.decodedFrameCount(in: 0..<4) == 0 and pool.totalCost == 0, so a view that comes back decodes the whole animation again.

**Reproduction check:** macOS, 3 of 3 iterations: store.decodedFrameCount(in: 0..<4) → 0 (expected 4) and pool.totalCost → 0 (expected 16384), with pool.playerCount == 0. Same on the iOS simulator.

**Refutation attempt (failed):**

I could not refute this. The defect is real and I reproduced it through the public API with the default Image I/O actor decoder, not only with the repro's main-actor decoder.

Code (HEAD 2c2b23f6, Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift):
- `evict(_:)` (line 375–376) begins with `guard !members.isEmpty, !frames.isEmpty`. Its doc comment says "An idle store keeps everything for a view that comes back on screen".
- Every other place that decides whether a store is idle counts live weak refs: `isIdle` checks `memberCount == 0`, and `memberCount` counts non-nil players. Only `evict` looks at the raw `members` array.
- `AnimatedImagePlayer.deinit` can only call `pool.setNeedsRebalance()`, which queues a main-actor Task. Until the sweep runs, the store keeps a `Member` whose player is nil.
- When a decode's main-actor continuation is already queued ahead of that Task, `didDecode` runs `evict(memberWindows())`. At that point `members` is non-empty but there are no windows, so every frame is dropped, including the one that just landed.

Of the paths that call `evict`, only `didDecode` can see stale members. `didUpdateWindow` is always called by a live player, and `setAllotment` only runs after `rebalance()` has swept. The code dates from commit 0a2ab073 ("Share the decoded frames…"). Nothing in the commit history, the CHANGELOG or the docs says dropping the frames here is intended. AnimatedImages.md (Sharing) promises the frames outlive the players.

Verification: I exported HEAD to the scratchpad and ran it on macOS through xcodebuild. The test used the public `AnimatedImagePlayer(source:)` (shared pool, real display-link clock, the default actor decoder) with a 40-frame 600×600 GIF. It called play(), waited until 5 frames were decoded, then set the player to nil while a decode was in flight.
- Instrumentation printed "didDecode with members=1 live=0 frames=6", then "sweep frames=0".
- The store ended with 0 frames and `pool.totalCost` was 0.
- This happened both with a 0.1 s main-thread block and without one, so the race is easy to hit.
- Control: releasing the player after the fill had finished, with no decode in flight, kept all 40 of 40 frames.

Impact is low:
- When an AnimatedImageView leaves the window, `updatePlaybackState` sets `keepsFullBuffer = false`. The resulting rebalance already cuts the store to the 2-frame idle window before the player is released. For a cell that scrolls off, the bug can therefore lose at most about 2 frames.
- More is lost only when a player is released while it is still active and its animation is still filling for the first time. Examples: a visible view or SwiftUI AnimatedImage switched to a different image, an app-owned player released while playing, or an auto-downsampling rebuild.
- The only cost is re-decoding those frames (CPU, and the poster showing a little longer) if the same animation shows up again while ImageCache still holds it. What is displayed is never wrong.
- The report's framing ("the main thread was busy releasing cells") overstates how common this is, but the defect itself is real and reachable.

**Suggested fix:**

In AnimatedImageFrameStore, make eviction treat a store with no live members as idle, instead of relying on the raw `members` array:

    private func evict(_ windows: [MemberWindow]) {
        // `windows` holds only live members: a released player's entry stays
        // in `members` until the next sweep.
        guard !windows.isEmpty, !frames.isEmpty else { return }
        ...
    }

Also change `reclaim()` to `if isIdle { removeAllFrames() } else { evict(memberWindows()) }`, so an effectively idle store that still has unswept entries is still reclaimed whole when the pool is over its limit. A narrower alternative: in `didDecode`, skip `evict` when `liveMembers.isEmpty`, since `pool?.reclaimIfNeeded()` already handles idle stores through `isIdle`. Add the writer's repro (a main-actor decoder that releases the player inside the final decode) as a regression test. It should expect `decodedFrameCount(in: 0..<4) == 4` after the deferred sweep.


### D30. windowLength over-counts a paused member, holding the playing member below its read-ahead

_Severity: low · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:337`

**Repro:** [NukeUITests/animated-frames-view--idle-member-shrinks-active-window.swift](NukeUITests/animated-frames-view--idle-member-shrinks-active-window.swift)

**What:** windowLength binary-searches the largest window "such that the windows of every member together fit in the allotment", but it measures every playhead with the same length. A member nobody is watching (keepsFullBuffer false) only ever holds 2 frames. Example: a 20-frame animation in a 5-frame pool. Player A plays at frame 0 and wants 3; player B is paused at frame 10 and wants 2. leastDemand is 5 and the pool grants 5. windowLength then asks whether windows of 3 at BOTH playheads fit (6 > 5), settles on 2, and A holds 2 frames, short of the read-ahead, while one allotted frame goes unused. This is a realistic setup: the same sticker twice in a list with one copy scrolled out and paused on a different frame.

**Expected:** The playing player gets readAheadFrameCount + 1 (3) frames, since windows of 3 + 2 fit the 5-frame allotment the pool granted for exactly that.

**Actual:** playing.diagnostics.bufferCapacity == 2

**Reproduction check:** macOS, 3 of 3 iterations: playing.diagnostics.bufferCapacity → 2 (expected 3). The preconditions passed: store.allotment == 5 frames and the paused player's capacity == 2. Same on the iOS simulator.

**Refutation attempt (failed):**

I could not refute it. I ran the repro on a copy of the worktree commit (d9eb6690) in the scratchpad with xcodebuild, macOS and CODE_SIGNING_ALLOWED=NO. It fails as described: the pool grants 5 frames, windowLength is 2, and the playing player's bufferCapacity is 2.

Why it happens: leastDemand and demand both go through claimedFrameCount. That function sizes each playhead by what the members at that playhead want, so a member nobody is watching (keepsFullBuffer false, wantedFrameCount 2) counts as 2. The pool then grants exactly that union: 3 + 2 = 5 frames. windowLength divides the grant differently. At AnimatedImageFrameStore.swift:347 it tests `unionSize(of: playheads, length: { _ in middle })`, which gives every playhead the same length. A window of 3 at both playheads is 6 frames, which is more than 5, so it settles on 2. The playing member gets 2 frames and one granted frame is never used. The two sides disagree, and nothing says that is deliberate:
- The claimedFrameCount doc says it counts playheads "the way windowLength goes on to divide the share the pool hands back".
- The windowLength doc says "the windows of every member together fit in the allotment", and a member nobody is watching only ever holds 2.
- Commit e6b3d3f7 changed both demands to a union over playheads without accepting this gap. The same mismatch existed before that commit too.

What users are promised: AnimatedImages.md says a windowed animation's player "holds the frame on screen and the two after it", and the read-ahead of 2 is there to "absorb a slow decode or a busy core". Here the playing player gets a read-ahead of 1.

Reachable through public API with default settings. Two views (AnimatedImageView or AnimatedImage) show the same AnimatedImageSource, which ImageCache hands out as one shared instance. One view leaves the window, for example a cell kept alive off screen, or it is hidden. The view then sets keepsFullBuffer to false, and that player stays parked on its frame. The other view keeps playing, and within about 3 frames the two playheads are apart. The animation also has to be played from a window rather than held whole, which is the usual case for large GIFs, or when other animations are sharing the pool. A player that was created and seeked but never played gets there as well, using only public calls.

It also happens without any memory pressure. I added a variant with a pool of 1000 frames where the playing player sets Options.maxBufferSize to 5 frames. That is the documented way to keep an animation windowed "however much room the pool has". The grant is again 5 frames, windowLength is 2 and bufferCapacity is 2. A control with the playing player alone in a 5-frame pool gets 3, as expected.

The repro is not misusing anything. The internal init with a ManualClock and a private pool only makes the run deterministic; it does not create the behaviour. This is Nuke's own arithmetic, not ImageIO or UIKit.

Impact is low. Playback continues, but the next frame has one frame's duration to decode instead of two, so stalls under load become more likely. Also, one frame of the pool budget sits reserved and unused while other animations could use it.

**Suggested fix:** In AnimatedImageFrameStore.windowLength (Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:331-354), size each playhead the way claimedFrameCount does rather than using one uniform length. Before the binary search, build the per-playhead lengths once, e.g. `var wanted: [Int: Int] = [:]; for p in liveMembers { wanted[p.currentFrameIndex] = max(wanted[p.currentFrameIndex] ?? 0, p.wantedFrameCount) }`. Take playheads from `wanted.keys.sorted()`, and change the test to `unionSize(of: playheads, length: { min(middle, wanted[$0] ?? middle) }) <= capacity`. (`claimedFrameCount(upTo: middle) <= capacity` is the same thing, but it walks the members on every search step.) While the animation is windowed, every real window is 2 or 3 frames, so clipping each window at the next playhead in unionSize stays exact. Add a regression test: a 20-frame animation in a 5-frame pool, with one playing player at frame 0 and a never-played player seeked to frame 10, should give the playing player bufferCapacity 3. Add a second case with an ample pool where the playing player sets maxBufferSize to 5 frames.


### D31. A paused copy elsewhere in an animation inflates its demand; the pool grants a share the store can't use and starves an animation that would fit whole

_Severity: low · user impact: medium · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:253`

**Repro:** [NukeUITests/animated-frames-view--idle-member-inflates-demand.swift](NukeUITests/animated-frames-view--idle-member-inflates-demand.swift)

**What:**

demand counts each playhead's window as reaching the next playhead. With a paused member (capped at 2 frames) the union is less than the whole animation but more than the store can hold: short of the whole animation, bufferCapacity(windowLength:) caps every window at the read-ahead. The pool treats demand as "hold it whole" and grants it. Example with an 18-frame pool:
- Animation S (20 frames): A plays at frame 0, B is paused at frame 10. least = 5, demand = 12.
- Animation O (13 frames): least = 3, demand = 13.
S is given 12 frames but can hold only 3 + 2. O, which the remaining 10 frames would have held whole, is played out of a 3-frame window and re-decoded on every loop.

**Expected:** O is held whole (bufferCapacity 13). The pool "holds as many of them whole as fit", and budget between least and demand "buys nothing".

**Actual:** single.diagnostics.bufferCapacity == 3, and after filling the pool holds 8 of its 18 frames.

**Reproduction check:** macOS, 3 of 3 iterations: single.diagnostics.bufferCapacity → 3 (expected 13), and after waitUntilFull pool.totalCost → 32768 (8 frames of an 18-frame pool). The preconditions passed: S allotment == 12 frames, and the two S capacities sum to 5. Same on the iOS simulator.

**Refutation attempt (failed):**

I could not refute this. It is a real arithmetic defect in `AnimatedImageFrameStore.demand`, and it is worse than the report says.

**Cause.** `claimedFrameCount(upTo:)` (AnimatedImageFrameStore.swift:277-285) uses `unionSize(of:length:)`. That function assumes a window stops at the next playhead because the next window carries the coverage on. The assumption only holds when every window is the same length, which is true in `windowLength`'s binary search. `demand` passes a different length for each playhead: the whole animation for a playing member, and `idleFrameCount` (2) for a member with `keepsFullBuffer == false`. So a playing member at frame 0 of a 20-frame animation and an idle member at frame 10 count as min(20,10) + min(2,10) = 12 frames. The real union is 20.

**Why 12 frames is useless.** `bufferCapacity(windowLength:)` (AnimatedImagePlayer.swift:252-256) caps any window short of the whole animation at the read-ahead (3). So a share of 12 frames buys 3 + 2 frames. That breaks the store's own doc comment: "these are the only two amounts the pool hands out … anything in between buys nothing". It also breaks AnimatedImages.md: "One that fits in memory is decoded exactly once and kept" and "holds as many of them whole as the rest allows".

**History.** This is a regression from e6b3d3f7 ("Measure what a store needs in playheads, not in members"). Before that commit, demand was min(frameCount, sum of wanted) = min(20, 22) = 20, so the store was held whole. The commit meant to stop coincident playheads from over-claiming. Nothing in the commit message, the CHANGELOG or the docs makes this undercount intentional.

**Verified.** I ran the tests on macOS in a scratch copy of the writer's worktree (the repo was not touched), in `scratchpad/refute-b4`:
1. The writer's repro fails as described: S has allotment 12, demand 12 and least 5; A holds 3, B holds 2, O holds 3; the pool holds 8 of 18 frames.
2. It happens with no contention at all. One 20-frame animation in a 40-frame pool, next to a copy that was played, seeked to frame 10, paused and set to `keepsFullBuffer = false` (what `AnimatedImageView.updatePlaybackState` and SwiftUI `AnimatedImage.onDisappear` do when a view leaves the window). The playing copy gets allotment 12 and bufferCapacity 3, and the pool holds 5 of 40 frames.
3. After the playhead met the idle copy, the store was held whole (20). An unrelated rebalance (a 2-frame sticker appearing) then dropped it to allotment 9 and bufferCapacity 3, and the store's decoded frames fell from 20 to 5.

**Order-dependent.** When the playing player became whole before the other copy moved away, `rebalanceIfNeeded` returns early and the store stays whole. It also recovers each loop once the playhead reaches the idle copy's frame. But any pool-wide rebalance with the playhead behind that frame drops it again, and creating a player, a view scrolling on or off screen, or a player being released each trigger one.

**No API misuse.** The repro uses the internal init only to inject a pool and a ManualClock. The same arithmetic runs with `.shared` through the public paths:
- `AnimatedImagePlayer(source:options:)`, then `seek(toFrame:)` and `play()`;
- `AnimatedImageView` or `AnimatedImage` leaving the window.

A likely case: a chat with repeated copies of one sticker, where some cells are out of the window and paused at other frames while the visible copies play. Those visible copies are windowed and re-decode every frame on every loop, even though memory is free. That is the headline "twenty copies of a sticker cost one sticker" case.

**Impact.** Wasted CPU and battery: animations that fit are re-decoded, and decoded frames are dropped. There is no crash and nothing is drawn wrong, so medium rather than high.

**Suggested fix:**

In `AnimatedImageFrameStore` (around line 253), make `demand` return one of the two amounts the pool is meant to deal in, instead of a partial union that the players' `bufferCapacity` can't use.

```swift
var demand: Int {
    // A window short of the whole animation is capped at the read-ahead, so the
    // only amount worth asking for beyond leastDemand is the whole animation.
    liveMembers.contains { $0.wantedFrameCount >= frameCount }
        ? frameCount * bytesPerFrame
        : leastDemand
}
```

With a share of `frameCount * bytesPerFrame`, `windowLength` returns `frameCount` and the playing member holds everything. The paused member's frames are already inside that set. With this fix:
- The writer's case gives S demand 20 and O demand 13. After the windows (5 + 3) there are 10 frames left. O fits whole (it costs 10); S does not (it would cost 15).
- A store alone in a pool with room is held whole.

`leastDemand` can stay as it is. With window lengths of only 2 or 3, the playhead-bounded union is exact.

An alternative is to compute a true circular union of arcs with different lengths in `claimedFrameCount`, for example a sweep over the sorted playheads, taken twice around to handle the wrap, that tracks the furthest frame covered so far. But the whole-or-least form matches the documented design and is cheaper.

Add the writer's test plus a no-contention case: a 40-frame pool, a playing copy, and an idle copy at another frame should give bufferCapacity == frameCount. Also add a case where an unrelated rebalance keeps a whole store whole.


### D32. A view given its animation before first layout re-decodes when it shrinks (if the animation fit at first layout)

_Severity: low · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageView.swift:283`

**Repro:** [NukeUITests/animated-frames-view--pending-view-rebuilds-on-shrink.swift](NukeUITests/animated-frames-view--pending-view-rebuilds-on-shrink.swift)

**What:** At the first layout, applyAutomaticDownsamplingIfNeeded() turns a derived size the animation already fits into nil and marks the animation as still pending (sourcePendingDownsampling = maxPixelSize == nil ? source : nil). That state was meant for "nothing to derive a size from, wait in case the content mode changes". On a later, smaller layout the pending branch sees a non-nil size and builds a new downsampled player: a second decode and a second set of frames. A view that received the same animation after it already had a size never enters this state (setAnimatedImage does not do that clamping) and keeps its frames when it shrinks. So behavior depends on whether layout or the image came first, and every cell and SwiftUI AnimatedImage gets the image first.

**Expected:** "a view that shrinks keeps the frames it has" (AnimatedImages.md): the same player after shrinking from 200x200 to 20x20.

**Actual:** The player is replaced with one at maxPixelSize 64.

**Reproduction check:** macOS, 3 of 3 iterations, original case (200x200 to 20x20): `imageFirst.player === player` failed; the new player has options.maxPixelSize 64. The laid-out-first view kept its player. Verified 200x200 to 10x10 case: the player is replaced and `imageFirst.player?.store === store` fails, so a second set of frames is decoded at 32 px. The laid-out-first view kept both its player and its store. Same on the iOS simulator.

**Refutation attempt (failed):**

I traced the code at HEAD (Sources/NukeUI/AnimatedImages/AnimatedImageView.swift; the worktree does not change Sources) and the claim holds.

Image set first: the view has zero bounds, so setAnimatedImage takes the isPending path (lines 456-464). It leaves player at nil and sets sourcePendingDownsampling = source.

First layout at 200x200: derived is about 400px or more. The clamp at lines 268-269 turns it into nil because the 100px animation fits. The pending branch goes ahead because player == nil and builds a full-size player. Line 283 then sets sourcePendingDownsampling = source again, because maxPixelSize == nil.

Shrink to 20x20: derived is 20*backingScale rounded up to a multiple of 32 (64 at 2x). That is less than 100, so the pending branch's guard (maxPixelSize != nil || player == nil) passes and setPlayer builds a new downsampled player. That is a second decode and a second set of frames. This happens at any backing scale.

Layout first, then image: setAnimatedImage never clamps and gets derived = 400, so isPending is false and pending is nil. On shrink, the else branch calls hasOutgrownItsFrames. There decoded = min(400, 100) = 100, which is not less than longestSide, so it returns false and the player is kept. The asymmetry is real.

The expected behavior is documented. Documentation/NukeUI.docc/AnimatedImages.md (Memory section) says "a view that shrinks keeps the frames it has". Commit c9f10cd24 ("Decode the frames again when the view outgrows them") added that sentence along with the outgrow logic, and the view's doc comment only talks about re-settling when the view grows. The pending state after a fitting first layout is left over from f9a5e7052, when pending was the only state after layout. The comment on that branch says it is for "Nothing to derive a size from … Keep waiting, in case the content mode changes", which does not describe an animation that simply fits. No existing test in AnimatedImageViewTests asserts a rebuild on shrink for a fitting animation. doesNotRebuildThePlayerForAnAnimationThatAlreadyFits only covers growth.

The repro uses only public API: setting animatedImage and player, frame changes and layoutIfNeeded. There is no mock or timing dependence and no platform behavior involved. The order it tests (image before layout) is the normal one for every cell, every NukeUI.loadImage(into:) call on a cell, and every SwiftUI AnimatedImage.

Impact is low. It only happens when the animation fits the view at its first layout and the view later shrinks below the animation's pixel size. It costs one extra decode and a new set of frames, and only once, because pending is cleared after the rebuild. The previous frames are still displayed until the new player produces one. The new frames are smaller, so memory does not get worse. The harm is wasted CPU, possibly a brief stall, and behavior that contradicts the docs and depends on whether layout or the image came first.

**Suggested fix:**

In applyAutomaticDownsamplingIfNeeded (AnimatedImageView.swift:283), keep the view pending only when there was nothing to derive a size from, not when the animation merely fits:

    sourcePendingDownsampling = derived == nil ? source : nil

After this change, an animation that fits at the first layout gets a player the view owns and nothing stays pending. Later layouts go through the else branch, where hasOutgrownItsFrames returns false for a full-size player whether the view shrinks or grows. The zero-size and .center/.scaleNone cases (derived == nil) still wait for a usable layout or a content-mode change as they do now. Add a regression test in AnimatedImageViewTests: set the image first, lay out at 200x200 with a 100px GIF, then at 20x20, and expect the player to be the same object.


### D33. Docs say an animation held still decodes no frame past the first; the second frame is decoded

_Severity: low · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:264`

**Repro:** [NukeUITests/animated-frames-view--still-decodes-second-frame.swift](NukeUITests/animated-frames-view--still-decodes-second-frame.swift)

**What:** AnimatedImages.md (Controlling Playback) says of isPlaybackEnabled = false: "The first frame is displayed and no frames beyond it are ever decoded." A player that never plays still asks for idleFrameCount (2) frames, the deliberate floor every player holds, so frame 1 is decoded and kept too. This is a mismatch between the docs and the code. The code comments make the floor intentional, so the article is the likely fix.

**Expected:** Per the docs, frame 1 is never decoded (decodedFrameCount == 1).

**Actual:** isFrameBuffered(1) is true and decodedFrameCount == 2.

**Reproduction check:** macOS, 3 of 3 iterations: player.isFrameBuffered(1) → true and player.diagnostics.decodedFrameCount → 2 (expected 1). view.image != nil and isFrameBuffered(0) passed. Same on the iOS simulator.

**Refutation attempt (failed):**

The claim holds. Documentation/NukeUI.docc/AnimatedImages.md:94 says of `AnimatedImageView.isPlaybackEnabled = false`: "The first frame is displayed and no frames beyond it are ever decoded." The code doesn't do that.

- In `AnimatedImagePlayer.init`, a new player sets `keepsFullBuffer = false`. The comment there says it "asks for the first frames only", plural.
- Because of that, `wantedFrameCount` returns `idleFrameCount` (2) at AnimatedImagePlayer.swift:264. `bufferCapacity(windowLength:)` then clamps to `max(idleFrameCount, …)`, so the window is 0..<2 and the store decodes frames 0 and 1.
- A player that is never played therefore always holds two frames. This is the same on or off screen: `updatePlaybackState` only pauses it or clears `keepsFullBuffer`, and never goes below the floor. The SwiftUI `AnimatedImageRenderer` path ends the same way: it builds the player and never calls `play()` while playback is off.

The floor is deliberate. Its doc comment says "the floor for every player: with one frame, the next could only start decoding after the current one was dropped", and the article's own Memory section says "a player always holds two frames". The doc sentence was also never accurate. `git log -S` shows it came in with 3e1283ba ("Document animated images", 2026-08-29). At that commit a never-played player filled its whole buffer with `buffer.setCurrentIndex(0)`, with a floor of 2. Commit 52c3b260 later cut that down to the 2-frame idle floor.

Anyone can see the mismatch through public API: set `isPlaybackEnabled = false`, set `animatedImage`, and read `player.diagnostics.decodedFrameCount`, which reports 2. The repro does lean on `@testable` helpers (`waitUntilFull`, `isFrameBuffered`), but those only make the wait deterministic and aren't needed to see the result. This is not a platform or mock artifact.

It is a documentation defect, not a code defect. Impact is low: each still costs one extra frame decode and one extra frame of memory. For a list of large stills, where the user followed the doc to save memory, that doubles the memory the stills take, and the idle floor is not counted against the pool's cost limit. There's a smaller, related inaccuracy: turning playback off after the view has played keeps the full window ("paused in place keeps its frames"). So "ever decoded" is also wrong for a view that was already playing.

**Suggested fix:** Fix the article, not the code. The 2-frame floor is intentional and documented elsewhere. Change Documentation/NukeUI.docc/AnimatedImages.md:94 to something like: "The first frame is displayed, and the player holds only it and the frame after it – ready for when playback starts – decoding nothing further." Optionally, add a note that turning playback off on an animation that has already played pauses it in place and keeps the frames it has. If one frame per still really matters, the alternative code change is to let a player that has never played and has playback disabled want 1 frame instead of `idleFrameCount`, going back to the floor on `play()`. That means a short stall on the first tick, which is the thing the floor exists to avoid, so the doc fix is the better choice.


### D34. An infinite or very large playbackRate hangs the main thread on the first tick

_Severity: low · user impact: low · public API: yes · found by: animated-playback_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift:374`

**Repro:** [NukeUITests/animated-playback--huge-playback-rate-hangs-main-thread.swift](NukeUITests/animated-playback--huge-playback-rate-hangs-main-thread.swift)

**What:**

`tick(_:)` scales the tick by the rate and then walks the animation frame by frame. After each frame it carries over `min(remainder, clock.period * playbackRate)` (line 401), so the work per tick grows with the rate and has no bound.
- With `.infinity`, `elapsed` stays infinite and the loop never exits for an animation that loops forever with its frames in memory.
- With a finite 1e17, `elapsed - delay` rounds back to `elapsed` (the rounding step at that size is 0.25 s), so it never exits either.
- Smaller finite rates do finish, but after about period × rate / delay iterations per display refresh.

`playbackRate` is a public option with no documented range. Zero, negative and NaN are already handled by `guard step > 0`; only the large end is unguarded. The repro breaks the loop from `onLoop` after 1000 loops by emptying the store (with no frames in memory the next frame counts as late, which ends the loop), so the test fails instead of hanging the test process.

**Expected:** A tick returns after a bounded amount of work (the rate is clamped, or a non-finite rate is ignored the way NaN is). In the repro that means fewer than 1000 loops for one tick.

**Actual:** The tick spins until the escape hatch fires at 1000 loops. Without the escape hatch it spins forever on the main thread.

**Reproduction check:** All 3 iterations failed for both arguments (inf and 1e17): `loops < 1000` failed with loops == 1000, which means the escape hatch in onLoop was what stopped the tick. A diagnostic without an escape hatch measured one 1/60 s tick at finite rates. Rate 1e3 gave 41 loops. Rate 1e6 gave 41,666 loops and took 29 ms of main-thread time for one tick, more than a 60 Hz frame. That is linear in the rate, as claimed (period*rate/delay frames). Log: scratchpad/logs/repro-animated-playback-3.log (diagnostic: repro-animated-playback-3-diag.log).

**Refutation attempt (failed):**

I could not refute this. It is a real defect, but a user would only hit it by passing an absurd value.

**Code path.** In AnimatedImagePlayer.swift:368-403, `tick(_:)` sets `step = min(delta, 1) * playbackRate`. The only check is `guard step > 0`. That stops 0, negative values and NaN (NaN > 0 is false), but it lets +inf and very large finite rates through. Inside `while elapsed >= source.delays[currentFrameIndex]`, each pass sets `elapsed = min(elapsed - delay, clock.period * playbackRate)`.
- With rate = inf: inf - delay is still inf, and period * inf is inf, because every real clock has period > 0. The shipped clocks use 1/60 or the display link's interval, and `TimerClock.period = 1/rate`. So `elapsed` stays infinite.
- The loop has only three exits. `nextFrameIndex == nil` only happens with a finite repeat limit. A pending next frame only happens while frames are still decoding or the window slides. The third is the condition itself.
- So once a small, forever-looping animation is fully in memory, the main thread spins forever. That is the common case: `.image` repeat count, and it fits in the pool.

**Float math check.** I rebuilt the loop in a standalone Swift program (scratchpad/verify/sim.swift):

| Rate | Passes per tick |
|---|---|
| inf | never ends |
| 1e17 | never ends (the 0.1 s delay is below half the spacing between doubles, which is 0.25 there) |
| 1e9 | about 1.7e8 |
| 1000 | 166 |
| 100 | 16 |
| 4 | 0 |

Realistic rates are fine; the demo offers 0.25x to 4x.

**Intent and history.**
- The per-tick work used to have a limit. Before commit 98368815 ("Never skip a frame – stretch under load"), the loop broke after `source.frameCount` advances ("More than a full loop behind: drop the debt and carry on").
- That commit replaced the limit with the carry-over `min(remainder, clock.period * playbackRate)`, which only bounds the work when the rate is small.
- Nothing in the doc comment, AnimatedImages.md, the CHANGELOG or the commit messages gives `playbackRate` a range. The only doc is "The speed multiplier. `1` by default."
- The `step > 0` guard shows the code already tries to ignore meaningless rates. Leaving inf out of it looks like an oversight, not a choice.

**Is the repro valid?** It uses @testable internals: `ManualClock`, `waitUntilFull`, and `store.removeAllFrames` as an escape hatch. These only make the hang show up as a test failure. The same hang is reachable through public API only: `AnimatedImagePlayer(source:options:)` with `options.playbackRate = .infinity`, then `play()`, driven by the real clock. It is not an ImageIO or UIKit issue.

**Impact: low.** Nobody picks infinity on purpose. It could come from a computed rate, such as dividing by a target duration of zero. But the result is an unrecoverable freeze of the main thread, not a glitch. The code is unreleased Nuke 14 work, so the fix is cheap.

**Suggested fix:**

Put back a limit on the work in one tick, independent of the rate, since the display shows one frame per tick anyway. In `tick(_:)`, count the advances and stop after one loop's worth, the way the code did before 98368815:

```swift
var advancedCount = 0
while elapsed >= source.delays[currentFrameIndex] {
    ...
    advance(to: next)
    elapsed = min(remainder, clock.period * options.playbackRate)
    advanced = true
    advancedCount += 1
    if advancedCount >= source.frameCount { elapsed = 0; break } // a loop per tick at most
}
```

Optionally, also ignore non-finite rates the way NaN is ignored: `guard step > 0, step.isFinite else { return }`. Without it, inf also turns `counters.playbackTime` into inf, and `effectiveFrameRate` reads 0. The `isFinite` check alone does not handle 1e17, so the advance limit is the actual fix.

Consider documenting the range of `Options.playbackRate` (> 0). Add a regression test with rates [.infinity, 1e17, 1e9] that checks one `clock.tick(1/60)` completes at most one loop (`completedLoopCount` goes up by at most 1).


### D35. A frame transform that returns a larger bitmap makes AnimatedImageFramePool hold several times its costLimit, and nothing reclaims it

_Severity: low · user impact: low · public API: yes · found by: animated-playback_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:253`

**Repro:** [NukeUITests/animated-playback--review-transform-larger-bitmap-exceeds-pool-limit.swift](NukeUITests/animated-playback--review-transform-larger-bitmap-exceeds-pool-limit.swift)

**What:** The pool divides its budget using `demand` and `leastDemand`, which multiply by `bytesPerFrame`. That figure is an estimate from the source canvas (AnimatedImageFrameStore.swift:153). The store, however, charges each frame for the bitmap it actually holds (`didDecode`, :477), and the transform's bitmap counts too. So a transform that draws into a larger bitmap (padding, a border, a wider pixel format, a higher-resolution redraw) gets the animation held whole on the strength of the estimate. `reclaimIfNeeded()` (AnimatedImageFramePool.swift:353) does see `totalCost > costLimit`, but the one live store's window covers every frame, so `reclaim()` and `evict()` drop nothing. The pool stays over its limit for as long as the animation plays. `costLimit` is documented as "The memory the decoded frames of every player may occupy", and `AnimatedImageFrameTransform` sets no limit on what a transform may return. Confirmed on macOS: a pool with costLimit = 4 x source.bytesPerFrame (1024 bytes) playing a 4-frame 8x8 GIF whose transform doubles each frame ends at totalCost = 4096. The player's bufferedByteCount is also 4096 against a bufferByteLimit of 1024.

**Expected:** `pool.totalCost <= pool.costLimit` once the window is full. Either the animation is played out of a window, or the division uses what the frames actually cost.

**Actual:** pool.totalCost == 4096 against costLimit == 1024. diagnostics.bufferedByteCount is 4096 against a bufferByteLimit of 1024, and the player reports itself fully buffered.

**Reproduction check:** All 3 iterations failed with the same values: pool.totalCost == 4096 against costLimit == 1024, and diagnostics.bufferedByteCount == 4096 against bufferByteLimit == 1024. A diagnostic that then ticked the player through 10 frames and explicitly called pool.rebalance() and pool.reclaimIfNeeded() still ended at totalCost 4096 with bufferCapacity 4. Nothing reclaims the excess. Log: scratchpad/logs/repro-animated-playback-4.log (diagnostic: repro-animated-playback-4-diag.log).

**Refutation attempt (failed):**

I could not refute it. It reproduces on a clean `git archive HEAD` copy (scratchpad/refute-pool, macOS, NukeUITests scheme). The only change to that copy was the same `SwiftUI.Color` fix the working tree already has, because HEAD's LazyImageTests.swift doesn't compile on macOS. The repro fails exactly as described: `pool.totalCost` is 4096 against a `costLimit` of 1024, `bufferedByteCount` is 4096 against a `bufferByteLimit` of 1024, and the player reports `isFullyBuffered`.

Probes I added:
- No transform: 1024 of 1024.
- A transform that returns a same-size bitmap: 1024 of 1024.
- 2x transform on a 100x100, 20-frame GIF: 3,200,000 against 800,000.
- 3x transform on the same GIF: 7,296,000 against 800,000 (9.1x).

So the overage equals the ratio between the bitmap the transform returns and the canvas estimate.

The mechanism matches the report:
- `demand`, `leastDemand`, `windowLength` and `rebalanceIfNeeded` all work in `bytesPerFrame`, the canvas estimate (AnimatedImageFrameStore.swift:153, 253, 263, 317, 332).
- `didDecode` charges `image.bytesPerRow * image.height` (:477).
- `reclaimIfNeeded()` sees `totalCost > costLimit`, but `evict` returns early when a window covers every frame (:377), so nothing is dropped.

Arguments for intended behaviour, and why they fail:
1. The article and the `maxBufferSize` docs say "What is measured is what the frames cost decoded – the canvas at four bytes a pixel". That describes the measure, not permission to go over. The `costLimit` doc ("The memory the decoded frames of every player may occupy") and the article's single named exception ("One thing sits outside the limit: a player always holds two frames") don't cover this case.
2. Commit 863f3357 added the `didDecode` comment "a transform that drew into a bitmap of its own included". That shows the author meant a transform's bitmap to count against the pool. The division just never uses that figure.
3. Existing tests treat `pool.totalCost <= pool.costLimit` as an invariant (AnimatedImageFramePoolTests:223, AnimatedImageFrameSharingTests:515).
4. It isn't API misuse. `AnimatedImageFrameTransform` sets no size contract. The repro's internal init only injects a deterministic clock, power monitor and pool.
5. It isn't ImageIO behaviour or a test-harness artifact.

Qualifications:
- "Nothing reclaims it" is slightly overstated. A memory warning (`reduceMemoryUsage`) drops the windows to 2 frames, so the frames are released for the 60 s grace period, and then the animation is held whole again.
- Without any transform, Core Graphics row padding also goes over slightly: a 7x7 GIF used 896 against 784. The test helpers acknowledge this padding, and it is negligible at realistic sizes.
- A custom `AnimatedImageFrameDecoding` that returns bitmaps larger than `AnimatedImageSource.size` would hit the same gap.

Impact is low. The transform API is new and unreleased (Nuke 14 WIP), the documented uses (tint, rounded corner, filter) keep the size, and the overage is bounded by the transform's growth ratio. The case to worry about is the common iOS idiom of drawing with `UIGraphicsImageRenderer`'s default format. That renders at screen scale (about 9x the pixels on a 3x device) and may use an extended-range 16-bit format, which could turn a within-budget animation into an order of magnitude more memory.

**Suggested fix:**

In AnimatedImageFrameStore, base the division on what a frame actually costs once one has been decoded:
- Keep the canvas estimate as the starting value, and add a stored `costPerFrame`, e.g. `private(set) var costPerFrame: Int` initialised to `bytesPerFrame`.
- In `didDecode`, after computing `cost`, run `if cost > costPerFrame { costPerFrame = cost; pool?.rebalance() }`. Use max-observed, or a running average if frames can differ.
- Use `costPerFrame` in `demand`, `leastDemand`, `windowLength`'s capacity, the `rebalanceIfNeeded` whole-animation guard, the player's `affordableFrameCount` (`maxBufferSize / costPerFrame`) and `diagnostics.bufferByteLimit`.

After the rebalance, a store that no longer fits gets its window allotment. `windowLength` drops below `frameCount`, and `evict` releases the frames outside the window, so `totalCost` settles at or under `costLimit` apart from the documented two-frame floor. Add the repro as a regression test, with a 2x transform and costLimit = 4 x source.bytesPerFrame, expecting `pool.totalCost <= pool.costLimit` and `isFullyBuffered == false`.

The weaker alternative is documentation only: state in `AnimatedImageFrameTransform` and the article that the budget assumes the transform returns a bitmap no larger than the frame it was given.


### D36. ImagePrefetcher.priority updates can be applied out of order, leaving queued prefetches at a stale priority

_Severity: low · user impact: low · public API: yes · found by: concurrency-stress, prefetch-internals_

**Where:** `Sources/Nuke/Prefetching/ImagePrefetcher.swift:39`

**Repro:** [NukeThreadSafetyTests/concurrency-stress--prefetcher-priority-stale-hop.swift](NukeThreadSafetyTests/concurrency-stress--prefetcher-priority-stale-hop.swift), [NukeTests/prefetch-internals--priority-updates-applied-out-of-order.swift](NukeTests/prefetch-internals--priority-updates-applied-out-of-order.swift)

**What:** The setter schedules `Task { @ImagePipelineActor in self.didUpdatePriority(to: newValue) }`, which captures the new value. The actor runs its queued jobs by priority, and each hop inherits the priority of the thread that set the property. So when the property is set from a background thread and then from a user-initiated one, the second hop runs first and the first hop lands last with the stale value. This is the same defect as the one fixed for ImageTask.priority in PR #918 (that hop now reads `self.priority`); the prefetcher still has the old pattern. The doc comment says changing the priority also changes the priority of all outstanding tasks.

**Expected:** After setting .veryHigh from a background-QoS thread and then .veryLow from a user-initiated one, `prefetcher.priority == .veryLow` and the queued prefetch operation's priority is .veryLow.

**Actual:** `prefetcher.priority == .veryLow`, but the queued operation's priority is .veryHigh. 5 out of 5 runs.

**Reproduction check:** All 3 iterations failed with `operation.priority → .veryHigh` where .veryLow was expected. `prefetcher.priority == .veryLow` passed each time. The failure matches the claim. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-prefetch-internals-3.log

**Refutation attempt (failed):**

I could not refute this. It is a real defect, and the maintainer already fixed the same pattern elsewhere.

Code: the setter at Sources/Nuke/Prefetching/ImagePrefetcher.swift:39 writes the new value into `_priority` under a lock. It then schedules `Task { @ImagePipelineActor in self.didUpdatePriority(to: newValue) }`, so each hop applies the value it captured. `ImagePipelineActor` is a plain default `@globalActor` actor. Its queued jobs run in priority order, and an unstructured `Task` takes the QoS of the thread that creates it. If the actor is busy, a hop scheduled from a background thread can run after a later hop from a user-initiated thread. The stale value is then applied last to every outstanding `PrefetchTask`: `request.priority`, `imageTask.priority` and `operation.priority`. The `priority` getter reads the lock, so it still returns the newest value while the queued work runs at the old one.

Is it promised? Yes. The doc comment says "Changing the priority also changes the priority of all of the outstanding tasks managed by the prefetcher." The class doc says "All ImagePrefetcher methods are thread-safe." Setting the property from different threads is therefore supported use. Commit ee70cccb (PR #918, listed in CHANGELOG.md) fixed the identical pattern in `ImageTask.setPriority`. Its commit message: "two hops carry no ordering guarantee between them, so a stale value could land last … Read the priority inside the hop instead of capturing it". The prefetcher copy was never updated; `git log -S` shows it unchanged since 088f0b25.

Does the repro misuse the API? No. It sets the public `priority` property from two DispatchQueues with different QoS. It uses the internal `prefetcher.queue` only to observe the operation. Holding the actor synchronously (`group.wait()`) only forces the "actor is busy" window. In a real app the shared pipeline actor is busy during heavy loading, so the window is narrow but real.

Verification: I copied the repo to the scratchpad (the real repo is unchanged) and ran the repro with xcodebuild on macOS. It failed with `operation.priority → .veryHigh` while `prefetcher.priority == .veryLow`. I then changed only line 39 to read `self.priority` inside the hop. The repro and all 31 existing ImagePrefetcherTests passed (32 tests).

Impact is low. Most apps set the prefetcher priority from the main thread only, and hops at the same priority run in FIFO order. Hitting it takes updates from threads with different QoS while the actor is busy. When it happens, queued prefetches keep a stale scheduling priority until the next change. It does not affect correctness or completion.

**Suggested fix:**

Use the same fix as PR #918: read the current value inside the hop instead of capturing `newValue`. In Sources/Nuke/Prefetching/ImagePrefetcher.swift:39:

    Task { @ImagePipelineActor in
        // Read the priority instead of capturing `newValue`: the hops are
        // unordered, so a stale value could land last.
        self.didUpdatePriority(to: self.priority)
    }

Every hop then converges on the latest value. I checked this change in a scratch copy: the repro and all ImagePrefetcherTests pass. For a regression test, add the repro to Tests/NukeTests/ImagePrefetcherTests.swift. Optionally add a short CHANGELOG line that mirrors the #918 entry.

- Also reported by **concurrency-stress** (unverified): ImagePrefetcher.priority can leave outstanding prefetches at a stale priority

### D37. Concurrent writes to different ImageCache limits overwrite each other

_Severity: low · user impact: low · public API: yes · known: defects.md #45 · found by: concurrency-stress, memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:38`

**Repro:** [NukeThreadSafetyTests/concurrency-stress--image-cache-config-lost-update.swift](NukeThreadSafetyTests/concurrency-stress--image-cache-config-lost-update.swift), [NukeTests/memory-cache--limit-update-lost-under-concurrency.swift](NukeTests/memory-cache--limit-update-lost-under-concurrency.swift)

**What:** Each ImageCache limit setter (costLimit, countLimit, ttl, entryCostLimit) is written as `impl.conf.x = newValue`. Swift runs that as a read-modify-write of the whole Configuration through the separate get and set of Cache.conf. Each of the two takes the lock, but the lock is released in between. So if one thread sets countLimit while another sets costLimit, the countLimit write can put back the old costLimit. The ImageCaching protocol says "The implementation must be thread safe", and there is no other way to change the limits. In the repro, one thread only ever writes costLimit and another only writes countLimit. In one run, 10,810 of 200,000 read-backs returned a value other than the one just written.

**Expected:** A thread that is the only writer of costLimit always reads back the value it just wrote.

**Actual:** lostUpdates was 10,810 instead of 0.

**Reproduction check:** All 3 iterations failed `lostUpdates.withLock { $0 } == 0`. lostUpdates was 9921, 9031 and 10454 out of 200,000 read-backs. Log: scratchpad/logs/repro-memory-cache-3.log

**Refutation attempt (failed):**

The race is real. It uses only public API, and I reproduced it outside the test target.

Code: in Sources/Nuke/Caching/ImageCache.swift (lines 26-49), each of `costLimit`, `countLimit`, `ttl` and `entryCostLimit` is set with `impl.conf.x = newValue`. `Cache.conf` (Sources/Nuke/Caching/Cache.swift:38-49) is a computed property. Its `get` and its `set` each take `lock` and release it. So Swift runs a nested-member assignment as get the whole `Configuration`, change a copy, then set the whole `Configuration`, and the lock is not held in between. Two threads that write different fields can therefore overwrite each other with a stale copy. Nothing else writes `conf`, and there is no other public way to change the limits.

Intent and history: nothing in the history suggests this was on purpose. The get/set pair dates back to at least e9d32760 (2022, "Shorter conf in Cache"), which only renamed `configuration` to `conf`. The earlier version used the same `lock.sync { _conf }` / `lock.sync { _conf = newValue }` pair. No commit message, CHANGELOG entry or doc comment says concurrent configuration is unsupported. `ImageCaching` is `Sendable` and says "The implementation must be thread safe", and `ImageCache` conforms to it. So a user can reasonably expect that one thread's write to `costLimit` is never undone by another thread's write to `countLimit`.

Repro validity: the repro has `@testable import`, but it only calls the public `ImageCache` setters and getters. To check that, I built a separate SwiftPM executable in the scratchpad that depends on the local Nuke package with a plain `import Nuke`, in release configuration. Results:
- The same two-writer loop had 3,830 of 200,000 read-backs return a value other than the one just written.
- A more realistic case that sets `costLimit = 500` on one thread and `countLimit = 50` on another, once each, on fresh caches, ended in the wrong final state 1 time in 20,000. So a limit can be reverted for good, not only for a moment.

This is not caused by a mock, test timing, ImageIO, UIKit or URLSession.

Impact is low. Limits are almost always set once at startup, from one thread. To hit this, an app has to change different limits from different threads at the same moment. When it does happen, a setting is silently dropped, for example the cost limit falls back to the old value. There is no crash and no memory corruption, because every access to the storage is still under the lock.

**Suggested fix:**

Hold the lock across the whole read-modify-write. In Cache.swift, add:

    func updateConf(_ body: (inout Configuration) -> Void) {
        lock.lock(); defer { lock.unlock() }
        body(&_conf)   // _conf's didSet still runs _trim() under the lock
    }

Then make each ImageCache setter use it, for example `set { impl.updateConf { $0.costLimit = newValue } }`, and do the same for countLimit, ttl and entryCostLimit. Keep `conf`'s getter for reads, and remove its setter (or make it private) so the non-atomic path can't come back. An alternative is a `_modify { lock.lock(); defer { lock.unlock() }; yield &_conf }` accessor on `conf`, but the closure form avoids the underscored accessor. Add a regression test in which two threads write different limits and each thread always reads back its own value.

- Also reported by **concurrency-stress** (unverified): ImageCache limit setters lose concurrent updates (read-modify-write of Cache.conf)

### D38. A job started by an unrecorded task (switch off) names the recorded task that later joined it as its creator

_Severity: low · user impact: low · public API: yes · found by: concurrency-stress, diagnostics_

**Where:** `Sources/Nuke/Diagnostics/DiagnosticsRecorder.swift:343`

**Repro:** [NukeThreadSafetyTests/concurrency-stress--diagnostics-created-by-joined-task.swift](NukeThreadSafetyTests/concurrency-stress--diagnostics-created-by-joined-task.swift), [NukeTests/diagnostics--created-by-joining-task.swift](NukeTests/diagnostics--created-by-joining-task.swift)

**What:** `JobRecord.makeSnapshot` sets `copy.createdByTaskID = joins.first?.taskID ?? 0`. `joins` only holds recorded tasks, because `ImageTask.diagnosticsDidSubscribe` returns early for a task with no record. So when the task that started the job was skipped by `pipeline.diagnostics.isEnabled == false`, `joins.first` is the first recorded task that joined later. That task's copy of the job then contradicts itself: `joinedAt != nil` means "its chain didn't create the job", yet `createdByTaskID` names it, while `createdByTaskID` is documented as "The task whose request created the job".

**Expected:** `createdByTaskID` is not the joining task's ID when that task's `joinedAt` is set: either 0 (unknown), or the first join's task only when that join's `joinedAt` is nil.

**Actual:** All three jobs (loadImage, fetchOriginalImage, fetchOriginalData) have `createdByTaskID == recorded.taskId` and also `joinedAt != nil`, and `isCoalesced == true`.

**Reproduction check:** Failed 3/3. All three jobs print `j1 .loadImage says task #2 created it, and that the same task joined it at …`, and the same holds for j2 fetchOriginalImage and j3 fetchOriginalData. The preconditions held: `isCoalesced`, 3 jobs, and `joinedAt != nil` on every job.

**Refutation attempt (failed):**

I could not refute this. The bug is real and reachable through public API only.

How it happens, from the code:
- Job records are created whenever `pipeline.recorder` exists, so whenever `isDiagnosticsEnabled` is set (Sources/Nuke/Tasks/AsyncPipelineTask.swift:18). The runtime switch does not gate them.
- Task records are gated by the switch in `makeTaskRecord` (DiagnosticsRecorder.swift:50).
- An unrecorded creator's subscription is dropped in `ImageTask.diagnosticsDidSubscribe` (line 393). The parents it creates copy the child's empty `joins` in `attach(child:didJoin:false)`.
- When a recorded task later joins, `addJoin` stores it with `joinedAt = now` in all three jobs.
- `makeSnapshot` (line 343) then sets `createdByTaskID = joins.first?.taskID`, which is the task that joined.

I ran the repro in an isolated `git archive` copy at scratchpad/refute-createdby-join (macOS, xcodebuild). All three expectations failed. The recorded task's JSON has `createdByTaskID: 2`, `taskIDs: [2]` and `joinedAt` set on j1, j2 and j3, while the creator was unrecorded task #1. So one record says both "task 2 created this job" and "task 2 joined this job", which contradicts the doc on `Job.createdByTaskID` ("The task whose request created the job", ImagePipeline+Diagnostics.swift:89) and on `joinedAt` ("nil if the task's chain created the job").

Is it intentional or documented? No.
- The switch doc says "The jobs the tasks share are reported only when a recorded task reached them". That explains why the unrecorded creator is missing from `taskIDs`, not why a joiner is named as creator.
- `git log -S` shows the "first join is the creator" rule goes back to 226f3da9 and was kept in 58ec360f. Neither commit considers an unrecorded creator.
- The CHANGELOG has nothing on this.
- The existing test `coalescedTaskJoinsTheJobs` only covers two recorded tasks.

Misuse or harness artifact? No. The repro uses `MockDataLoader`, `TestExpectation` and `onTaskStarted` only to keep the download in flight and to order the join. The same state comes from a real app turning `pipeline.diagnostics.isEnabled` on while prefetches are running, then a visible cell asking for the same image. Toggling the switch on and off to sample would hit this regularly.

Impact is low:
- The text timeline (`description` / `formatted`) never reads `createdByTaskID`. It correctly prints "coalesced: yes" and "joined at".
- `isCoalesced`, `joinedAt` and the attributed durations are all correct.
- Only JSON or code consumers that read `createdByTaskID` get the wrong creator. For example, a log pipeline that dedups jobs by `id` and credits the download to its creator would blame the cell instead of the prefetcher.
- It only happens when the runtime switch changes while shared work is in flight.

**Suggested fix:**

In `JobRecord.makeSnapshot` (Sources/Nuke/Diagnostics/DiagnosticsRecorder.swift:343), name a creator only when the first join is a creation (its `joinedAt` is nil), and otherwise report 0, the same "unknown" value the record starts with:

    copy.createdByTaskID = joins.first.flatMap { $0.joinedAt == nil ? $0.taskID : nil } ?? 0

This is safe for recorded creators. A creator is always recorded with `joinedAt == nil` (the first subscriber, `subscriptionKey == 0`), and `attach(child:didJoin:false)` copies those nil entries into the parents it creates. A job cannot have a parent yet when its creating subscriber attaches, because dependencies subscribe in `start()`, after `didSubscribe`. So `coalescedTaskJoinsTheJobs` and `networkLoadRecordsTheWholeChain` keep passing.

Also:
- Document on `createdByTaskID` that it is 0 when the task that created the job was not recorded (runtime switch off).
- Add the repro as a regression test in ImagePipelineDiagnosticsTests.swift that expects 0.

- Also reported by **concurrency-stress** (unverified): Diagnostics report a task that joined a job as the job's creator after the switch is flipped

### D39. Writes are silently dropped when the generated filename is 251–255 bytes long

_Severity: low · user impact: low · public API: yes · found by: data-cache_

**Where:** `Sources/Nuke/Caching/DataCache.swift:501`

**Repro:** [NukeTests/data-cache--long-filename-temp-file.swift](NukeTests/data-cache--long-filename-temp-file.swift)

**What:** `write(_:to:)` first writes to a temporary file named "." + filename + ".tmp", which is 5 bytes longer than the entry's filename. A filename of 251–255 bytes is still valid under APFS's 255-byte limit (the limit the `FilenameGenerator` docs mention), but its temporary name is not. `Data.write` then fails with error 514 (invalid filename), and the catch-all in `perform(_:)` at lines 479–481 swallows it. The change is then dropped from staging, so the entry never reaches the disk, on every write to that key. This is a regression from #937: the previous non-atomic `data.write(to: url)` handled these names. A generator that percent-encodes the key and truncates it to 255 bytes hits it for every long URL.

**Expected:** An entry whose filename is a valid 252-byte name is persisted and readable after `flush()`.

**Actual:** After `flush()`, `cache["ab"]` is nil and `totalCount` is 0. The repro first writes a file with the same 252-byte name directly, to show the name itself is valid.

**Reproduction check:** Failed in all 3 iterations. The direct probe write to the 252-byte URL succeeded, but after `cache["ab"] = ...` + `await flush()`, `cache["ab"] == Data("123".utf8)` was false (nil) and `cache.totalCount == 1` was false (0). Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-cache-2.log

**Refutation attempt (failed):**

I could not refute it. The bug is real and reachable through the public API.

1. Code (Sources/Nuke/Caching/DataCache.swift:499-513, added in e84607af / PR #937): `write(_:to:)` first writes to `"." + url.lastPathComponent + ".tmp"`, which is 5 bytes longer than the entry's filename. For a 251–255 byte filename, `data.write(to: tempURL)` throws NSCocoaErrorDomain 514. The only error `perform(_:)` retries is fileNoSuchFile, so this one falls into the empty `catch {}`. Then `staging.flushed(staging)` drops the change from staging, so the entry exists only until the flush.

2. The platform limit, checked with a standalone script on this Mac (APFS): direct writes with 250, 251, 252 and 255-byte names succeed and 256 fails. The matching ".<name>.tmp" write fails with 514 for 251, 252 and 255. `Data.write(options: .atomic)` with a 255-byte name also succeeds. So the name is valid and the failure comes only from Nuke's temp-name scheme.

3. Nuke code, not a test artifact: I copied Sources/Nuke from HEAD into a scratch SwiftPM package (the repo was not touched) and ran the agent's repro. It fails exactly as described: `cache["ab"]` is nil after `flush()` and `totalCount` is 0. With `write` changed to the pre-#937 `try data.write(to: url)`, the same test passes. So this is a regression that #937 introduced.

4. API use: the repro calls only public API: `DataCache(path:filenameGenerator:)`, `isSweepEnabled`, `url(for:)`, subscript, `flush()`, `totalCount`. The `@testable` import is not needed for any of it. The public `FilenameGenerator` doc says names must fit "a size limit for filenames (e.g. 255 UTF-8 characters in APFS)", so a user who follows that guidance can hit it. Nothing documents a lower limit such as 250, and neither the CHANGELOG nor the #937 commit message mentions the new restriction. The failure is also silent: no error, no log, and the entry reads back from staging until the flush.

Why the impact is low and not medium: the default generator (SHA1, 40 hex chars) can never hit this. Only custom generators that make filenames longer than 250 bytes are affected, such as percent-encoding plus truncation to 255, which is uncommon. #937 is also unreleased: it is on main under "Nuke 14 WIP" and in no tag, and 13.2.0 is unaffected. For users who are affected, every write to those keys is lost silently and permanently, so disk caching quietly stops working for long URLs.

Relevant files:
- /Users/kean/Developer/Nuke/Sources/Nuke/Caching/DataCache.swift (lines 86-92, 469-513)
- the repro at /Users/kean/Documents/_nuke/test-coverage/2026-09-19/bugs/data-cache--long-filename-temp-file.swift
- the scratch verification package at /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/lfn/pkg

**Suggested fix:**

Keep the temp name within NAME_MAX (255 bytes) whatever the entry filename is. The smallest change is in `write(_:to:)`: when the derived name would be too long, use a fixed-length hidden name that is still derived from the destination, so it stays deterministic (one leftover per key after a crash) and hidden (skipped by `contents(keys:)`). All writes are serialized on ioQueue, so it does not need to be unique beyond that.

```swift
let name = url.lastPathComponent
let tempName = name.utf8.count <= 250
    ? "." + name + ".tmp"
    : "." + (DataCache.filename(for: name) ?? UUID().uuidString) + ".tmp" // 46 bytes
let tempURL = url.deletingLastPathComponent().appendingPathComponent(tempName, isDirectory: false)
```

A simpler fallback also works: catch the invalid-name error (CocoaError.fileWriteInvalidFileName) in `perform(_:)` and retry with `data.write(to: url, options: .atomic)`, which I verified writes a 255-byte name. Add a DataCacheTests case with a generator that returns a 255-byte name, then check that the entry reads back after `flush()` and from a new instance at the same path. Optionally, change the FilenameGenerator doc to say names up to 255 bytes are supported.


### D40. A last-sweep date in the future turns off the scheduled LRU sweeps until the clock catches up

_Severity: low · user impact: low · public API: yes · found by: data-cache_

**Where:** `Sources/Nuke/Caching/DataCache.swift:558`

**Repro:** [NukeTests/data-cache--future-sweep-date.swift](NukeTests/data-cache--future-sweep-date.swift)

**What:** `isSweepNeeded()` checks `Date().timeIntervalSince(lastSweepDate) >= sweepInterval`. If the date stored in `.data-cache-info` is ahead of the current clock, the interval is negative, so every scheduled sweep is skipped until the real date reaches the stored one. That can happen when the device clock was wrong during a sweep and was corrected later, or when the folder was restored from another device. Skipped sweeps never rewrite the metadata, so only an explicit `sweep()` fixes it; until then the cache grows past `sizeLimit` without bound. This contradicts the docs: "The sweeps are performed periodically for as long as the cache is alive", and the first sweep "is skipped if one was already performed within the interval".

**Expected:** A stored date that isn't in the past does not count as a recent sweep, so the launch sweep runs and trims the cache.

**Actual:** With the stored date set one year ahead, `onSweepCompleted` is never called; the `TestExpectation` times out after 10 s. The cache stays at 4 MB with a 1 MB `sizeLimit`.

**Reproduction check:** Failed in all 3 iterations: `TestExpectation timed out after 10.0 seconds` because `onSweepCompleted` was never called. After that, `cache.totalSize <= 1024 * 1024` was false; totalSize was 4194304 against a 1048576 limit. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-cache-3.log

**Refutation attempt (failed):**

I could not refute this. The report reads the code correctly. `isSweepNeeded()` in /Users/kean/Developer/Nuke/Sources/Nuke/Caching/DataCache.swift:554-559 returns `Date().timeIntervalSince(lastSweepDate) >= sweepInterval`. When `lastSweepDate` is later than the current clock, that interval is negative, so `performScheduledSweep()` returns early. It returns before `performSweepAndRecordIt()`, so the bad date is never overwritten. `scheduleSweep` keeps re-arming every `sweepInterval` ("Also when skipped"), but each run is skipped the same way until the wall clock passes the stored date. Only a manual `sweep()` rewrites the date. Nothing else trims the cache: writes do not trigger a sweep.

Intent and history: the comparison came from 7a28b9d4 (2023, "Move DataCache metadata to file"), and the older UserDefaults version it replaced did the same thing. No commit, CHANGELOG entry or doc says a future date is meant to count as a recent sweep. Recent work (508fdfd1, PR #930 "sweeping only once per launch"; PR #932) added the promise that sweeps run "periodically for as long as the cache is alive". The `sweepInterval` doc says the first sweep is skipped only "if one was already performed within the interval". A date a year ahead does not fit either statement. The existing tests cover only a past date (-3600 s) and a fresh date, never a future one.

Misuse check: none. The repro uses the internal `sweepDelay`/`onSweepCompleted` init only to watch the sweep happen. The public `init(name:)`/`init(path:)` schedule the same sweep. The `.data-cache-info` file the test writes by hand is exactly what Nuke writes itself when it sweeps under a clock that is set ahead. This is not ImageIO, URLSession or platform behavior, and it is not a timing artifact of the test harness: the arithmetic is deterministic.

How a user hits it: someone sets the device clock forward, often to skip ahead in games. The app sweeps during that window, and then the clock is corrected. Sweeps then stop for as long as the clock was ahead. Restoring from another device is less likely: iOS backups and Time Machine usually skip Caches. It could still happen with a custom `path:` such as Application Support.

Why the impact is low: it needs an unusual clock change. The skipped period lasts only as long as the clock was ahead. `sizeLimit` is a soft LRU target. iOS also purges Caches when storage runs low. Still, for a large jump the disk cache can grow well past `sizeLimit` for months, which breaks the documented behavior.

**Suggested fix:**

In DataCache.isSweepNeeded(), treat a stored date that is ahead of the current clock as untrustworthy, so the sweep runs:

    private func isSweepNeeded() -> Bool {
        guard let lastSweepDate = getMetadata().lastSweepDate else { return true }
        let elapsed = Date().timeIntervalSince(lastSweepDate)
        // A date in the future means the clock changed since it was recorded
        return elapsed < 0 || elapsed >= sweepInterval
    }

This repairs itself: performSweepAndRecordIt() writes the current Date() afterwards, so later checks work normally again. A small backwards clock step right after a sweep costs at most one extra sweep, which is harmless because sweeping twice changes nothing. Add a DataCacheTests case next to scheduledSweepRunsWhenTheLastOneIsOlderThanTheInterval that stores lastSweepDate = Date(timeIntervalSinceNow: 365 days) and expects the launch sweep to run and trim the cache. Also update the `sweepInterval` doc comment if needed.


### D41. DataLoader drops URLSession metrics for rejected (non-2xx) responses, so diagnostics of 404s have no urlSessionMetrics

_Severity: low · user impact: low · public API: yes · found by: data-loader_

**Where:** `Sources/Nuke/Loading/DataLoader.swift:211`

**Repro:** [NukeTests/data-loader--review-rejected-response-drops-urlsession-metrics.swift](NukeTests/data-loader--review-rejected-response-drops-urlsession-metrics.swift)

**What:** When validate rejects a response, _DataLoader.urlSession(_:dataTask:didReceive:completionHandler:) removes the handler and immediately calls `handler.completion(error, nil)`. URLSession only collects the task's metrics after that, following the `.cancel` disposition. By then didFinishCollecting finds no handler, so the metrics are thrown away. With diagnostics on, every download that failed with a 4xx/5xx has `Stage.urlSessionMetrics == nil`, and so does ImageTask.Metrics.urlSessionMetrics (which also means no wireBytes, redirect count or timing). The docs for Stage.urlSessionMetrics say it is nil only 'if the data loader isn't a DataLoader, or if the download hadn't completed when the record was captured', and neither is true here. Stage.statusCode is also nil for these downloads, because it's only recorded when the first data chunk arrives. The repro includes a control: a download that fails with a network error mid-body does get its metrics, and that test passes.

**Expected:** The download stage of a task that failed with .dataLoadingFailed(statusCodeUnacceptable(404)) carries urlSessionMetrics, like successful downloads and network failures do.

**Actual:** download.urlSessionMetrics == nil and metrics.urlSessionMetrics == nil. The control test (networkConnectionLost mid-body) passes.

**Reproduction check:** All 3 repetitions of rejectedResponseHasURLSessionMetrics() failed with "Expectation failed: download.urlSessionMetrics != nil" (the value is nil) and "Expectation failed: metrics.urlSessionMetrics != nil" (nil). The error was .dataLoadingFailed and urlSessionTaskID was non-nil, so only the metrics assertions failed. The control networkFailureHasURLSessionMetrics() passed all 3 repetitions. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-6.log

**Refutation attempt (failed):**

I could not refute this. It reproduces, and it is not a test artifact.

1. The repro fails as described. I built a copy of Sources/Nuke in the scratchpad package refute-metrics with the repro test added and ran it. rejectedResponseHasURLSessionMetrics fails: download.urlSessionMetrics and metrics.urlSessionMetrics are both nil. The control, networkFailureHasURLSessionMetrics, passes.

2. It also happens with a real HTTP server, not only with the URLProtocol mock. I ran a python http.server on 127.0.0.1 and used a plain DataLoader(configuration: .ephemeral) with isDiagnosticsEnabled on and a URLSessionTaskDelegate spy set as DataLoader.delegate. For a 404, the spy saw ["metrics", "complete(-999)"], and the metrics' transaction had status 404. So URLSession does collect and deliver the metrics. Nuke drops them because line 210 unregisters the handler before didFinishCollecting runs. For comparison, a 200 response that later fails to decode keeps its metrics and statusCode 200. So among failed downloads, only responses that validate rejects lose them. Stage.statusCode is also nil for the 404, as the report says.

3. Nothing marks this as intended. The code comes from two commits:
   - 2197bea6 unregisters the handler before .cancel to fix a double completion.
   - a85dfafe ("Record what URLSession measured for the download") later changed `handler.completion(error)` to `handler.completion(error, nil)` without comment. Its only new test covers the success path.

   Neither the CHANGELOG nor the docc mention this limitation. The Stage.urlSessionMetrics doc says it is nil only when the loader isn't a DataLoader or the download hadn't completed when the record was captured. The ImageTask.Metrics doc says "or if the task ended before the download did". You could argue that wording technically covers this, because DataLoader reports the failure before URLSession's didCompleteWithError. But that gap is created by DataLoader itself, not by the user or a cancellation. The metrics exist a moment later, and a user reading the doc would expect a finished 404 download to carry them.

4. The repro does not misuse the API. It uses only public API: DataLoader(configuration:), isDiagnosticsEnabled, ImageTask.metrics and Stage.urlSessionMetrics. The internal loadData(…completion: (Error?, URLSessionTaskMetrics?)) overload is what the pipeline itself calls when diagnostics are on.

Impact is low. Only diagnostics are affected, in an opt-in feature that hasn't shipped yet (the WIP section of the CHANGELOG, Nuke 14). Loading behavior doesn't change, and ErrorSummary still carries statusCodeUnacceptable(404). Still, the missing timing, wire bytes and redirect data belong to the failed requests diagnostics exist to explain.

**Suggested fix:** In _DataLoader.urlSession(_:dataTask:didReceive:completionHandler:), when validate rejects the response and the handler asked for metrics (handler.collectsMetrics), don't call the completion right away. Store the validation error, keep the handler registered, and call completionHandler(.cancel). Then, in urlSession(_:task:didCompleteWithError:), call handler.completion(rejection ?? error, metrics) once, so the validation error replaces URLError(.cancelled). That keeps the "called once" contract that 2197bea6 fixed, and it lets didFinishCollecting, which runs before didCompleteWithError, find the handler and store the metrics. A minimal version adds `var rejection: Error?` to _Handler (it would need a lock or delegate-queue confinement, because _Handler is Sendable), or keeps a `rejections: [URLSessionTask: Error]` dictionary next to `metrics`. The collectsMetrics == false path can keep completing immediately, so nothing changes when diagnostics are off. Optionally, fill Stage.statusCode from the last transaction's HTTPURLResponse when metrics arrive with no statusCode recorded, so rejected responses get their status code too. Add a test to ImagePipelineDiagnosticsTests for a 404 with diagnostics on, and one to DataLoaderTests that metrics come with the completion for a rejected response and the completion is called exactly once.


### D42. A 416 (rejected range) response puts the resumable data back, so every retry sends the same bad Range

_Severity: low · user impact: low · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:354`

**Repro:** [NukeTests/data-loading-tasks--rejected-range-is-retried-forever.swift](NukeTests/data-loading-tasks--rejected-range-is-retried-forever.swift)

**What:** The default `DataLoader` validates the status code when the response arrives and fails with `statusCodeUnacceptable(416)` without passing the response to the pipeline. `urlResponse` stays nil, so `tryToSaveResumableData()` takes the "request ended before the server responded" branch and stores the rejected range again. The server did respond, and it rejected exactly that range. Every later attempt repeats the Range and fails, until the in-memory entry is evicted. This happens, for example, with a server that honors Range but not If-Range after the resource got shorter. The repro uses a real DataLoader with a private URLProtocol.

**Expected:** After the 416, the next attempt asks for the whole resource and succeeds.

**Actual:** The third attempt sends `Range: bytes=10000-` again and fails with 416.

**Reproduction check:** Failed 3/3 iterations: ranges.last → "bytes=10000-" (expected nil), and result?.0 → nil, so the third attempt failed again. ranges.count == 3, and the second range bytes=10000- passed as expected (log: scratchpad/logs/repro-data-loading-tasks-6.log).

**Refutation attempt (failed):**

I could not refute this. The bug is real and it is a regression.

Mechanism, checked against HEAD 2c2b23f6:
- `performDataLoad` removes the resumable data from `ResumableDataStorage`, then adds `Range: bytes=N-` and `If-Range`.
- On a non-2xx response, `_DataLoader.urlSession(_:dataTask:didReceive:completionHandler:)` (Sources/Nuke/Loading/DataLoader.swift:206) calls `validate`. It then fails with `DataLoader.Error.statusCodeUnacceptable(416)` and cancels, so `didReceiveData` never runs.
- As a result `urlResponse` stays nil in TaskFetchOriginalData. `dataTaskDidFinish(error:)` then calls `tryToSaveResumableData()`, which falls into the `else if let resumableData` branch (TaskFetchOriginalData.swift:348-351) and stores the rejected range again.

History: commit 08e6441b (Aug 2026) added that branch, and it shipped in 13.1.0 and 13.2.0. The commit message and the code comment give the intent as "a request that ended before the server responded". A 416 is a server response that rejects exactly that range, so it does not fit the stated intent. Before 08e6441b, the same path dropped the data, and the next attempt fetched the full resource.

Escape routes:
- Nuke never retries on its own, so each later load by the user (a LazyImage reappearing, a pull-to-refresh) takes the entry out, sends the same Range, gets 416 and puts the entry back. Re-inserting it also keeps it at the fresh end of the LRU.
- `reloadIgnoringCachedData` does not skip resumable data. `ResumableDataStorage.removeAllResponses` is internal. The only public ways out are `isResumableDataEnabled = false` or a new pipeline (new pipeline id).
- Otherwise the entry leaves only through count/cost eviction or the iOS background trim to 10%. A refreshed entry probably survives that trim.

Verification: I exported HEAD with `git archive` to the scratchpad, added the repro file and ran it with xcodebuild on macOS. It fails exactly as described: the third attempt sends the Range again, `ranges.last != nil` and `result` is nil. The repro uses a real `DataLoader` and URLSession with a URLProtocol, not a mock `DataLoading`. It relies on `@testable` only for test helpers (`makeStartedImageTask`, `Test.data`). The public `imageTask`/`data(for:)`/LazyImage paths reach the same code. I then applied a minimal fix in the copy: skip the put-back when the error is `.dataLoadingFailed(DataLoader.Error.statusCodeUnacceptable(416))`. The repro passed, and all 5 existing ImagePipelineResumableDataTests still passed, including `resumableDataIsKeptWhenCancelledBeforeServerResponds`. The repo itself was not modified.

Why the impact is low:
- An RFC 9110-compliant server never produces this 416. If the If-Range validator doesn't match, it must ignore Range and send 200, which Nuke handles. If the validator matches, the resource hasn't changed, so the range is satisfiable.
- Hitting it needs three things: a partial download, the resource at the same URL replaced by a shorter one within the process lifetime, and a server that honors Range but ignores If-Range (some object stores/CDNs are reported to do this; I did not verify which ones), or a misbehaving proxy.
- The mock server, which answers 416 to every Range, is a stand-in for that case. Once hit, though, the image cannot load in that pipeline until the entry is evicted.

Other statuses on a resumed request (5xx, 404) also get their data put back. That is arguably desirable for 5xx and harmless for 404, so the fix should target 416 rather than all validation failures.

**Suggested fix:**

In Sources/Nuke/Tasks/TaskFetchOriginalData.swift, pass the error through: have `dataTaskDidFinish(error:)` call `tryToSaveResumableData(error: error)`. Give `tryToSaveResumableData(error: ImagePipeline.Error? = nil)` a default of nil, so the `onCancelled` call site is unchanged. Guard the put-back branch so it does not store data the server rejected:

    } else if let resumableData, !Self.isRangeRejected(error) {
        ResumableDataStorage.shared.storeResumableData(resumableData, ...)
    }

    static func isRangeRejected(_ error: ImagePipeline.Error?) -> Bool {
        if case .dataLoadingFailed(let error as DataLoader.Error)? = error,
           case .statusCodeUnacceptable(416) = error { return true }
        return false
    }

This fix passed the repro and the existing ImagePipelineResumableDataTests in a scratch copy. A broader alternative is to put the data back only on transport-level failures (cancellation or `URLError`) and drop it on any `statusCodeUnacceptable`. Add a regression test that uses a real `DataLoader` with a URLProtocol (the repro file works), and add a CHANGELOG line.


### D43. A resumed 206 without Content-Length reports a progress total below completed (fraction 1.0 mid-download)

_Severity: low · user impact: low · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:254`

**Repro:** [NukeTests/data-loading-tasks--resumed-progress-without-content-length.swift](NukeTests/data-loading-tasks--resumed-progress-without-content-length.swift)

**What:** `TaskProgress(completed: data.count, total: response.expectedContentLength + resumedDataCount)`. When the 206 has an unknown length (-1), the total becomes `resumedDataCount - 1`, which is below the bytes already received, so `fraction` clamps to 1. The diagnostics code in `dataTaskDidFinish` guards the same sum with `expectedContentLength >= 0`; the progress calculation doesn't.

**Expected:** While the download is incomplete, `fraction < 1` and `total` is never below `completed`; an unknown total should be reported as unknown.

**Actual:** The first event is `completed: 14096, total: 9999` (fraction 1.0), and every progress event before the last one is the same way.

**Reproduction check:** Failed 3/3 iterations: every non-final progress event has total 9999, below completed (Progress(completed: 14096, total: 9999), then 18192/9999, then 22288/9999), so fraction == 1. The final data and the 206 status check passed (log: scratchpad/logs/repro-data-loading-tasks-8.log).

**Refutation attempt (failed):**

I could not refute this. It is a real bug, but a narrow one.

Code: Sources/Nuke/Tasks/TaskFetchOriginalData.swift, line 251 at HEAD 2c2b23f6 (the report says 254). In `dataTask(didReceiveData:response:)`, the progress is built as `TaskProgress(completed: Int64(data.count), total: response.expectedContentLength + resumedDataCount)` with no check that the length is known. When a resumed 206 response has no Content-Length, URLResponse gives -1, so `total` becomes `resumedDataCount - 1`. That is below the bytes the task already holds, which include the resumed prefix. Because `total > 0`, `ImageTask.Progress.fraction` returns `min(1, completed/total)`, which is 1.0.

I ran the repro test unchanged in a scratch SwiftPM package (a copy of Sources/Nuke built with `-enable-testing`; the repo itself was not touched). It fails as described. The events were: 14096/9999, 18192/9999, 22288/9999 and 22789/9999, all with fraction 1.0.

Why this is a defect and not intended behavior:
1. The doc comment on `Progress.total` calls it "a best-guess upper bound on the number of bytes of the resource". A value below `completed` breaks that.
2. An existing test in Tests/NukeTests/ImageTaskTests.swift, `progressFractionIsZeroUntilTheTotalIsKnown`, asserts `Progress(completed: 10, total: -1).fraction == 0`. So the convention is that an unknown total means fraction 0. A download that was never resumed follows it (total -1, fraction 0). A resumed download with the same unknown length reports 1.0 instead.
3. `dataTaskDidFinish` in the same file guards the same sum with `urlResponse.expectedContentLength >= 0`. The other uses guard it too: `expectedSize > 0` for `reserveCapacity` and for the size limit, and the progressive-decoding guard fails safe. Only the progress line is missing the guard.
4. Commit 4120ea5f ("Fix progressive previews on a resumed download") and CHANGELOG #187 show that progress on resumed 206 downloads is meant to be correct. Nothing documents this case as intended.

The repro does not misuse the API. The mock implements the public `DataLoading` protocol, and the response it sends is valid HTTP: a 206 must carry Content-Range, but Content-Length is optional (chunked transfer, or HTTP/2 and HTTP/3 without a length). With a real `DataLoader`, URLSession reports -1 for that response. The test uses the internal `makeStartedImageTask`, but the same `.progress` event reaches users through the public `ImageTask.progress` / `events` streams and through NukeUI's `FetchImage` progress.

How often a user hits it: several things must line up. The first response must have Content-Length, `Accept-Ranges: bytes` and an ETag or Last-Modified, which `ResumableData.init` requires. The download must be interrupted. The retry must then get a 206 with no Content-Length. Real servers and CDNs usually do send Content-Length on 206, so this is uncommon.

Impact: cosmetic only. Progress bars jump to 100% for the whole resumed download. The downloaded data and the decoded image are correct. Impact is low.

**Suggested fix:**

In `dataTask(didReceiveData:response:)` in TaskFetchOriginalData.swift, report an unknown total as unknown, the same way a download that was never resumed does:

    let expectedLength = response.expectedContentLength
    let total = expectedLength >= 0 ? expectedLength + resumedDataCount : -1
    send(progress: TaskProgress(completed: Int64(data.count), total: total))

Optionally, when `expectedContentLength < 0` on a 206, take the full size from the `Content-Range` header ("bytes start-end/size") when it is not "*".

Add a regression test to ImagePipelineResumableDataTests: resume with a 206 that has no Content-Length, then assert `fraction < 1` and `total <= 0 || total >= completed` for every progress event except the last.


### D44. An empty local file or empty data: URL succeeds with zero bytes instead of failing with dataIsEmpty

_Severity: low · user impact: low · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:40`

**Repro:** [NukeTests/data-loading-tasks--empty-local-resource-succeeds.swift](NukeTests/data-loading-tasks--empty-local-resource-succeeds.swift)

**What:** The network path (`dataTaskDidFinish`) and the closure path (`asyncDataDidFinish`) both reject empty data with `.dataIsEmpty`. The local-resource branch in `start()` sends whatever `Data(contentsOf:)` returns without that check. So `data(for:)` returns `(Data(), nil)` for a zero-length file or `data:image/jpeg;base64,`, and `image(for:)` fails in the decoder with an error that doesn't say the data was empty.

**Expected:** `ImagePipeline.Error.dataIsEmpty`, the same as for an empty download. The repro's control case confirms that behavior for the loader path.

**Actual:** `data(for:)` returns "(0 bytes, nil)" without throwing.

**Reproduction check:** emptyFileFailsWithDataIsEmpty and emptyDataURLFailsWithDataIsEmpty failed 3/3 iterations: 'an error was expected but none was thrown and "(0 bytes, nil)" was returned'. The control case emptyDownloadFailsWithDataIsEmpty passed (log: scratchpad/logs/repro-data-loading-tasks-10.log).

**Refutation attempt (failed):**

I could not refute this. It reproduces with only the public API and the default configuration, and the fetch task's own design history backs up the claim.

What I found:
1. I ran the repro in a scratch clone at HEAD 2c2b23f6 (macOS, scheme Nuke). With the default settings, both `emptyFileFailsWithDataIsEmpty` and `emptyDataURLFailsWithDataIsEmpty` fail: `data(for:)` returns "(0 bytes, nil)" and throws nothing. The loader control case passes with `.dataIsEmpty`.
2. I added probes with the real DataLoader/URLSession by setting `isLocalResourcesSupportEnabled = false`. There, a zero-byte file and `data:image/jpeg;base64,` both fail with `.dataIsEmpty` ("Data loader returned empty data.") from both `data(for:)` and `image(for:)`. With the fast path on (the default), `image(for:)` instead fails with `.decodingFailed(ImageDecoders.Default)`. So the same URL gives a different result depending only on whether the fast path is on.
3. CHANGELOG line 344 (PR #779) calls the local-resource path "an optimization that loads local resources ... quickly without using DataLoader" and offers the flag "if you rely on the existing behavior". An optimization is not meant to change which error comes back, so this is a regression from that change, not a design decision.
4. Commit 53958907 removed the empty-data check from the decode task, with the comment "TaskLoadData does it. No need to check this twice." The fetch task was meant to be the one place that turns away empty data. The network path (`dataTaskDidFinish`) and the closure path (`asyncDataDidFinish`) still do. The local branch, added two years later in 39c537ee, skips that check. That looks like an oversight: its commit message says nothing about empty data.
5. No existing test expects an empty local resource to succeed. `ImagePipelineLocalResourcesTests` only covers missing files and malformed data URLs, which get `.dataLoadingFailed`.
6. The repro uses the API correctly. It needs no @testable-only paths and no mock behavior: the failing cases never reach MockDataLoader, and the fast path reads the file with `Data(contentsOf:)`. ImageIO and URLSession are not the cause, since URLSession on the same input leads to `.dataIsEmpty`.

The one counter-argument is that the doc comment for `.dataIsEmpty` says "Data loader returned empty data." and the fast path has no data loader. But the `.data` closure path has no data loader either and still sends `.dataIsEmpty`, so the error clearly covers any empty source.

Impact is low. Zero-byte local files do happen (truncated or partly written downloads, empty app-group files, empty data URIs from servers). When they do, `data(for:)` hands back empty `Data` as a success, and prefetching with a data destination reports success. `image(for:)` still fails, but with a decoder error, so code that matches on `.dataIsEmpty` misses it. Nothing bad gets cached, because local resources are never written to the disk cache.

**Suggested fix:** Sources/Nuke/Tasks/TaskFetchOriginalData.swift, local-resource branch of start(): after `let data = try Data(contentsOf: url)` and the `diagnostics?.endStage(stage) { ... }` call, add `guard !data.isEmpty else { send(error: .dataIsEmpty); return }` before `send(value: (data, nil), isCompleted: true)`. This matches `dataTaskDidFinish` and `asyncDataDidFinish`. Optionally, change the `.dataIsEmpty` doc comment and description in ImagePipeline+Error.swift from "Data loader returned empty data." to something source-neutral, such as "The loaded data is empty." Add tests to ImagePipelineLocalResourcesTests for a zero-byte file and for `data:image/jpeg;base64,`, both expecting `.dataIsEmpty` from `data(for:)` and `image(for:)` with `dataLoader.createdTaskCount == 0`. Add a short CHANGELOG entry.


### D45. A download the delegate refused (willLoadData threw) is stamped source=network with 0 bytes, and the task reports "transfer: 0 bytes"

_Severity: low · user impact: low · public API: yes · found by: diagnostics_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:264`

**Repro:** [NukeTests/diagnostics--never-started-download-reports-transfer.swift](NukeTests/diagnostics--never-started-download-reports-transfer.swift)

**What:** `dataTaskDidFinish` runs `diagnostics?.endStage(downloadStage) { stage.source = … .network; stage.bytes = Int64(data.count); stage.resumedBytes = … }` for every failure. That includes an error thrown by `ImagePipeline.Delegate.willLoadData`, which happens before `startStage(downloadStage)` is ever called. The stage keeps `startedAt == nil` (it prints "never started") but gets `source = .network` and `bytes = 0`. `TaskRecord.bytes(of:)` then copies `Bytes(downloaded: 0, resumed: 0, expected: 0)` into the task record. The docs say `Stage.source` is "Where a download got the data from" and `Metrics.bytes` is "The bytes of the download the task waited on, if any"; a download that never started got nothing from anywhere.

**Expected:** `download.source == nil`, `download.bytes == nil`, `metrics.bytes == nil`, and no `transfer:` line in the header.

**Actual:** The header has `transfer:  0 bytes`, and the timeline has `├─ download 0.2 ms █████████ 44% never started · network · 0 bytes`.

**Reproduction check:** Failed 3/3. `download.source == .network`, `download.bytes == 0`, and `metrics.bytes != nil`. The header has `transfer:  0 bytes`, and the timeline has `├─ download 0.4 ms ██████████ 51% never started · network · 0 bytes`, with `dataLoader.createdTaskCount == 0`. The breakdown also reads `network 0.4 ms (51%)` for this download that never ran, which is bug 1 again.

**Refutation attempt (failed):**

I could not refute it. I ran the repro against an unmodified copy of the sources (macOS, NukeTests; copy at /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-neverstarted-dl). All four expectations fail. `metrics.bytes` is `Bytes(downloaded: 0, resumed: 0, expected: 0)`, and the report prints `transfer:  0 bytes` in the header and `download ... never started · network · 0 bytes` in the timeline.

How it happens: in Sources/Nuke/Tasks/TaskFetchOriginalData.swift, `performDataLoad` calls `diagnostics?.startStage(downloadStage)` only after `pipeline.willLoadData` returns. When the delegate throws, control goes to the outer `catch`, which calls `dataTaskDidFinish(error:)`. That function always runs `endStage(downloadStage) { stage.source = ... ? .httpCache : .network; stage.bytes = Int64(data.count); ... }`. `JobRecord.endStage` applies the update even when `startedAt == nil`; only `Stage.end(at:)` checks for a stage that never started. `TaskRecord.bytes(of:)` then turns the non-nil `stage.bytes` into `Metrics.bytes`.

Why it is not a misuse or a test artifact:
- The path uses only public API. The `willLoadData` doc says throwing is supported "for example, when a token refresh fails", and that the request then fails with `dataLoadingFailed`.
- The test uses no @testable-only entry point.
- It does not depend on the mock or on timing: the failing call returns before the data loader is reached (`createdTaskCount == 0`).

Intent: nothing in the commits (226f3da9 "Record where the time of every image task went", fee87ca5 "Rework the metrics report"), the CHANGELOG or the docc says a download that never started should carry a source or bytes. The comment above the `endStage` call assumes a load actually happened ("URLSession collected its metrics before the continuation that brought us here resumed"). The docs contradict the output: `Stage.source` is "Where a download got the data from", and the report puts "never started" and "network · 0 bytes" on the same row.

Why the impact is low:
- It affects diagnostics only, which are off by default and new in the unreleased section of the CHANGELOG.
- Image loading and the error itself are correct, and `Metrics.source` is already nil for any failure.
- `transfer: 0 bytes` on a failure is partly the existing convention. As a control, a download that started and failed (`notConnectedToInternet`) also prints `transfer: 0 bytes` and `network · 0 bytes`, and the existing test `failureCarriesTheErrorCode` expects `.network` for that case.
- What is wrong is narrower: a stage that never started claims a network source and a byte count. A logger that reads `metrics.bytes != nil` as "a request went out" will miscount delegate refusals.

The same report also counts the unstarted download as `network 0.5 ms (43%)` in the `time:` line. That is a separate problem (see bugs/diagnostics--never-started-stage-counted-as-work.swift) and not part of this finding.

**Suggested fix:**

In `TaskFetchOriginalData.dataTaskDidFinish`, stamp the transfer only on a stage that actually started. Keep the call to `dataTaskDidFinish`, because it also runs `tryToSaveResumableData()`, which puts back the resumable data that `performDataLoad` took out before calling `willLoadData`:

```swift
diagnostics?.endStage(downloadStage) { stage in
    guard stage.startedAt != nil else { return } // e.g. `willLoadData` threw
    stage.source = stage.urlSessionMetrics?.isServedFromCache == true ? .httpCache : .network
    stage.bytes = Int64(data.count)
    ...
}
```

Add a regression test to ImagePipelineDiagnosticsTests. It should use a delegate whose `willLoadData` throws, and assert that the download stage has `startedAt == nil`, `source == nil` and `bytes == nil`, that `metrics.bytes == nil`, and that the description has no `transfer:` line.


### D46. Time a cancelled task spent held by the rate limiter is lost: no rateLimit stage, and the wait is reported as `other`

_Severity: low · user impact: low · public API: yes · found by: diagnostics_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:51`

**Repro:** [NukeTests/diagnostics--rate-limiter-wait-lost-on-cancel.swift](NukeTests/diagnostics--rate-limiter-wait-lost-on-cancel.swift)

**What:** The `rateLimit` stage is recorded only from inside the work the limiter eventually runs (`if isDeferred, let queuedAt { recordStage(.rateLimit, from: queuedAt) }`, after `guard let self, !self.isDisposed else { return false }`). A job cancelled while it is still pending in the limiter records nothing. By contrast, a download waiting for `dataLoadingQueue` is recorded from the moment it is enqueued. The docs say `Category.rateLimit` is "The wait in rateLimiter", `Stage.Kind.rateLimit` is "The time the request spent in the rate limiter", and `other` is only for time before the start, hops between jobs, and work nobody timed. The repro fills the limiter with 200 dummy work items so the task's request is held, then cancels the task.

**Expected:** The cancelled task's fetchOriginalData job has a `rateLimit` stage, and `timeShares` contains `.rateLimit`.

**Actual:** `time: other 28.5 ms (100%)`, and `j6 fetchOriginalData` has no stages at all.

**Reproduction check:** Failed 3/3. `fetch.stages.contains { $0.kind == .rateLimit }` is false and timeShares has no `.rateLimit`. The report is `time: other 0.7 ms (100%)`, and `j3 fetchOriginalData` has no stage rows. In my runs the task was held only about 0.1-0.3 ms before the cancel, not 28 ms, but no stage is recorded however long the hold.

**Refutation attempt (failed):**

I could not refute this. The defect is real, reachable through the public API, and it contradicts the documented categories. Its impact is limited to the accuracy of diagnostics.

Code (HEAD 2c2b23f6, Sources/Nuke/Tasks/TaskFetchOriginalData.swift:48-65): the `rateLimit` stage is written only by `recordStage(.rateLimit, from: queuedAt)` inside the closure the limiter eventually runs. That line comes after `guard let self, !self.isDisposed else { return false }`. So a job that is disposed while its closure is still in `RateLimiter.pending` never records the wait. `JobRecord.finish` closes any running stages on cancel, but no stage was ever begun here, so there is nothing for it to close. A download waiting in dataLoadingQueue is different: `beginStage(.download, queued: true)` records it from the moment it is enqueued.

History and intent: commit 226f3da9 ("Record where the time of every image task went", PR #960) added the recordStage-after-the-fact pattern. Neither that commit message nor the CHANGELOG entry mentions this limitation. The only related remark is in commit 0459b49f ("the rate limiter ... is recorded once it's already over"), which explains why the stage has no signpost. It says nothing about cancelled tasks, and that commit and the rate-limiter-removal branch (#963) are not on main or HEAD.

Docs: `Category.rateLimit` is "The wait in rateLimiter" and `Stage.Kind.rateLimit` is "The time the request spent in the rate limiter". `other` is described as the time before start, the hops between jobs, and work that isn't bracketed. The performance guide says the rate limiter exists for apps that "start and cancel requests at a fast rate". Cancelled tasks are exactly the ones the limiter holds, so this is the main case for the limiter, not an edge case.

Reproduced on macOS with xcodebuild, using a copy of the repo in scratchpad/refute-ratelimit-cancel; the repo itself was not modified.
- The original repro fails as described: `time: other 2.2 ms (100%)` and fetchOriginalData has no stages.
- A variant that uses only public API also reproduces it. It starts 60 plain `imageTask(with:)` tasks on a default pipeline (limiter on by default, burst 25) and cancels the last one after 50 ms. Result: `time: other 52.4 ms (100%)`, and `j180 fetchOriginalData` has no stages and no queued download stage, which confirms the task was held in the limiter.
- Control: with the same backlog and the task allowed to finish, the record correctly shows `rateLimit 168.2 ms (81%)`. So only the cancel path loses the wait.

This is not a test artifact: the 200 dummy closures in the original repro just use up tokens the way real requests do, and the public variant needs no @testable hooks.

Impact is low. Diagnostics are opt-in and not yet released (Nuke 14 WIP), and no loading behaviour changes. But a task cancelled during a fast scroll gets a record with an empty fetch job and 100% `other`, which gives no hint that the rate limiter held it, and that is the question such a record would be read for.

Side note: the comparison case shows a separate bug that is already filed as diagnostics--never-started-stage-counted-as-work. A download cancelled while waiting in dataLoadingQueue is charged to `network` ("network 31.3 ms (97%) · download never started") instead of `queue`, because `timeShares` only splits out the queue part when `startedAt` is set.

**Suggested fix:**

Open the stage when the limiter holds the request, and close it when the work runs. JobRecord.finish already closes running stages when the job is cancelled, so a cancelled task keeps the wait up to the cancel. In TaskFetchOriginalData.start():

```swift
if let rateLimiter = pipeline.rateLimiter {
    var didRun = false
    var rateLimitStage: Int?
    rateLimiter.execute { [weak self] in
        guard let self, !self.isDisposed else { return false }
        didRun = true
        self.diagnostics?.endStage(rateLimitStage)
        self.loadData(urlRequest: urlRequest)
        return true
    }
    if !didRun {
        // The limiter held the request; finish(.cancelled) closes this stage if the job is cancelled first.
        rateLimitStage = diagnostics?.beginStage(.rateLimit)
    }
}
```

This drops the `queuedAt`/`isDeferred`/`recordStage` path. The stage is still appended before the download stage, so the timeline order does not change. Add a test next to cancellationIsRecorded in ImagePipelineDiagnosticsTests: fill the limiter, start a task, cancel it while held, then check that `jobs.last` has a `.rateLimit` stage with a duration and that `timeShares` contains `.rateLimit`.


### D47. Time spent in the delegate's willLoadData is reported as a wait for dataLoadingQueue; the willLoadData → other mapping can never take effect

_Severity: low · user impact: low · public API: yes · found by: diagnostics_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:118`

**Repro:** [NukeTests/diagnostics--review-will-load-data-counted-as-queue.swift](NukeTests/diagnostics--review-will-load-data-counted-as-queue.swift)

**What:** `downloadStage` is begun as queued in `loadData(urlRequest:)` (line 72). The queue runs `performDataLoad`, which awaits `pipeline.willLoadData` (lines 118-125), and only after that calls `diagnostics?.startStage(downloadStage)` (line 130). So the download's `queuedAt..startedAt` interval covers the whole delegate call. `timeShares` (ImageTask+Metrics.swift:280-284) charges that interval to `.queue` (rank 1). The overlapping `.willLoadData` stage maps to `.other` (rank 7, last), so the delegate's time always lands in `queue` and never in `other`. The timeline's `dataLoadingQueue` row (`split`, ImageTask+MetricsFormat.swift:432-438) spans the delegate too. Docs: `Category.queue` is "The wait for one of the queues in ImagePipeline.Configuration, which is where the time goes when the pipeline is busy"; `Stage.queueWait` is "The time the work waited for its queue". On an idle pipeline with a 50 ms token-refresh delegate, the breakdown sends the reader to `dataLoadingQueue`. Note: the existing ImagePipelineDiagnosticsTests.willLoadDataIsRecordedForCustomDelegates pins `queueWait >= 0.02`, with the comment that the wait includes the delegate. The breakdown is still at odds with the Category docs whichever way `queueWait` is defined.

**Expected:** With one task on an idle pipeline and a delegate that takes 50 ms, the delegate's time is not counted as `queue`: `queue <= duration - willLoadData`.

**Actual:** `time: queue 78.5 ms (95%) · decode 0.4 ms (1%) · network 0.1 ms · other 3.8 ms (5%)` for an 82.9 ms task whose willLoadData took 53.4 ms. The timeline shows `dataLoadingQueue 78.5 ms` drawn over the `willLoadData 53.4 ms` row.

**Reproduction check:** The original repro failed only 2 of 3 iterations. Repetition 1 passed because its loose bound `queue <= duration - willLoadData` holds whenever the rest of the task takes longer than the delegate, and a cold first run does (a cold first decode/download took ~35 ms). The corrected repro asserts `queue < willLoadData` with a 100 ms delegate, covers `.skipDataLoadingQueue` on and off, and failed in 6/6 cases. Default path: `time: queue 104.0 ms (99%) · network 0.8 ms · decode 0.4 ms · other 0.1 ms`, with `├─ dataLoadingQueue 104.0 ms ░░░…` drawn over `├─ willLoadData 104.0 ms ███…`. With `.skipDataLoadingQueue`, where the request never enters that queue, the breakdown is still `queue 103.1 ms (74%)` and the timeline still prints a `dataLoadingQueue 103.1 ms` row.

**Refutation attempt (failed):**

I could not refute it. I reproduced it using only the public API. I built a separate SwiftPM probe in the scratchpad (scratchpad/wldprobe) that depends on Nuke by path, with no @testable and no test mocks. It used a custom DataLoading that returns an 8×8 PNG at once, a delegate that sleeps 50 ms in willLoadData, and an idle pipeline with isDiagnosticsEnabled. The repo was not modified. Output: `time: queue 50.2 ms (64%) · decode 28.4 ms (36%) · network 0.1 ms · other 0.4 ms`. The timeline has a `dataLoadingQueue 50.2 ms` row over a `willLoadData 50.2 ms` row, and download.queueWait = 50.2 ms, even though the queue admitted the work at once.

Mechanism, confirmed by reading the code: loadData(urlRequest:) begins the download stage with `queued: true` (TaskFetchOriginalData.swift:72). The dataLoadingQueue operation runs performDataLoad, which awaits pipeline.willLoadData (:118-125). Only then does it call startStage(downloadStage) (:130). So [queuedAt, startedAt) always contains the whole willLoadData stage. timeShares (ImageTask+Metrics.swift:280-284) gives that interval to `.queue` (rank 1). `.willLoadData` maps to `.other` (rank 7), so that mapping never wins for any time. The same holds with .skipDataLoadingQueue, because that path is also begun with queued: true.

There is a worse variant with the same root cause. I added a delegate that sleeps 50 ms and then throws. The download stage never gets a startedAt, so timeShares falls into the else branch and charges the whole queuedAt→end span to category(of: .download). Output: `time: network 56.5 ms`, for a request that never reached the network.

Is it intentional? Partly. The test ImagePipelineDiagnosticsTests.willLoadDataIsRecordedForCustomDelegates pins `queueWait >= 0.02` ("its wait includes the delegate"). Commit 80094139 describes the delegate as running "inside" the dataLoadingQueue row, and orders the rows to match. So queueWait and the timeline row are known and accepted behaviour.

The public docs point the other way, though:
- Category.queue: "The wait for one of the queues in ImagePipeline.Configuration, which is where the time goes when the pipeline is busy."
- Stage.queueWait: "The time the work waited for its queue."
- The performance guide: "The `time:` line names the part worth making faster."
- The maintainer's own diagnostics proposal names willLoadData time as one of two things the feature should make visible. It says a token refresh "shows up in Instruments as 'download'". Its sample print separates "queued 0.2 ms · willLoadData 1.5 ms".

As it stands, the time: line sends a reader with a slow token-refresh delegate to dataLoadingQueue (for example, to raise its concurrency, which won't help). A throwing delegate is shown as network time. No docs, CHANGELOG entry or commit ever says the delegate's time is meant to be charged to queue or network in the breakdown. The repro does not misuse the API: willLoadData is the documented auth hook, and the behaviour is deterministic, not a timing artifact of the test harness.

Impact is low. The feature is opt-in and unreleased (Nuke 14 WIP). The willLoadData row with its correct duration still appears in the full timeline. The wrong part is the summary line and the queue row, which is what someone reading the timeShares summary would act on.

**Suggested fix:**

End a queued stage's wait when the queue admits the work, not when the stage itself starts. A minimal fix in the analysis layer, which also needs no schema change:

1. In ImageTask.Metrics.timeShares (ImageTask+Metrics.swift:278-288), compute the end of the queue for a stage with queuedAt as follows:
   - Let `admittedAt` be the earliest startedAt of another stage in the same job that begins inside [span.from, stage.startedAt ?? span.to), which is the willLoadData stage.
   - Set `queueEnd = min(admittedAt ?? stage.startedAt ?? span.to, span.to)`.
   - Append (.queue, span.from..queueEnd).
   - Append (category(of: stage.kind), max(startedAt, queueEnd)..span.to) only when the stage actually started. A download that never left the queue, or whose delegate threw or was cancelled, then gets no network interval.
   The willLoadData stage then gets its own time, as `.other` or better as a new category such as `.delegate` placed before `.queue`.

2. Apply the same end-of-queue rule in `split(_:in:)` (ImageTask+MetricsFormat.swift:432-438), so the dataLoadingQueue row stops at the delegate's start.

3. Either change the recording so it keeps the admission time (for example, start the willLoadData stage and record the download's dequeue at the top of performDataLoad/performAsyncDataLoad), or document that Stage.queueWait for a download includes willLoadData.

4. Update willLoadDataIsRecordedForCustomDelegates: the queue share of an idle pipeline should be about 0, the delegate's time should not be counted as queue, and a throwing delegate should produce no `network` share.


### D48. A download cancelled after receiving data records its first byte and status but not the bytes received or the announced size, so the task has no transfer field

_Severity: low · user impact: low · public API: yes · found by: diagnostics_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:261`

**Repro:** [NukeTests/diagnostics--review-cancelled-download-drops-bytes.swift](NukeTests/diagnostics--review-cancelled-download-drops-bytes.swift)

**What:** The download stage's `bytes`, `resumedBytes`, `expectedBytes` and `source` are written only in `dataTaskDidFinish` (lines 261-272). That function returns early for a disposed job (`guard !isDisposed else { return }`) and is never reached on cancellation. `JobRecord.finish(.cancelled)` (DiagnosticsRecorder.swift:261-271) closes the stage without them, while `recordFirstByte` has already set `firstByteAt` and `statusCode`. So a download cancelled after receiving 1/3 of the file says it got its first byte with HTTP 200, and nothing about how much arrived. `TaskRecord.bytes(of:)` then finds no bytes, and `Metrics.bytes` is nil. A failure partway through a download, by contrast, records bytes and expectedBytes. Docs: `Stage.bytes` is "The bytes downloaded, read, or written"; `Metrics.bytes` is "The bytes of the download the task waited on, if any"; the header's transfer text is documented to say "what the server announced if the download stopped short of it", and cancellation is the usual way a download stops short (fast scrolling).

**Expected:** `download.bytes == 13152` (bytes received before the cancel), `download.expectedBytes == data.count`, `metrics.bytes?.downloaded == 13152`, and a `transfer:` header field such as `13 KB of 39 KB`.

**Actual:** `download.bytes == nil`, `expectedBytes == nil`, `metrics.bytes == nil`, and no `transfer:` field, while `firstByteAt` and `statusCode` are set.

**Reproduction check:** Failed 3/3. The failure reads `bytes nil, 13152 received`, and `download.expectedBytes` is nil where 39456 was expected. `metrics.bytes` is nil and there is no `transfer:` field. The timeline row is `└─ download 7.2 ms ███ 92% HTTP 200 · first byte 0.1 ms`, so the first byte and status are recorded but no source or byte count.

**Refutation attempt (failed):**

I couldn't refute it. The behavior is real, it comes from Nuke's own code, and a user reaches it through public API alone. I ran the repro against a clean `git archive HEAD` copy of the repo (xcodebuild, macOS, -only-testing). All four expectations failed: `download.bytes`, `download.expectedBytes`, `metrics.bytes?.downloaded` and the `transfer:` header field. The preconditions held: `firstByteAt` was set and some bytes had been received.

Why it happens, in the code:
1. `TaskFetchOriginalData.dataTaskDidFinish` (Sources/Nuke/Tasks/TaskFetchOriginalData.swift:260-272) is the only place a URL download's `bytes`, `resumedBytes`, `expectedBytes` and `source` are written.
2. On cancellation, `AsyncTask.terminate(.cancelled)` (AsyncTask.swift:221-231) calls `diagnostics?.finish(.cancelled)`. That `JobRecord.finish` (DiagnosticsRecorder.swift:261-271) closes the running stages' durations and nothing else. It then runs `onCancelled`, which cancels the loader and saves resumable data but records nothing.
3. All of this happens synchronously inside `imageTaskCancelCalled`, before `ImageTask._cancel()` takes the `TaskRecord.finish` snapshot.
4. Later the loader's completion resumes the continuation, and `dataTaskDidFinish(error:)` returns at `guard !isDisposed`. Even without that guard, the task's snapshot has already been taken.

So this isn't something the mock causes. It happens the same way with the real `DataLoader` and `URLSession`.

Is it intended or documented? I found nothing saying so. The commits (226f3da9, 58ec360f), the CHANGELOG entry for PR #960 and the performance guide never say cancelled downloads drop their byte counts, and no test asserts it (`cancellationIsRecorded` checks only outcome and endedAt). The record contradicts itself: a download that fails partway records bytes and expectedBytes, while one cancelled partway records `firstByteAt` and `HTTP 200` but no size. The docs point the other way: `Stage.bytes` is "The bytes downloaded, read, or written", `Metrics.bytes` is "The bytes of the download the task waited on", and the transfer header is documented to show "what the server announced if the download stopped short of it". The author also made `urlSessionTaskID` work "for a task that ended before the download did", so tasks ending mid-download were a case they designed for.

Why impact is only low: diagnostics are opt-in, the feature is still unreleased (Nuke 14 WIP), and loading, caching and resumable data are unaffected. The only harm is a record that leaves out bytes for cancelled downloads. That matters mostly in fast scrolling, which is exactly when someone would look for wasted bandwidth.

A related case is different and fine: a task leaves a coalesced download that keeps running. Its copy shows a running stage with no bytes, which matches the documented "outlived the task" meaning. That case is not part of this report.

**Suggested fix:**

In TaskFetchOriginalData.swift, move the transfer fields into one helper and call it from the cancellation path as well. Neither `JobRecord.finish` nor `Stage.end` needs to change.

```swift
private func recordTransfer(into stage: inout ImagePipeline.Diagnostics.Stage) {
    stage.source = stage.urlSessionMetrics?.isServedFromCache == true ? .httpCache : .network
    stage.bytes = Int64(data.count)
    stage.resumedBytes = resumedDataCount
    if let urlResponse, urlResponse.expectedContentLength >= 0 {
        stage.expectedBytes = urlResponse.expectedContentLength + resumedDataCount
    }
}
```

Then:
- `dataTaskDidFinish` uses `diagnostics?.endStage(downloadStage) { recordTransfer(into: &$0) }`.
- The `onCancelled` closure set in `performDataLoad` adds `if urlResponse != nil { self.diagnostics?.updateStage(self.downloadStage) { self.recordTransfer(into: &$0) } }` next to `tryToSaveResumableData()`. The `urlResponse != nil` guard keeps a download that received nothing from claiming 0 bytes.

This works because `onCancelled` runs synchronously inside `terminate(.cancelled)`, before `ImageTask._cancel()` takes its snapshot, so the cancelled task's copy of the job now carries the bytes. `updateStage` on a stage that is already closed is fine: it just mutates the stage.

Add a regression test like the repro (MockProgressiveDataLoader, cancel after the first chunk), and check `transfer:` reads "13 KB of 39 KB".


### D49. A late progressive decode or processing operation clears the handle to the final operation, so the final one can't be cancelled or re-prioritized

_Severity: low · user impact: low · public API: yes · known: defects.md #18 · found by: image-decode-process-tasks_

**Where:** `Sources/Nuke/Tasks/AsyncPipelineTask.swift:96`

**Repro:** [NukeTests/image-decode-process-tasks--stale-progressive-operation-clobbers-final-operation.swift](NukeTests/image-decode-process-tasks--stale-progressive-operation-clobbers-final-operation.swift)

**What:** When the final data or image arrives while a preview is being decoded or processed, the task cancels the preview operation (it keeps running) and stores the final operation in `operation`. When the preview operation finishes, it runs `operation = nil` unconditionally and drops the final operation's handle. The same pattern is at TaskLoadImage.swift:94 (process) and in the decompression closure. After that, AsyncTask.terminate(.cancelled) and priority changes can't reach the final operation. The fix is to clear the handle only if it still refers to the finishing operation.

**Expected:** Cancelling the ImageTask cancels the outstanding final decode or processing operation.

**Actual:** The final operation's isCancelled stays false, and it runs to completion for nobody. Reproduced for both decode and processing.

**Reproduction check:** Both the decode and the processing variants failed on all 3 iterations at `operations.operations.last?.isCancelled == true`. The first (preview) operation was cancelled; the final one was not.

**Refutation attempt (failed):**

I could not refute this; the bug is real. The code does what the report says. When the final data or image arrives, `TaskFetchOriginalImage.didReceiveData` (line 53), `TaskLoadImage.process` (line 72) and `TaskLoadImage.didReceiveImageResponse` (line 127) cancel the preview operation and store the new one in `operation`. Cancelling a running `TaskQueue.Operation` only sets `isCancelled` and calls `Task.cancel()`. The work runs through `performInBackground`, which never checks for cancellation, so the preview closure keeps going. It then runs `self?.operation = nil` unconditionally (AsyncPipelineTask.swift:66/92, TaskLoadImage.swift:95/143) and drops the handle to the final operation. After that, `AsyncTask.terminate(.cancelled)`, which calls `operation?.cancel()`, and `priority.didSet`, which sets `operation?.priority`, cannot reach it.

Nothing documents this as intended. The `AsyncTask.operation` doc says the outstanding operation is cancelled when the task is cancelled. The `decode` doc says the handle is cleared "so the callers never see a stale handle". Commit 9f6e0d23 moved the clearing into the closures without considering this overlap. CHANGELOG PR #898 fixed the sibling case, where an outstanding progressive operation was not cancelled when a task failed and so occupied a queue slot. So the maintainer does treat leftover queued work as a bug.

Caveat on the repro: its scenario has no visible effect by itself. There the final operation is already running, and cancelling a running synchronous decode or process does not stop it anyway. Only the `isCancelled` flag differs.

I checked for a visible effect with my own test in a `git archive` copy under the scratchpad (the repo was not touched). Setup: `imageDecodingQueue = TaskQueue(maxConcurrentTaskCount: 1)`, progressive decoding on, a gated preview decode, and another decode queued ahead of the final one (standing in for another image's decode). The public `pipeline.imageTask`, `task.cancel()` and `task.priority` then show:
- After cancelling, the pending final operation stays `isCancelled == false` and `decode(_:)` still runs for nobody (count = 1).
- Raising `task.priority` to `.veryHigh` leaves the pending final operation at `.normal`.

The original repro's two tests also fail on HEAD as described. With the candidate fix applied in the copy, both repro tests, both of my tests, and the progressive decoding, pipeline and related suites pass (43 tests).

Impact is low. Progressive decoding is opt-in (`isProgressiveDecodingEnabled = false` by default). A preview decode or process must still be running when the final data or image arrives. And the final operation must still be waiting in a busy queue when the task is cancelled or re-prioritized. The result is wasted CPU and a decode, processing or decompression queue slot taken from other images (the same class as #898). Priority changes are also lost. Nothing is delivered wrong, nothing crashes, and nothing leaks.

**Suggested fix:** Clear the handle only when the finishing operation is still the one stored. The smallest version, verified in a scratch copy: in all four closures (Sources/Nuke/Tasks/AsyncPipelineTask.swift:66 and :92, Sources/Nuke/Tasks/TaskLoadImage.swift:95 for process and :143 for decompress), replace the unconditional clear with `if !Task.isCancelled { self?.operation = nil }` (use `self.operation` in TaskLoadImage). A running operation's Task is cancelled exactly when its handle was cancelled, either by the replacement final operation or by termination, so a superseded preview no longer clears the final operation's handle. An alternative is an identity check through a small `@ImagePipelineActor` box that holds the returned operation, so the closure can test `self.operation === box.operation`. Add a regression test in ImagePipelineProgressiveDecodingTests with these steps: a 1-slot decoding queue; a gated preview decode; a blocker operation queued before the final data arrives; release the preview; cancel the task. Then assert the final operation `isCancelled` and that `decode(_:)` never runs. Add the same test for processing.


### D50. .skipDataLoadingQueue is ignored for ImageRequest(id:image:)

_Severity: low · user impact: low · public API: yes · found by: image-decode-process-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalImage.swift:138`

**Repro:** [NukeTests/image-decode-process-tasks--image-closure-ignores-skip-data-loading-queue.swift](NukeTests/image-decode-process-tasks--image-closure-ignores-skip-data-loading-queue.swift)

**What:** loadAsyncImage always adds the closure to dataLoadingQueue. URL requests and ImageRequest(id:data:) both bypass the queue when the option is set; the repro includes the passing data-closure case as a control.

**Expected:** Doc: "Perform data loading immediately, ignoring dataLoadingQueue." The closure should run even when the queue is suspended or full.

**Actual:** The closure never runs while dataLoadingQueue is suspended; the test expectation times out.

**Reproduction check:** imageClosureSkipsTheDataLoadingQueue failed on all 3 iterations with `TestExpectation timed out after 10.0 seconds` because the closure never ran. The control dataClosureSkipsTheDataLoadingQueue (ImageRequest(id:data:) with the same option and suspended queue) passed all 3 times.

**Refutation attempt (failed):**

I could not refute this. It is a real, public-API-reachable bug.

The doc on `ImageRequest.Options.skipDataLoadingQueue` (Sources/Nuke/ImageRequest.swift:340-344) says "Perform data loading immediately, ignoring dataLoadingQueue". No per-resource exception is documented anywhere: not in the ImageRequest docs, CHANGELOG or Documentation/*.docc. The pipeline itself treats the `image:` closure as data loading. `TaskFetchOriginalImage.loadAsyncImage` (line 138) schedules the closure on `pipeline.configuration.dataLoadingQueue` and records it as the `.download` diagnostics stage. So the option should cover it.

History points to an oversight, not a design choice. Commit 43c5eaa3 ("Add new init(id:image:...) to ImageRequest") built `loadAsyncImage` by copying `TaskFetchOriginalData.loadAsyncData`. At that commit, `loadAsyncData` already had the `if request.options.contains(.skipDataLoadingQueue) { Task {...} } else { queue.add }` branch. The copy kept only the `else` arm. The commit message, the CHANGELOG entry and the added tests say nothing about the option. A later fix (CHANGELOG line 137, about cancelling the `skipDataLoadingQueue` Task) touched only `TaskFetchOriginalData`, which fits the image path being missed again.

The repro only uses public API: `ImageRequest(id:image:options:)`, `ImagePipeline.imageTask(with:)`, and the public nonisolated `TaskQueue.isSuspended`. Existing tests already use a suspended queue to check this option for the URL and `data:` paths (ImagePipelineTests.swift:486-510). This is Nuke's own scheduling code, with no platform or mock artifact involved.

I verified it by running the repro against a `git archive HEAD` copy in the scratchpad. `dataClosureSkipsTheDataLoadingQueue` passed and `imageClosureSkipsTheDataLoadingQueue` timed out after 10 s. I then added the missing branch in the copy. After that, both repro tests and all of ImagePipelineAsyncAwaitTests passed (27 tests).

User impact is low. With the default unsuspended queue, the closure is only delayed, not blocked forever: it waits behind up to maxConcurrentTaskCount running loads (6 by default) and whatever is queued ahead. It never runs only if the app suspends the queue. Still, a user who sets the option to raise the priority of a Photos- or memory-backed `image:` request gets none of the documented effect.

**Suggested fix:**

In Sources/Nuke/Tasks/TaskFetchOriginalImage.swift, make `loadAsyncImage` match `TaskFetchOriginalData.loadAsyncData`:

```swift
private func loadAsyncImage(_ fetch: @Sendable @escaping () async throws -> ImageContainer) {
    let stage = diagnostics?.beginStage(.download, queued: true)
    if request.options.contains(.skipDataLoadingQueue) {
        let task = Task { [weak self] in
            await self?.performAsyncImageLoad(fetch, stage: stage)
        }
        onCancelled = { task.cancel() }
    } else {
        operation = pipeline.configuration.dataLoadingQueue.add { [weak self] in
            await self?.performAsyncImageLoad(fetch, stage: stage)
        }
    }
}
```

`onCancelled` cancels the Task, so the closure is cancelled the same way as in the data-closure path. Add tests next to the existing `data:` ones: `skipDataLoadingQueuePerRequestWithImageClosure` (suspended queue, image still loads) and a cancellation test in the style of `imageRequestWithAsyncAwaitSkippingDataLoadingQueueIsCancellable` using `image:`. Add a short CHANGELOG line.


### D51. ImageResponse.request of a freshly processed image lacks its processors

_Severity: low · user impact: low · public API: yes · found by: image-decode-process-tasks, nukeui-views, request-model_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:86`

**Repro:** [NukeTests/image-decode-process-tasks--response-request-loses-processors.swift](NukeTests/image-decode-process-tasks--response-request-loses-processors.swift), [NukeUITests/nukeui-views--response-request-drops-processors.swift](NukeUITests/nukeui-views--response-request-drops-processors.swift), [NukeTests/request-model--response-request-drops-processors.swift](NukeTests/request-model--response-request-drops-processors.swift)

**What:** process() starts from the dependency's response, which was created for request.withProcessors(dropLast), and replaces only the container. The final response therefore carries the innermost request, which has no processors. A memory-cache hit for the same request returns the full request, so the result is inconsistent.

**Expected:** Doc: "The request for which the response was created." response.request.processors.count should be 1 for a request with one processor.

**Actual:** It is 0 when the image was loaded and 1 when it came from the memory cache.

**Reproduction check:** `loaded.request.processors.count == 1` failed on all 3 iterations with `loaded.request.processors.count → 0`. The memory-cache hit for the same request passed with `cached.request.processors.count == 1` and `cacheType == .memory`.

**Refutation attempt (failed):**

The bug is real. I reproduced it in a scratch copy of the repo (/private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/refute-respreq/src, macOS, xcodebuild). The repo itself was not modified.

What the probe tests showed without a fix:
- A fresh load of ImageRequest(url:, processors: [p1]) returns a response whose request.processors.count is 0.
- With [p1, p2], response.request.processors is [].
- A memory-cache hit returns 1, and a hit on processed data in the disk cache also returns 1. This is because TaskLoadImage.start and decodeCachedData build the response with the task's full request.
- It has a real effect through the public API: after a fresh load, `pipeline.cache.removeCachedImage(for: response.request)` leaves the processed image in the memory cache. It removes the key for the unprocessed image instead.

Why it happens: fetchImage() subscribes to makeTaskLoadImage(for: request.withProcessors(dropLast)). The innermost TaskLoadImage has no processors, so it fetches the original image and decodes it with that stripped request. process() then does `var response = response; response.container = ...`, which keeps the dependency's request. The stripped request was built inside the pipeline. No caller ever created it.

Is it intentional or documented? No. ImageResponse.request is documented as "The request for which the response was created", and nothing in CHANGELOG ("Add ImageRequest to ImageResponse", Nuke 11), the docc, or the commit history says it is the base request. The commit that added the field (0d0f9aa2) built the response with the full `request` on the intermediate memory-cache path. The fetch path kept the inner request only because `response.map` (later inlined in 3b44c1c7) preserved it. That looks like an oversight, not a design choice.

The repro is not an API misuse or a test artifact. It uses only the public imageTask(with:).response, and MockDataLoader/MockImageProcessor do not affect which request ends up on the response.

A separate caveat: because of deduplication, response.request is the request of whichever task created the shared worker. I confirmed that two coalesced tasks with different userInfo or priority both get the first task's values, so "response.request equals my request" is never strictly guaranteed. That issue is broader and has a different cause. The processors case is worse: the request carries neither the caller's processors nor its cache key, and the cache paths for the same request disagree with it.

Impact is low. Most consumers read response.request.url or use their own request or ImageTask.request, and nothing in Nuke or NukeUI reads response.request. It matters for anyone who logs it, keys a custom cache on it, or passes it back to pipeline.cache APIs.

I verified the fix below in the scratch copy. With it, response.request is correct on the fresh, two-processor, disk and memory paths, and removeCachedImage(for: response.request) works. The whole NukeTests target (1109 tests) passes except my deliberately failing coalescing probe, which is the separate issue above.

**Suggested fix:**

In Sources/Nuke/Tasks/TaskLoadImage.swift, didFinishProcessing(result:isCompleted:), put the task's own request back on the processed response before passing it on:

    case .success(var response):
        response.request = request
        didReceiveImageResponse(response, isCompleted: isCompleted)

(Setting it inside the Result closure at line 86 also works, if `request` is captured first.) ImageProcessingContext can keep receiving the dependency's response unchanged. A broader option also fixes the deduplication case: in ImageTask, set `response.request = self.request` before delivering each .value event. It costs one retain per event on the hot path, so measure it before choosing it. Add a regression test asserting response.request.processors for a freshly processed image, a memory hit and a disk hit.

- Also reported by **nukeui-views** (confirmed): ImageResponse.request of a processed image loaded from the network has no processors
- Also reported by **request-model** (confirmed): ImageResponse.request of a processed network image has no processors

### D52. isDecompressionEnabled = true has no effect on macOS

_Severity: low · user impact: low · public API: yes · found by: image-decode-process-tasks_

**Where:** `Sources/Nuke/Decoding/ImageDecoding.swift:105`

**Repro:** [NukeTests/image-decode-process-tasks--macos-decompression-option-has-no-effect.swift](NukeTests/image-decode-process-tasks--macos-decompression-option-has-no-effect.swift)

**What:** TaskLoadImage decompresses only images marked as needing it. The only place that marks them, makeImageResponse, is inside `#if !os(macOS)`. On macOS, turning the option on never calls the delegate's shouldDecompress or decompress, even though ImageDecompression.decompress works on macOS. The repro is wrapped in `#if os(macOS)`.

**Expected:** Doc: "By default, enabled on all platforms except for macOS" reads as an opt-in on macOS, so the loaded image should be decompressed.

**Actual:** shouldDecompress is called 0 times and decompress is called 0 times.

**Reproduction check:** Both expectations failed on all 3 iterations: `delegate.shouldDecompressCount == 1 → false` and `delegate.decompressCount → 0`.

**Refutation attempt (failed):**

I reproduced this using only the public API, and the history points to an oversight rather than a design choice.

Reproduction. I copied the sources into the scratchpad and built a small macOS executable against the `Nuke` product. It uses a custom `ImagePipeline.Delegate` whose `shouldDecompress` and `decompress` count their calls, and it loads Tests/Resources/fixture.jpeg from a file URL with `isDecompressionEnabled` set to false and then to true. Both runs printed `shouldDecompress=0 decompress=0`. No mocks, `@testable` code or test-harness timing are involved, so a real macOS app gets the same result. A delegate whose `shouldDecompress` always returns true is never asked either.

Cause. `TaskLoadImage.isDecompressionNeeded` (Sources/Nuke/Tasks/TaskLoadImage.swift:153) only checks the delegate when `ImageDecompression.isDecompressionNeeded(for:)` is true. The only code that sets that flag is `makeImageResponse` (Sources/Nuke/Decoding/ImageDecoding.swift:104-108), and it is wrapped in `#if !os(macOS)`. On macOS the flag is never set, so the delegate is never asked.

Is it intentional? Probably not.
- Commit 578ed278 (2019) added this `#if !os(macOS)` marker. At that time decompression was iOS-only and `isDecompressionEnabled` did not exist on macOS.
- Commit fea2626b (Nuke 11, Jun 2022, "Add callbacks to customize image decompression to ImagePipelineDelegate") deliberately changed that:
  - it made `isDecompressionEnabled` (default false) and `imageDecompressingQueue` available on macOS;
  - it deleted the macOS-only `decompressImage` shortcut in `TaskLoadImage` whose comment said "There is no decompression on macOS";
  - it made the delegate hooks available on every platform.
- Commit cb8d0bb0 then changed the doc comment to "By default, enabled on all platforms except for `macOS`". That reads as off by default but available to turn on, not as unsupported.
- The marker in the decoder was left behind, so the option does nothing on macOS.
- Nothing documents this: no CHANGELOG entry, doc article or GitHub issue says decompression is unsupported on macOS.
- `ImageDecompression.decompress` does work on macOS: `DecompressionTests` runs the wide-gamut case there, and `PlatformImage.make(cgImage:)` builds an `NSImage`.

Counter-evidence I weighed. The pipeline decompression tests in ImagePipelineTests.swift are all inside `#if !os(macOS)`, and exposing the option might have been meant only for source compatibility across platforms. But that would not explain removing the macOS no-op path and adding public decompression hooks on every platform. The docs also describe the option as something you can switch on, which a reasonable user would take at face value.

Impact. Low. The default behavior on macOS (no decompression) is unchanged. Only apps that opt in are affected: they silently get no background decompression, so images are decoded lazily on the main thread when first drawn. That is a performance issue, not a correctness one, and nothing crashes or returns a wrong image.

**Suggested fix:**

Remove the `#if !os(macOS)` / `#endif` around the marking in `makeImageResponse` (Sources/Nuke/Decoding/ImageDecoding.swift:104-108), so it reads:

    if context.request.thumbnail == nil && !container.isPreview {
        ImageDecompression.setDecompressionNeeded(true, for: container.image)
    }

The default on macOS stays the same: `_isDecompressionEnabled` is false there, and the default `shouldDecompress` returns `pipeline.configuration.isDecompressionEnabled`. The only new cost is one associated object per decoded image and one delegate call.

Then turn on the "Decompression" tests in Tests/NukeTests/ImagePipelineTests/ImagePipelineTests.swift for macOS. They are currently inside `#if !os(macOS)`. On macOS they need a pipeline with `isDecompressionEnabled = true`. Add a macOS test showing that the delegate's `shouldDecompress` and `decompress` are called once when the option is on, and zero times by default.

The alternative is to keep the current behavior and change the doc comment to say the option has no effect on macOS. That fits worse with the Nuke 11 change that made the option and the decompression hooks available on every platform.


### D53. An unusable thumbnail entry in the disk cache skips the original-data fallback

_Severity: low · user impact: low · public API: yes · found by: image-decode-process-tasks_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:21`

**Repro:** [NukeTests/image-decode-process-tasks--review-unusable-thumbnail-entry-skips-original-data.swift](NukeTests/image-decode-process-tasks--review-unusable-thumbnail-entry-skips-original-data.swift)

**What:** For a thumbnail request with no processors, start() chooses between its branches up front. If the thumbnail key has data, decodeCachedData runs. When that data fails to decode, or the decoder factory declines it, didFinishDecoding(with: nil) at line 45 calls fetchImage() directly. That skips the `lookUpCachedData(for: request.withoutThumbnail())` branch, even though the original data is on disk. The image is downloaded again, and with .returnCacheDataDontLoad the request fails. An unusable entry is supposed to be treated as a cache miss, and a miss for a thumbnail falls back to the original data.

**Expected:** The thumbnail is generated from the original data on disk. No download starts (createdTaskCount == 0), and a request with .returnCacheDataDontLoad succeeds.

**Actual:** The data loader is called (createdTaskCount == 1). With .returnCacheDataDontLoad the request throws .dataMissingInCache.

**Reproduction check:** thumbnailIsMadeFromOriginalDataWhenItsOwnEntryIsCorrupted failed on all 3 iterations with `dataLoader.createdTaskCount → 1` (the 400x300 size check passed, because the thumbnail was built from the downloaded data). thumbnailIsMadeFromOriginalDataWhenLoadingIsNotAllowed failed on all 3 iterations with `Caught error: Failed to load data from cache and download is disabled.` (.dataMissingInCache).

**Refutation attempt (failed):**

I couldn't refute this. I ran the repro in a copy of HEAD (scratchpad/verify-thumb, xcodebuild on macOS) and it fails exactly as described. createdTaskCount is 1 instead of 0, and with .returnCacheDataDontLoad the request throws "Failed to load data from cache and download is disabled".

Cause, in Sources/Nuke/Tasks/TaskLoadImage.swift:
- start() (lines 21-28) looks for the original data only when the thumbnail key is a miss.
- When the thumbnail entry exists but can't be used, decodeCachedData gets no decoder (line 34) or the decode fails, and didFinishDecoding(with: nil) calls fetchImage() (line 45).
- For a thumbnail request with no processors, fetchImage() goes straight to TaskFetchOriginalImage and then TaskFetchOriginalData. Neither of those reads the disk cache (only TaskLoadImage and TaskLoadData call lookUpCachedData), so the original data on disk is never used.

The processor path behaves differently, which suggests the thumbnail path is an oversight. I added a comparison test: a processor request whose processed entry is corrupted, with the original data on disk. It passes with createdTaskCount == 0. That works because fetchImage() creates a TaskLoadImage for the request minus its last processor, and that task does its own cache lookups. The thumbnail fallback added in 67fbf4ed (fix for #837, CHANGELOG: "Fix thumbnail requests re-downloading original image data when it is already stored in the disk cache") went only into start(), so it covers a miss but not an entry that fails to decode. The comment the repro quotes ("load as if there was no data in the cache") is not in the current source. That is a small error in the repro and doesn't change the finding. An unusable entry leading to a load has been the behavior since 97eeefc6.

Why the impact is low:
1. Default config can't reach it. With dataCachePolicy .storeOriginalData, a thumbnail request stores only the original key. I checked: the only key stored was "http://test.com/example.jpeg". The thumbnail key gets an entry only with .automatic or .storeAll, where both entries are stored (verified), or with manual storeCachedData or a custom cache.
2. The built-in DataCache writes to a temp file and renames it (DataCache.swift:500), so a crash mid-write can't leave a partial entry. A bad entry needs storage-level corruption, a custom DataCaching, or an encoder/decoder mismatch. Example: an app that used a plugin encoder and later dropped the matching decoder, or an imageDecoder(for:) delegate that declines the entry.
3. It fixes itself. After the extra download, TaskLoadImage re-encodes the thumbnail and overwrites the bad entry. In my .automatic test the bad entry was replaced by 11691 bytes of valid data. So the cost is one extra download per bad entry. The worse case is offline use with .returnCacheDataDontLoad, which fails with .dataMissingInCache even though the original data is on disk, until a normal load succeeds.

The repro uses only the public API: ImagePipeline configuration, ImageRequest.thumbnail and imageTask(with:).response. Seeding MockDataCache.store directly is just a way to set up the bad-entry state.

**Suggested fix:**

In TaskLoadImage, try the original data once when the thumbnail entry can't be used, before downloading. The smallest change is a flag set in start():

```swift
private var canFallBackToOriginalData = false

override func start() {
    ...memory lookup unchanged...
    canFallBackToOriginalData = request.thumbnail != nil && request.processors.isEmpty
    if let data = lookUpCachedData(for: request) {
        decodeCachedData(data)
    } else {
        loadOriginalDataOrFetch()
    }
}

private func loadOriginalDataOrFetch() {
    if canFallBackToOriginalData {
        canFallBackToOriginalData = false
        if let data = lookUpCachedData(for: request.withoutThumbnail()) {
            return decodeCachedData(data) // decodes with the thumbnail options
        }
    }
    fetchImage()
}

private func didFinishDecoding(with response: ImageResponse?) {
    if let response {
        didReceiveImageResponse(response, isCompleted: true)
    } else {
        loadOriginalDataOrFetch()
    }
}
```

Resetting the flag keeps it to one attempt, so undecodable original data still goes on to fetchImage(). It also avoids decoding the same data twice when a custom cacheKey(for:) returns one key for both requests. Add regression tests for both cases: a corrupted thumbnail entry with the original data on disk should give createdTaskCount == 0, and the same setup with .returnCacheDataDontLoad should succeed.


### D54. Setting FetchImage.priority back to nil doesn't restore the running task's priority

_Severity: low · user impact: low · public API: yes · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/FetchImage.swift:65`

**Repro:** [NukeUITests/nukeui-swiftui--fetchimage-priority-nil-not-restored.swift](NukeUITests/nukeui-swiftui--fetchimage-priority-nil-not-restored.swift)

**What:** The priority doc says: 'Overrides the priority of the current and future requests. When nil (the default), the request's own priority is used. Can be updated while a task is already running.' But didSet only forwards non-nil values to imageTask. Setting nil leaves the running task at the override. The FetchImage docs recommend lowering the priority in onDisappear and undoing it in onAppear. LazyImage only avoids this bug because it restarts the request right after setting priority = nil.

**Expected:** After load(ImageRequest(url:, priority: .high)), then priority = .veryLow, then priority = nil, the running task's priority is .high.

**Actual:** The task stays at .veryLow.

**Reproduction check:** Failed on all 3 iterations: 'settingPriorityBackToNilRestoresTheRequestPriority() ... Expectation failed: imageTask.priority == .high' (line 51). The earlier checks (priority .high after load, .veryLow after the override) passed.

**Refutation attempt (failed):**

The code does what the report says. `FetchImage.priority`'s didSet (Sources/NukeUI/FetchImage.swift:65-71) only forwards non-nil values: `if let priority { imageTask?.priority = priority }`. So `priority = nil` does nothing to a running task. The public API reaches it directly with no misuse: load a request with `.high`, set `priority = .veryLow`, then set `priority = nil`, and `ImageTask.priority` stays `.veryLow`. The ImageTask has already been started with the overridden priority, and nothing resets it. It's not a mock or timing artifact. The data loader is only suspended so the task is still running, and priority is read synchronously from the task's lock-protected status.

What argues against it:
- The behavior is old. It has been `priority.map { imageTask?.priority = $0 }` since 2021 (0250d2b2), and da099659 only rewrote the syntax. LazyImageView.priority has the same pattern (LazyImageView.swift:130-136), so "nil means don't override" may have been deliberate.
- The docs example in Documentation/NukeUI.docc/Extensions/FetchImage-Extensions.md restores the priority with `image.priority = .normal` plus `image.load(url)` in onAppear, not with nil. That pattern works, so the report overstates what the docs recommend.
- LazyImage.onAppear sets `viewModel.priority = nil` and then calls `viewModel.load(...)`, which cancels and restarts at the request's own priority (commit b40a4a7d). The main SwiftUI consumer is therefore not affected.

What argues for it: commit cc581e83 (March 2026) rewrote the property docs to say "Overrides the priority of the current and future requests. When `nil` (the default), the request's own priority is used. Can be updated while a task is already running." Read plainly, clearing the override should put the current request back on its own priority. A user who clears it without reloading, for example because the load runs from init or onChange rather than onAppear, keeps the running task at the lowered priority. The maintainer already treated a stuck lowered priority as a bug worth a CHANGELOG entry ("Fix LazyImage with the lowerPriority disappear behavior permanently lowering the priority...").

Impact is low. Priority only changes scheduling order, so the image still loads, only later, and only when someone clears the override mid-load without restarting. It's a real mismatch between the docs and the code on a public API, not a correctness failure.

**Suggested fix:**

In FetchImage, remember the caller's own priority before applying the override and restore it on nil:

    private var requestPriority: ImageRequest.Priority = .normal

    public var priority: ImageRequest.Priority? {
        didSet { imageTask?.priority = priority ?? requestPriority }
    }

    // in load(_ request:), after the nil guard and before the override:
    requestPriority = request.priority
    if let priority { request.priority = priority }

`imageTask.request.priority` can't be used for this, because load() has already rewritten `request.priority` with the override when one was set. Make the same change to LazyImageView.priority (LazyImageView.swift:130 and its load at ~293) so both behave the same way. Another option is to keep the current behavior and change the doc comment to say that setting nil affects only future loads. Either way, add a test: load with `.high`, set `.veryLow`, set nil, expect `.high`.


### D55. LazyImage.processors(_:) doc says the request's processors take priority, but the modifier overwrites them

_Severity: low · user impact: low · public API: yes · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/LazyImage.swift:105`

**Repro:** [NukeUITests/nukeui-swiftui--lazyimage-processors-doc-mismatch.swift](NukeUITests/nukeui-swiftui--lazyimage-processors-doc-mismatch.swift)

**What:** The doc comment reads 'Processors are only applied if the request does not already define its own processors. The request's processors always take priority.' It was reworded in cc581e83 'Update documentation'; it previously said 'your processors will be applied instead'. The implementation still overwrites unconditionally (`request.processors = processors ?? []`), and the existing LazyImageTests.nilProcessorsClearRequestProcessors test pins the overwrite. So either the doc or the implementation is wrong. FetchImage.processors, for comparison, really does defer to the request.

**Expected:** Per the doc: LazyImage(request: request with processor 'request').processors([processor 'modifier']) produces an image processed by ['request'].

**Actual:** The image is processed by ['modifier'].

**Reproduction check:** Failed on all 3 iterations: 'Expectation failed: try #require(response.value).image.nk_test_processorIDs == ["request"]' (line 52). The #require passed, so the image loaded, but it was processed by the modifier's processor, not the request's.

**Refutation attempt (failed):**

This is a real mismatch between the doc and the code, and the doc is the part that is wrong. The implementation is fine.

Evidence:
- The modifier at /Users/kean/Developer/Nuke/Sources/NukeUI/LazyImage.swift:105-107 always overwrites: `map { $0.context?.request.processors = processors ?? [] }`. It writes straight into `context.request`, which `body` passes to `viewModel.load(context?.request)` at lines 163 and 189. `FetchImage.processors` is never set on this path, so FetchImage's "defer to the request" logic (FetchImage.swift:126) never applies. The repro's result, `['modifier']` instead of `['request']`, follows directly from that line.
- The code on that line has not changed in substance since 2022. `git log -L` shows only 154f8fdc (move), cb9ce7b2 (adopt `any`), fb7d12de and a79025bc (`consuming`).
- The doc text before cc581e83 ("Update documentation", 2026-03-13) was "If you pass an image request with a non-empty list of processors as a source, your processors will be applied instead." That matches the overwrite. cc581e83 changed only the comment, not the code, to "Processors are only applied if the request does not already define its own processors. The request's processors always take priority." That is false for LazyImage. It looks like the wording was copied from FetchImage and ImageLoadingOptions, which do defer to the request.
- Tests pin the overwrite: LazyImageTests.nilProcessorsClearRequestProcessors, added in 181d6d7f "Increase test coverage". The internal preview also relies on `.processors(isBlured ? [GaussianBlur()] : [])` replacing the processors.
- Nothing promises the new behavior anywhere else. CHANGELOG and NukeUI.docc (LazyImage-Extensions.md) never say the request's processors take priority.

On the repro: `@testable` is used only for test helpers (MockImageProcessor, nk_test_processorIDs). The behavior itself goes through public API only: `LazyImage(request:)` and `.processors(_:)`. It does not misuse the API, it is not a test artifact, and it is not platform behavior.

A related mismatch: LazyImageView.processors (/Users/kean/Developer/Nuke/Sources/NukeUI/LazyImageView.swift:122-126) still has the old "your processors will be applied instead" text. Its code does the reverse and applies them only when `request.processors.isEmpty` (line 290). So each of the two components has the other's doc.

Impact is low. The behavior has been stable for four years and tests cover it. A user who trusts the current doc and passes both, for example a request with `.resize` plus a `.processors([blur])` modifier, will silently lose the request's processors. With resize gone, the image decodes at full size. The cost is surprise, not a crash.

**Suggested fix:**

Fix the docs only; don't change behavior. Changing the code would break existing callers and LazyImageTests.nilProcessorsClearRequestProcessors.

In Sources/NukeUI/LazyImage.swift:101-104, replace the comment with:

    /// Sets processors to be applied to the image.
    ///
    /// Replaces the processors of the request passed to the initializer, if any.
    /// Passing `nil` or an empty array removes them.

Also fix the opposite mismatch in Sources/NukeUI/LazyImageView.swift:122-125. That comment should say the processors are applied only when the request has none of its own, which is what line 290 does. Optionally, add a test that pins non-nil overwrite, e.g. a request with ['request'] plus `.processors(['modifier'])` produces ['modifier'].


### D56. LazyImageView leaves the previous image visible in imageView when a memory-cache hit or deferred reset is displayed through makeImageView

_Severity: low · user impact: medium · public API: yes · found by: nukeui-views_

**Where:** `Sources/NukeUI/LazyImageView.swift:300`

**Repro:** [NukeUITests/nukeui-views--lazyimageview-stale-image-under-custom-view.swift](NukeUITests/nukeui-views--lazyimageview-stale-image-under-custom-view.swift)

**What:** A memory-cache hit uses resetOrDefer(clearImage: false) so that it can overwrite imageView.image directly. The deferred reset (isResetEnabled = false) also uses clearImage: false (line 369). When makeImageView returns a view, display() adds that view on top and never hides or clears the built-in imageView. The typical setup is makeImageView returning a view only for some content types. In that setup, a reused cell shows the previous image through any transparent part of the custom view and keeps it in memory. A normal network response hides imageView in this case, and the existing test fadeInTransitionSkippedWhenImageViewIsUnused relies on that.

**Expected:** After a response is displayed by a custom view, imageView is hidden and holds no image.

**Actual:** imageView.isHidden is false and imageView.image is still the previous image, in both the memory-cache-hit case and the isResetEnabled = false case.

**Reproduction check:** macOS, 3/3 iterations: both tests fail `view.imageView.isHidden` and `view.imageView.image == nil`. The custom view is added, but the built-in imageView stays visible and still holds the previous image. This happens for the memory-cache hit and for isResetEnabled = false. The one-shot iOS run fails the same way.

**Refutation attempt (failed):**

The bug is real, and it is a regression in released code. I ran the repro on macOS in a scratch export of HEAD 2c2b23f6. One outside change was needed to build: the working tree's test-only `SwiftUI.Color` edit to `LazyImageTests.swift`, because HEAD's test target doesn't compile on the macOS 27 SDK.

Test results:
- Both repro tests fail as the report says: `imageView.isHidden` is false and `imageView.image` still holds the previous image.
- Control test 1: loading the second image over the network with a custom view passes. `reset(clearImage: true)` hides and clears `imageView`, which is also what `fadeInTransitionSkippedWhenImageViewIsUnused` relies on.
- Control test 2: calling the public `reset()` before a memory-cache hit also passes.

So the fault is only in the two paths that skip clearing the image. The repro uses public API only: `makeImageView`, `request`, `isResetEnabled` and `pipeline.cache`. `@testable` is used only for the test mocks. It is called on the main actor as required.

History:
- Before 4bc51489 ("Optimize cache hits in LazyImageView") and 00666688 ("Skip clear image on load"), both from May 2026, `load()` always called `reset()`, and the deferred `resetIfNeeded()` in `display()` did a full reset that set `imageView.image = nil` and `isHidden = true`.
- The optimization assumed that `display()` always overwrites `imageView.image`. That is false when `makeImageView` returns a view: `display()` then never touches `imageView`.
- Both commits are in tags 13.0.5, 13.0.6, 13.1.0 and 13.2.0. No CHANGELOG entry or doc says `imageView` should stay visible under a custom view.

The documented use case is exposed. The Nuke 12 migration guide shows `makeImageView` returning a `VideoPlayerView` only for video and nil otherwise. So when a reused cell gets a video from the memory cache after showing a still image, the old image stays under the player. An `AVPlayerLayer` is transparent until its first frame and in letterbox areas, so the stale image shows there. The old image, or animated image, also stays in memory.

There is also a cost the report misses, found by reading the code, not by a test. `AnimatedImageView.isVisible` checks only window, `isHidden` and alpha, and its own comment says nothing tells the view it is covered. So an animated GIF left under the custom view keeps playing and decoding frames.

With `isResetEnabled = false`, the previous image staying up while the load runs is documented behavior. It should still be removed once the new content is shown, as it is when the new content goes to `imageView`.

Impact: users of `makeImageView` who mix custom views with the built-in image view. They see a visible stale image and pay for retained memory and CPU. Users who never set `makeImageView` are not affected.

I tried the fix below in the scratch copy. It makes both repro tests pass, and all 62 tests in `LazyImageViewTests` plus the repro suite pass.

**Suggested fix:**

In `Sources/NukeUI/LazyImageView.swift`, in `display(_:isFromMemory:)`, clear and hide the built-in image view when a custom view takes over. This covers both the memory-cache-hit `resetOrDefer(clearImage: false)` path and the deferred `resetIfNeeded(clearImage: false)` path, and leaves the fast path for plain image hits unchanged:

```swift
if let view = makeImageView?(container) {
    // A memory cache hit or a deferred reset skips clearing the
    // built-in image view, so clear it here when it goes unused.
    if imageView.image != nil { imageView.prepareForReuse() }
    if !imageView.isHidden { imageView.isHidden = true }
    addSubview(view)
    view.pinToSuperview()
    customImageView = view
} else { ... }
```

Add regression tests next to `makeImageViewUsedForCustomView` in `Tests/NukeUITests/LazyImageViewTests.swift`: a memory-cache hit, and `isResetEnabled = false`, each shown through a custom view after an image in `imageView`. Both should assert that `imageView` is hidden and holds no image. The two repro tests can be moved over as they are.


### D57. LazyImageView delivers onCompletion for a replaced request after the completion of the request that replaced it

_Severity: low · user impact: low · public API: yes · found by: nukeui-views_

**Where:** `Sources/NukeUI/LazyImageView.swift:361`

**Repro:** [NukeUITests/nukeui-views--lazyimageview-superseded-oncompletion-last.swift](NukeUITests/nukeui-views--lazyimageview-superseded-oncompletion-last.swift)

**What:** handle(result:isSync:) calls onSuccess or onFailure and then onCompletion. A common pattern is to set a fallback URL from onFailure. If the fallback is a memory-cache hit, it completes synchronously inside onFailure, running onSuccess and onCompletion for the fallback. Only after that does the outer handle call onCompletion with the original failure. An app that mirrors onCompletion into its own state (an error badge, analytics) ends up recording a failure while the view shows the fallback.

**Expected:** The onCompletion calls arrive in the order the requests completed: [failure, success].

**Actual:** They arrive as [success, failure].

**Reproduction check:** macOS, 3/3 iterations: `completions == ["failure", "success"]` fails with the actual value `["success", "failure"]`. The fallback image is displayed. The one-shot iOS run fails the same way.

**Refutation attempt (failed):**

I couldn't refute this. It is real, reachable through the public API, and has been in the code since NukeUI was merged in 2022. The impact is low.

Code path in /Users/kean/Developer/Nuke/Sources/NukeUI/LazyImageView.swift:
- `handle(result:isSync:)` (lines 342-366) sets `imageTask = nil`, calls `onSuccess` or `onFailure`, then calls `onCompletion?(result)`. Nothing checks whether the callback started a new load.
- If `onFailure` sets `view.url` or `view.request`, `load(_:)` runs synchronously inside it. A memory-cache hit, or a nil request, then goes back into `handle(result:isSync:true)` and delivers `onSuccess` and `onCompletion` for the new request.
- Control then returns to the outer `handle`, which delivers `onCompletion` for the original failure last.
- `git blame` shows these lines are from 154f8fdc (2022). The only recent change was the type change in 30ce4d89. No commit message, CHANGELOG entry or docc page mentions the ordering or warns against reloading from inside a callback. The docs only say "Gets called when the request is completed."

I ran the repro against a `git archive HEAD` copy in the scratchpad (macOS, NukeUITests scheme). It fails as described: "Expectation failed: completions == ["failure", "success"]", with the actual order `["success", "failure"]` and the fallback image on screen. To build it I had to delete `Tests/NukeUITests/LazyImageTests.swift` in the copy, because at HEAD it doesn't compile on macOS ("ambiguous use of 'Color'", lines 115/136/155). That is a separate issue, not this bug.

Why it isn't a misuse or a test artifact:
- The test uses only public API on the main actor: `url`, `request`, `onFailure`, `onCompletion`, and `pipeline.cache`. The mocks only stand in for a network failure and a cached fallback image.
- Setting a fallback URL from `onFailure` is the natural pattern. `LazyImageView` has no built-in fallback-URL option; `failureImage` and `failureView` are static.
- The callback API makes a promise elsewhere that this path breaks. `_loadImage` in `Sources/Nuke/Pipeline/Deprecated.swift` says "after cancellation no events are called on the callback queue". So in every async path a replaced request never gets callbacks after its replacement. `FetchImage` has tests for the same kind of guarantee (`asyncLoadDeliversNoResultAfterCancel`/`Reset`). The synchronous re-entry from inside a callback is the one path that skips it.
- The fallback doesn't have to be cached. If it loads over the network, the new request's `onStart` still fires before the old request's `onCompletion`. An app that turns a loading flag on in `onStart` and off in `onCompletion` then shows "not loading" while the fallback downloads.

Why the impact is low:
- Nothing wrong ends up in the view. The outer `handle` only calls the callback, so the image, failure view and `imageTask` are all correct.
- The ordering is not documented as a promise.
- It needs a reload from inside `onSuccess` or `onFailure` plus app state driven by `onCompletion` (or `onStart`/`onCompletion`).
- There is an easy workaround: set the fallback from `onCompletion`, or defer it with `DispatchQueue.main.async`.
- `LazyImage` and `FetchImage` only offer `onCompletion`, so they are not affected in the same way.

**Suggested fix:**

Minimal fix in `Sources/NukeUI/LazyImageView.swift`: if `onSuccess` or `onFailure` started a new load, skip `onCompletion` for the old result. This matches the pipeline's rule that a replaced request gets no more events.

```swift
private var loadGeneration = 0

private func load(_ request: ImageRequest?) {
    loadGeneration &+= 1
    ...
}

private func handle(result: Result<ImageResponse, ImagePipeline.Error>, isSync: Bool) {
    ...
    imageTask = nil
    let generation = loadGeneration
    switch result {
    case .success(let response): onSuccess?(response)
    case .failure(let error): onFailure?(error)
    }
    // onSuccess/onFailure started a new load; its callbacks were already
    // delivered or are coming. Don't report the replaced result after them.
    guard generation == loadGeneration else { return }
    onCompletion?(result)
}
```

Alternative that keeps every callback: while `handle` is delivering callbacks, have `load(_:)` store the new request as pending, then run it after `onCompletion` returns. The order is then [failure, success]. The cost is that `view.imageTask` is still nil right after setting `url` inside `onFailure`.

Either way, add a regression test covering both the cached and the not-cached fallback set from `onFailure`. The not-cached case should check that the new request's `onStart` does not come before the old request's `onCompletion`. Also add a sentence to the `onSuccess`/`onFailure` doc comments saying what happens when a new request is set from inside them.


### D58. LazyImageView shows a memory-cached progressive scan even when isProgressiveImageRenderingEnabled is false

_Severity: low · user impact: low · public API: yes · found by: nukeui-views_

**Where:** `Sources/NukeUI/LazyImageView.swift:308`

**Repro:** [NukeUITests/nukeui-views--lazyimageview-cached-scan-ignores-progressive-rendering-flag.swift](NukeUITests/nukeui-views--lazyimageview-cached-scan-ignores-progressive-rendering-flag.swift)

**What:** load(_:) calls display(image, isFromMemory: true) for a cached preview without checking isProgressiveImageRenderingEnabled. Scans produced during a load go through handle(preview:), which does check the flag and ignores them. The documentation says "If disabled, progressive image scans will be ignored." isStoringPreviewsInMemoryCache is on by default, so an app that turned progressive rendering off still shows a blurry partial scan whenever the same URL was partially loaded earlier, for example by a cancelled cell.

**Expected:** With the flag off, the placeholder stays and imageView stays hidden until the final image arrives.

**Actual:** The cached scan is displayed (imageView is visible with the scan's image) for the whole load.

**Reproduction check:** macOS, 3/3 iterations (6 issues): `view.imageView.isHidden` is false and `view.imageView.image` is the cached 640x480 scan. imageTask is not nil and the placeholder is un-hidden, but it sits below the visible imageView. The one-shot iOS run fails the same way.

**Refutation attempt (failed):**

I could not refute this. The bug is real and the repro fails as described. I ran it in a scratch clone at HEAD 2c2b23f6 with `xcodebuild test -scheme NukeUITests` on macOS. The repo itself was not touched. I had to copy over the uncommitted `SwiftUI.Color` fix in LazyImageTests.swift, because HEAD does not compile on macOS without it. After `view.request = Test.request`, `imageView.isHidden` is false and `imageView.image` is non-nil.

**Why the claim holds**
1. **Same scan, two paths, only one checks the flag.** TaskLoadImage.start() looks up the memory cache. On a preview hit it calls `send(value: response, isCompleted: false)`, so the pipeline delivers the same cached scan again through the progress handler. My extra test confirmed `onPreview` fires with `cacheType == .memory`. That path goes through `handle(preview:)`, which returns early when `isProgressiveImageRenderingEnabled` is false. The early display at LazyImageView.swift:308 is only a faster version of that same delivery, and it skips the check. The two paths disagree about the same image.
2. **The documentation promises otherwise.** The doc comment says "If disabled, progressive image scans will be ignored." A cached preview is a progressive scan: `isPreview == true`, carrying `scanNumberKey`. The existing test `progressivePreviewsIgnoredWhenRenderingDisabled` asserts nothing is shown during a load when the flag is off; it just never covered the cached-scan case.
3. **Nothing says it is intentional.** The code dates from the original NukeUI import (154f8fdc, 2022, comment "Display progressive preview"). 4bc51489 ("Optimize cache hits in LazyImageView") only restructured it. No commit message or CHANGELOG entry says cached scans should bypass the flag.
4. **The other UIKit API behaves differently.** The ImageViewExtensions `loadImage` path does not end up showing a cached scan when `ImageLoadingOptions.isProgressiveRenderingEnabled` is false. My test saw `image == nil` right after the call. Its early `display` is immediately wiped by `nuke_display(nil)` from `isPrepareForReuseEnabled`, or covered by the placeholder, and the scan the pipeline re-delivers is blocked by the flag. So LazyImageView is the odd one out.
5. **The repro uses the API correctly.** The only shortcut is seeding the scan with the public `pipeline.cache[request] =` setter. In a real app it gets there through TaskLoadImage.storeImageInCaches, which stores every scan as it is produced. A cancelled load leaves the scan in the memory cache.

**Why impact is low**
- Scans are only produced when `ImagePipeline.Configuration.isProgressiveDecodingEnabled` is true, and it is false by default (see the guard in TaskFetchOriginalImage).
- A user also has to turn the view flag off, and an earlier load of the same request has to have been cut short, for example by a cancelled cell. Otherwise the final image replaces the scan in the cache.
- The effect is cosmetic: a blurry scan is shown, sitting over the placeholder, until the final image replaces it.
- It matters most for apps that turn off built-in rendering to draw scans themselves via `onPreview` (for example, a progressive blur). They get the raw scan in `imageView` as well as their own rendering.
- It is reachable through public API: `LazyImageView.isProgressiveImageRenderingEnabled` plus the pipeline configuration.

**Side note (separate issue)**
The early cached-preview `display` in ImageViewExtensions.swift (around line 311) never takes effect. It is immediately overwritten by the placeholder or by `nuke_display(nil)`.

**Suggested fix:**

In Sources/NukeUI/LazyImageView.swift load(_:), apply the same check that handle(preview:) uses to the early display:

    if let image = cachedImage, image.isPreview, isProgressiveImageRenderingEnabled {
        display(image, isFromMemory: true)
    }

With the flag off, the placeholder stays visible and imageView stays hidden. The pipeline still re-delivers the cached scan, so `onPreview` still receives it (cacheType .memory) and the final image displays as usual. Add a regression test next to `progressivePreviewsIgnoredWhenRenderingDisabled` in Tests/NukeUITests/LazyImageViewTests.swift. It should seed a preview with `pipeline.cache[Test.request] = ImageContainer(image:, isPreview: true)`, suspend the data loader, set the flag to false, and assert that imageView is hidden and the placeholder is visible.


### D59. The fade-in cross-dissolve between content modes in loadImage(into:) resets the image view's alpha to 1 on iOS

_Severity: low · user impact: low · public API: yes · found by: nukeui-views_

**Where:** `Sources/NukeUI/ImageViewExtensions.swift:465`

**Repro:** [NukeUITests/nukeui-views--cross-dissolve-resets-alpha.swift](NukeUITests/nukeui-views--cross-dissolve-resets-alpha.swift)

**What:** runCrossDissolveWithContentMode sets transitionView.alpha = 1 and imageView.alpha = 0, then animates imageView.alpha to 1. This overwrites any alpha the app set, such as 0.5 for a dimmed or disabled cell, and draws the previous image at full opacity during the transition. The plain fade-in path (UIView.transition with a cross-dissolve, used when the content mode doesn't change) leaves alpha alone, so whether the app's alpha survives depends on the contentModes option. The repro includes a passing contrast test for the plain path.

**Expected:** imageView.alpha is still 0.5 after the transition.

**Actual:** imageView.alpha is 1.0.

**Reproduction check:** iOS 26.5 private simulator, 3/3 iterations: crossDissolvePreservesImageViewAlpha fails `imageView.alpha == 0.5` with actual 1.0. The contrast test simpleFadeInPreservesImageViewAlpha (same content mode, UIView.transition path) passes, so alpha stays 0.5 on that path.

**Refutation attempt (failed):**

I could not refute this. It is a real defect, though a narrow one. In /Users/kean/Developer/Nuke/Sources/NukeUI/ImageViewExtensions.swift:464-476, `runCrossDissolveWithContentMode` hard-codes `transitionView.alpha = 1` and `imageView.alpha = 0`, then sets `imageView.alpha = 1` inside the `UIView.animate` block. Setting a property inside an animation block changes the model value right away, so by the time the load completion runs, `imageView.alpha` is already 1. That makes the repro deterministic, not a timing artifact of the test. The other fade path, `runSimpleFadeIn`, uses `UIView.transition(... .transitionCrossDissolve)` and never touches alpha. The no-transition path doesn't either. So whether the app's alpha survives depends only on whether the content mode changes, which is the claimed inconsistency.

Intent: the manual cross-fade came in 2018 in commit 63ea2f86, "Simplified image transitions", with no message about alpha. Later edits to the function (PRs #792 and 33cbea74, which copy tint, corner radius, dynamic range, etc. onto the transition view) show that it tries to make the transition view mirror the image view's appearance, yet alpha is never copied or kept. The docs only say `fadeIn` is a "Fade-in transition (cross-fade in case the image view is already displaying an image)". Nothing in the docs, the CHANGELOG, or the commit history says the transition takes ownership of the view's alpha, so resetting it looks like an implementation shortcut, not a design choice.

Reachability: it is reachable through the public API, not only through @testable code. The repro uses @testable only for test helpers (MockDataLoader, Test.image). It sets `isPrepareForReuseEnabled = false` to keep a pre-set image. That option is public, and the flag isn't needed: the default flow reaches the same path. `loadImage` shows the placeholder with `contentModes.placeholder`, then shows the success image with `contentModes.success`. The config shown in Documentation/NukeUI.docc/ImageViewExtensions.md (`.init(success: .scaleAspectFill, failure: .center, placeholder: .center)`) plus a placeholder and `.fadeIn` therefore takes the cross-dissolve path on every non-memory-cache load. The only other requirement is that the app has set `imageView.alpha < 1`, for example to dim a disabled or already-watched cell. The result is that the dim setting is permanently lost, and the old image flashes at full opacity during the transition.

This is UIKit behaving as specified, with Nuke's code writing the literal value; it is not a platform quirk. I did not run the repro. I judged the static evidence to be conclusive.

Impact is low. It needs an app-set alpha on the image view itself; LazyImageView is not affected, because it fades its own internal imageView. It also needs `contentModes` whose success mode differs from the current mode, plus `.fadeIn`. When those conditions hold, the effect is visible and persistent.

**Suggested fix:** In `runCrossDissolveWithContentMode`, capture the view's current alpha and use it as the target instead of 1: `let targetAlpha = imageView.alpha`; set `transitionView.alpha = targetAlpha` and `imageView.alpha = 0` before the animation; inside the animation block, set `transitionView.alpha = 0` and `imageView.alpha = targetAlpha`. If a transition is interrupted (prepareForReuse's `removeAllAnimations`) or a second load arrives mid-animation, the model value is already `targetAlpha`, so the captured value stays correct. Add a regression test that runs the documented contentModes configuration with a placeholder and `imageView.alpha = 0.5`, and asserts that alpha is still 0.5 after the load.


### D60. LazyImageView's .fadeIn restarts from fully transparent for every progressive scan and for the final image while an image is already on screen

_Severity: low · user impact: low · public API: yes · known: defects.md #30 · found by: nukeui-views_

**Where:** `Sources/NukeUI/LazyImageView.swift:388 (display: `if !isFromMemory, let transition = transition { runTransition(...) }`, reached from handle(preview:) at line 339)`

**Repro:** [NukeUITests/nukeui-views--review-lazyimageview-fade-in-restarts-per-scan.swift](NukeUITests/nukeui-views--review-lazyimageview-fade-in-restarts-per-scan.swift)

**What:** Each progressive scan goes through display(_, isFromMemory: false), and so does the final image. Each time, runTransition runs the fade-in again: on iOS it sets imageView.alpha = 0 and animates to 1; on macOS it adds a CABasicAnimation for opacity from 0 to 1. With progressive decoding on, the visible image disappears and fades back in (0.33 s by default) on every scan and once more for the final image, which is a visible flicker. With isResetEnabled = false the old image also cuts to transparent instead of cross-fading. On iOS, loadImage(into:) uses a cross-dissolve from the current content, so it doesn't have this problem.

**Expected:** The transition brings the image in once. Later scans, or the final image replacing a visible preview, are swapped in place without fading from 0 again.

**Actual:** A new fade-in animation from 0 is added for scan 2 and for the final image. The repro records ["preview 2", "final"] on both macOS and iOS.

**Reproduction check:** macOS and iOS, 3/3 iterations each: `restartedFades.isEmpty` fails with `["preview 2", "final"]`. A new 0→1 opacity animation is on imageView's layer after scan 2 and after the final image. The macOS key is "imageTransition" and the iOS key is "opacity" from UIView.animate. The test clears animations after each preview, so these are new animations, not leftovers.

**Refutation attempt (failed):**

I could not refute this. The bug is real.

Code path: in /Users/kean/Developer/Nuke/Sources/NukeUI/LazyImageView.swift, `handle(preview:)` (line 339) calls `display(preview.container, isFromMemory: false)` for every scan. The final network result also arrives with `isFromMemory: false`, because `isSync` is false. `display` then runs `if !isFromMemory, let transition { runTransition(...) }` (line 388) and never checks whether an image is already on screen. `runFadeInTransition` only returns early when `imageView.isHidden`. After the first scan the view is no longer hidden, so the fade runs again:
- iOS: sets `imageView.alpha = 0`, then animates it back to 1.
- macOS: `CALayer.animateOpacity` in Internal.swift:66 adds a `CABasicAnimation` from 0 to 1 under the key "imageTransition".

The image on screen therefore drops to fully transparent and fades back in on every scan and again for the final image. The placeholder is already hidden at that point, so the background shows through.

Confirmed by running it. I cloned the repo into the scratchpad (the real repo was not modified), added the repro to Tests/NukeUITests and ran `xcodebuild test -scheme NukeUITests -destination platform=macOS`. It failed with `restartedFades → ["preview 2", "final"]`, exactly as claimed. I did not run the iOS variant; the UIKit path is plain from the source.

Not intentional or documented as far as I can find:
- The code comes unchanged from the 2022 "Move Sources from NukeUI" import (154f8fdce).
- No CHANGELOG entry, commit message or doc comment says per-scan fading is intended.
- The property doc says only "An animated transition to be performed when displaying a loaded image."
- The iOS `loadImage(into:)` path handles the same case on purpose. `ImageLoadingOptions.Transition.fadeIn` is documented as "cross-fade in case the image view is already displaying an image", and its `runSimpleFadeIn` uses `.transitionCrossDissolve`. LazyImageView is inconsistent with that.

Not an API misuse or test artifact:
- The repro only uses public API: pipeline config, `transition`, `url`, `onPreview`, `onCompletion`. It reads the layer's animations only to observe the result.
- `MockProgressiveDataLoader` just stands in for a slow progressive download.
- Setting `progressiveDecodingInterval = 0` only makes the scans reliable in the test. With the default 0.5 s interval and the default 0.33 s fade, each fade finishes before the next scan, so a slow connection shows a snap to blank and a fade every half second.
- Both `isProgressiveImageRenderingEnabled` and `.fadeIn(0.33)` are on by default in LazyImageView. The only opt-in is the pipeline's `isProgressiveDecodingEnabled` (off by default).
- It is not a UIKit/AppKit quirk. Nuke itself sets alpha to 0, or adds an animation whose fromValue is 0.
- The final-over-preview case also happens when a cached preview is shown first. That preview is displayed with `isFromMemory: true` and no fade, then the final image fades in from 0 over it.

Weaker parts of the claim:
- The `isResetEnabled = false` point is more a design choice than a defect. LazyImageView documents `.fadeIn` only as "Fade-in transition", with no cross-fade promise. Still, blanking out the kept content goes against the purpose of `isResetEnabled` ("keep the previous content").
- `loadImage(into:)` on macOS (ImageViewExtensions.swift:488-495) has the same fade-from-0 behavior for each scan, so macOS is not the clean comparison the report implies.

Impact is low. The effect is cosmetic and needs progressive decoding turned on in the pipeline plus a download slow enough to produce several scans. I found no GitHub issue about it in over four years (issues 745 and 709 are unrelated). But the flicker is plainly visible to anyone who hits it.

**Suggested fix:**

In `LazyImageView.display(_:isFromMemory:)`, check before calling `nuke_display` whether an image is already on screen, and don't restart `.fadeIn` from 0 when one is:

```swift
let isReplacingVisibleContent = customImageView != nil || (!imageView.isHidden && imageView.image != nil)
// ... existing removeCustomImageView / nuke_display ...
if !isFromMemory, let transition {
    switch transition {
    case .fadeIn(let duration) where isReplacingVisibleContent:
        runCrossDissolve(duration: duration) // or skip it: swap in place
    default:
        runTransition(transition, container)
    }
}
```

Options for `runCrossDissolve`:
- iOS: `UIView.transition(with: imageView, duration: duration, options: [.transitionCrossDissolve, .allowUserInteraction], animations: {})`. Better still, wrap the `nuke_display` call in it, the way `ImageViewController.runSimpleFadeIn` does.
- macOS: a `CATransition` of type `.fade` on `imageView.layer`, instead of the opacity animation from 0.
- Simplest: skip the fade once content is visible, so later scans and the final image swap in place.

Keep calling `.custom` closures on every display, since they receive the container and can check `isPreview`.

The same fix would help macOS `loadImage(into:)` (ImageViewExtensions.swift:488).

Add a regression test like the repro: with progressive loading, assert that no new opacity animation starting at 0 is added for scan 2 or later, or for the final image.


### D61. Coalesced requests with different imageIDs cache the result only under the first request's keys

_Severity: low · user impact: low · public API: yes · known: defects.md #17 · found by: pipeline-caching, request-model, task-engine_

**Where:** `Sources/Nuke/Internal/ImageRequestKeys.swift:56`

**Repro:** [NukeTests/pipeline-caching--coalesced-request-image-id-not-cached.swift](NukeTests/pipeline-caching--coalesced-request-image-id-not-cached.swift), [NukeTests/request-model--coalesced-image-id-override-not-cached.swift](NukeTests/request-model--coalesced-image-id-override-not-cached.swift), [NukeTests/task-engine--image-id-ignored-by-coalescing.swift](NukeTests/task-engine--image-id-ignored-by-coalescing.swift)

**What:** `TaskLoadImageKey` is built from `TaskFetchOriginalImageKey`, which uses `originalImageID` (the URL), plus the options and processors. The custom `imageID` is not part of the key; 3776cae7 dropped `MemoryCacheKey` from it. So concurrent requests for the same URL with different `imageID`s share one `TaskLoadImage`, which writes to memory and disk only under `self.request`, the first subscriber's request. The same happens for anything a delegate derives from `userInfo` in `cacheKey(for:)` or `imageCache(for:)`.

**Expected:** `imageID` is documented as "the image identifier used for caching and task coalescing". After both requests finish, each one can be served from the caches under its own ID.

**Actual:** `pipeline.cache[b] == nil`, the disk only has key "a", and loading `b` again downloads a second time (`createdTaskCount == 2`).

**Reproduction check:** In 3/3 iterations, `pipeline.cache[a] != nil` passed, but `pipeline.cache[b] != nil` failed, `pipeline.cache.containsData(for: b)` failed, and `dataLoader.createdTaskCount == 1` failed with actual value 2 after reloading b. Log: scratchpad/logs/repro-pipeline-caching-3.log

**Refutation attempt (failed):**

I could not refute the core claim. It is a real regression, but it only shows up in an unusual situation.

1. Reproduced at HEAD. I ran it in an isolated copy at scratchpad/verify-imageid-coalesce-k7; the repo was not touched. The macOS NukeTests run confirms it with public API only: a real `ImageCache`, no data cache, and two `pipeline.imageTask(with:)` calls for the same URL with imageID "a" and "b". The log prints `cache[a]=true cache[b]=false downloads=1`, and task b's `response.request.imageID` is "a". With `isTaskCoalescingEnabled = false`, both IDs are cached. A related symptom: if b is already in the memory cache while a is loading, `pipeline.imageTask(with: b)` joins a's download and waits for the network instead of returning the cached image (`cacheType` is nil). `ImagePrefetcher` has the same problem because it also uses `TaskLoadImageKey`. Prefetching [a, b] caches only a, and `stopPrefetching(with: [b])` finds a's task under the same key.

2. Not intentional. Before 3776cae7 (Nuke 12.6), `TaskLoadImageKey` contained `MemoryCacheKey`, which held `preferredImageId`. So same URL with different IDs did not coalesce. 3776cae7 is titled only "Optimize TaskLoadImageKey". It replaced that with `TaskFetchOriginalImageKey` (URL-based) and silently dropped the custom ID. The CHANGELOG says nothing about it. One day earlier, 2b55252b fixed the same kind of key gap for `scale` (#746), so the author does care about this. The only test in this area, `thatLoadKeyForProcessedImageDoesntUseFilteredURL`, covers the opposite case (different URL, same ID), which is still handled correctly. The `imageID` doc says it is "the image identifier used for caching and task coalescing", and no doc says different IDs share a task.

3. It is not a test artifact. Mocks only make the timing deterministic; the path is ordinary public API.

Parts of the report that do NOT hold:
- The disk-cache part (`containsData(for: b)` false) is older and separate. `TaskFetchOriginalData` has always been coalesced by `originalImageID` (the URL), on purpose ("the actual URL determines what gets fetched"). With the default `.storeOriginalData` policy it writes the original data under the first subscriber's key only. That was already true before 12.6, and fixing `TaskLoadImageKey` does not change it.
- The `userInfo`/delegate `cacheKey(for:)` part is not new either. The memory key never included `userInfo`.

Impact is low. It needs the same URL loaded at the same time under different `imageID`s, for example versioned IDs on a URL whose content changes, or IDs set per header. The effect is a missing memory-cache entry or a wait for a download, not a wrong image. The main UI paths (LazyImage, FetchImage, NukeExtensions) check the memory cache synchronously before they start a task. The bug has gone unnoticed since 12.6.0 (April 2024).

Fix verified: I added the custom image ID to `TaskLoadImageKey`. All 1109 NukeTests pass, and download counts stay at 1 because data loading is still shared by URL. The only failure left is the repro's own `containsData(for: b)` expectation, which is the older disk behavior described above.

**Suggested fix:**

Put the custom image ID back into `TaskLoadImageKey` (Sources/Nuke/Internal/ImageRequestKeys.swift:56). Use the override itself, not `request.imageID`. It is nil for default requests, so the common case hashes no extra string.
- ImageRequest.swift: add `var customImageID: String? { ref.customImageID }` next to `originalImageID`.
- TaskLoadImageKey: add `private let customImageID: String?`. Set it in `init` from `request.customImageID`, `hasher.combine(customImageID)` into the cached `_hashValue`, and add `lhs.customImageID == rhs.customImageID` to `==`.
This also fixes `ImagePrefetcher`'s dedupe and stop, and the load-data pool, because both use the same key. Data loading stays coalesced by URL, so there is still only one download.
I checked this in a scratch copy: the full NukeTests suite passes, and the repro's memory-cache and re-download expectations now pass. Its `containsData(for: b)` expectation should be dropped or tracked separately. That behavior comes from `TaskFetchOriginalData` coalescing by URL and storing the original data only under the first subscriber's key, and it predates 3776cae7. Fixing it would mean writing the data under every direct subscriber's data-cache key.
Add a coalescing test: same URL, different imageIDs, loaded at the same time, then check that both are in `pipeline.cache` after one download. Per the repo's no-perf-regression rule, run the pipeline benchmark A/B, interleaved.

- Also reported by **request-model** (confirmed): Coalesced requests for one URL with different imageID overrides: only the first is cached
- Also reported by **task-engine** (confirmed): Coalesced requests that differ only in imageID are cached under the first request's key only

### D62. containsCachedImage(caches: .disk) and containsData(for:) ignore .disableDiskCacheReads

_Severity: low · user impact: low · public API: yes · known: defects.md #15 · found by: pipeline-caching_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:114`

**Repro:** [NukeTests/pipeline-caching--contains-ignores-disk-read-option.swift](NukeTests/pipeline-caching--contains-ignores-disk-read-option.swift)

**What:** The disk branch of `containsCachedImage` (line 114) and `containsData` (line 193) query `DataCaching` directly, without the `.disableDiskCacheReads` guard that `cachedData(for:)` has. The memory branch of `containsCachedImage` does honor `.disableMemoryCacheReads`. The two methods therefore contradict `cachedData` and `cachedImage` for the same request.

**Expected:** For a request with `.disableDiskCacheReads`, both return false. accessing-caches.md says "All ImagePipeline.Cache respect request cache control options", and for that request `cachedData` and `cachedImage(caches: [.disk])` return nil.

**Actual:** Both return true.

**Reproduction check:** In 3/3 iterations, `cachedData(for:)` and `cachedImage(for:caches:[.disk])` returned nil as expected, while `!containsCachedImage(for:caches:[.disk])` and `!containsData(for:)` both failed, meaning both methods returned true. Log: scratchpad/logs/repro-pipeline-caching-5.log

**Refutation attempt (failed):**

I could not refute this. It is a real inconsistency in the public API, and I confirmed it without @testable or any mocks. I built a standalone SPM executable in the scratchpad against a `git archive` copy of HEAD Sources, using a real `DataCache` and `ImageCache` and only public API. I stored a PNG through `pipeline.cache.storeCachedData` and then called `await dataCache.flush()`. For `ImageRequest(url:, options: [.disableDiskCacheReads])` the results were:
- `cachedData` returns nil.
- `cachedImage(caches: [.disk])` returns nil.
- `containsCachedImage(caches: [.disk])` returns true.
- `containsData` returns true.

With `.reloadIgnoringCachedData`, `containsCachedImage()` (defaults to `.all`) returns true while `cachedImage()` returns nil. On the memory side, `containsCachedImage(caches: [.memory])` with `.disableMemoryCacheReads` correctly returns false, because it goes through `cachedImageFromMemoryCache`, which has the options guard. So one method honors read options for memory but not for disk.

Documentation: accessing-caches.md says "All ImagePipeline/Cache-swift.struct respect request cache control options." Neither `contains*` doc comment claims an exception.

History: `containsData(for:)` was added in 834da2cb on 2021-05-15. The granular `.disableDiskCacheReads`/`.disableDiskCacheWrites` options came three days later in c6471c63, which added the guard to `cachedData`/`storeCachedData` but never touched `containsData` or the disk branch of `containsCachedImage`. That looks like an oversight, not a design choice. Nothing in the CHANGELOG, commit messages or docs describes "contains" as a raw storage probe that ignores options. Existing tests never combine `contains*` with read-disabling options, and no code in Sources calls these methods, so a fix won't break the pipeline.

Small correction to the report: line 114 is the memory branch, which is correct. The faulty disk branch is at lines 117-120, and `containsData` is at lines 193-198.

Impact is low. A caller would need to build a request with `.disableDiskCacheReads` or `.reloadIgnoringCachedData` and then ask whether it is cached. For example, a "cached" badge driven by the same request used for a forced reload would show true even though the pipeline will go to the network. The fix does change observable behavior for anyone who relied on the old answer, but it matches the documented promise and the memory half of the same method.

**Suggested fix:**

In Sources/Nuke/Pipeline/ImagePipeline+Cache.swift, add the read guard to `containsData(for:)` and route the disk branch of `containsCachedImage` through it:

```swift
public func containsCachedImage(for request: ImageRequest, caches: Caches = [.all]) -> Bool {
    if caches.contains(.memory) && cachedImageFromMemoryCache(for: request) != nil {
        return true
    }
    if caches.contains(.disk) {
        return containsData(for: request)
    }
    return false
}

public func containsData(for request: ImageRequest) -> Bool {
    guard !request.options.contains(.disableDiskCacheReads),
          let dataCache = dataCache(for: request) else {
        return false
    }
    return dataCache.containsData(for: makeDataCacheKey(for: request))
}
```

Next to the existing `disableDiskCacheReads` test in Tests/NukeTests/ImagePipelineTests/ImagePipelineCacheTests.swift, add a test asserting that both `contains` methods return false for a `.disableDiskCacheReads` request (and for `.reloadIgnoringCachedData` with caches `.all`). Add a short CHANGELOG line linking the PR.


### D63. ImageRequest(id:image:) is stored in the disk cache although the doc says it never is

_Severity: low · user impact: low · public API: yes · found by: pipeline-caching, request-model_

**Where:** `Sources/Nuke/Tasks/TaskLoadImage.swift:190`

**Repro:** [NukeTests/pipeline-caching--image-closure-request-stored-on-disk.swift](NukeTests/pipeline-caching--image-closure-request-stored-on-disk.swift), [NukeTests/request-model--closure-image-stored-in-disk-cache.swift](NukeTests/request-model--closure-image-stored-in-disk-cache.swift)

**What:** The doc for `init(id:image:...)` (ImageRequest.swift:249) says "the image is never stored in the disk cache because no raw data is available". But `shouldStoreResponseInDataCache` does not treat the `.image` resource differently. The image is encoded and stored always under `.storeEncodedImages`, and for requests with processors under `.automatic` and `.storeAll`. Either the doc or the behavior should change.

**Expected:** Per the doc, the disk cache stays empty for an image-closure request.

**Actual:** The encoded image is stored under "closure" (or "closurep1" with a processor).

**Reproduction check:** In 3/3 iterations, `dataCache.store.isEmpty` failed. Stored keys were ["closure"] for .storeEncodedImages without a processor, and ["closurep1"] for .automatic and .storeAll with processor p1. Log: scratchpad/logs/repro-pipeline-caching-7.log

**Refutation attempt (failed):**

Not refuted, but this is a documentation bug. The behavior itself is intended.

Reproduced on macOS in a scratch copy of the repo, which was left unchanged. I ran every policy for an ImageRequest(id:"closure", image:), with and without a processor:
- .automatic: nothing stored without a processor; "closurep1" stored with one
- .storeOriginalData: nothing stored either way
- .storeEncodedImages: "closure" / "closurep1" stored
- .storeAll: nothing stored without a processor; "closurep1" stored with one
Under .storeEncodedImages the second load comes from disk (cacheType == .disk) and the closure is not called again. Only public API is needed; the mocks just stand in for a real DataCache.

Why the behavior is intended, and only the doc is wrong:
- Commit 7b91a667 (2022, "Update data cache policy") removed the old `request.url?.isCacheable` guard from TaskLoadImage on purpose. Since then the processed/encoded storage path follows DataCachePolicy for every resource type.
- The policy docs say this outright: `.automatic` says "Store only processed images for local resources", `.storeAll` says "only the processed images are stored" for local resources, and `.storeEncodedImages` says "Encode and store images".
- An image closure is effectively a resource with no raw data. Nothing is stored for it under the default `.storeOriginalData`, and the doc holds there.
- Commit 43c5eaa3 added init(id:image:) and the note, and made no change to TaskLoadImage caching. The note's own reason ("because no raw data is available") shows it meant original data only.

Still, the public doc makes a flat promise: "the image is never stored in the disk cache". That is false under the three opt-in policies. A user who relies on it (for example, keeping Photos-derived images off disk, or expecting the closure to run again on the next launch) would be misled.

It matters more because of a separate bug found while checking this, and not claimed by the reporter: TaskLoadImage.shouldStoreResponseInDataCache / storeImageInDataCache ignore `.disableDiskCacheWrites`. Verified: with that option, `.storeEncodedImages` still stored "closure", and a URL request with a processor under `.automatic` still stored "http://test.com/example.jpegp1". So the per-request opt-out that init(id:data:) documents does not work on this path, for any resource. The check seems to have been dropped by mistake in 19423094 (2021). TaskLoadImageKey includes the request options, so checking the option per request is safe.

Impact is low. The default policy matches the doc, the other policies must be chosen on purpose, and caching the processed result is usually what users want.

**Suggested fix:**

Fix the doc only; keep the behavior, which follows DataCachePolicy. In Sources/Nuke/ImageRequest.swift:252-253, replace the note with something like: "- note: Unlike init(id:data:...), no original data is stored in the disk cache because none is available. Depending on ImagePipeline/DataCachePolicy, the pipeline may still encode and store the image: processed images with .automatic and .storeAll, and all images with .storeEncodedImages." Add a test covering this policy matrix to ImagePipelineDataCacheTests.

Separate issue, worth its own fix: in Sources/Nuke/Tasks/TaskLoadImage.swift shouldStoreResponseInDataCache, add `!request.options.contains(.disableDiskCacheWrites)` to the guard. Options are part of TaskLoadImageKey, so a per-request check is correct. Then `.disableDiskCacheWrites` / `.disableDiskCache` will also block encoded and processed disk writes, as the Options docs say.

- Also reported by **request-model** (confirmed): init(id:image:) images are stored in the disk cache despite the doc saying "never"

### D64. ImagePipeline.Cache.storeCachedImage encodes the image even when nothing will be written to disk

_Severity: low · user impact: low · public API: yes · found by: pipeline-caching_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:88`

**Repro:** [NukeTests/pipeline-caching--review-store-cached-image-encodes-without-disk.swift](NukeTests/pipeline-caching--review-store-cached-image-encodes-without-disk.swift)

**What:** `storeCachedImage(_:for:caches:)` calls `encodeImage(_:for:)` inside `if caches.contains(.disk), !image.isPreview`, before anything checks that a disk layer exists or that writes are allowed. The data cache and `.disableDiskCacheWrites` are checked only afterwards, in `storeCachedData` (line 176). So when the pipeline has no data cache, the image is still fully encoded (JPEG/HEIF) on the calling thread and the result is thrown away. No data cache is the default configuration, which ImagePipeline.shared uses via .withURLCache. The same happens when the delegate returns nil from `dataCache(for:)` or the request has `.disableDiskCacheWrites`. The pipeline's own path, `TaskLoadImage.storeImageInDataCache`, resolves the data cache before encoding. The doc for this method says it is safe to call from the main thread.

**Expected:** With the default caches [.all], the encoder is not called when there is no data cache or when the request disables disk writes.

**Actual:** encoder.encodeCount == 1 in both cases; the encoded data is discarded.

**Reproduction check:** In 3/3 iterations, `encoder.encodeCount == 0` failed with actual value 1 in both cases: no data cache (dataCache == nil confirmed), and a MockDataCache with a `.disableDiskCacheWrites` request (the store stayed empty). Log: scratchpad/logs/repro-pipeline-caching-9.log

**Refutation attempt (failed):**

I could not refute this. The behavior is real, a user can reach it through the public API, and nothing in the repo says it is intended.

Code: in /Users/kean/Developer/Nuke/Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:92-96, `storeCachedImage` calls `encodeImage(image, for: request)` whenever `caches.contains(.disk) && !image.isPreview`. The data cache and `.disableDiskCacheWrites` are checked only afterwards, in `storeCachedData` (lines 179-186), which returns early and throws the encoded data away. The pipeline's own path, `TaskLoadImage.storeImageInDataCache` (Sources/Nuke/Tasks/TaskLoadImage.swift:185-203), does it the other way round: it resolves `delegate.dataCache(for:)` first and returns before encoding when there is none.

Repro: I copied HEAD (2c2b23f6) into the scratchpad and ran the repro test with `xcodebuild test -scheme Nuke -destination platform=macOS`. Both tests fail with `encoder.encodeCount == 0` not met, so the encoder does run.

- The API is used as documented. `storeCachedImage` and the `ImageEncoding`/`makeImageEncoder` hooks are public, and nothing internal or `@testable` is needed.
- It is not a mock artifact. The default `ImageEncoding.encode(_:context:)` calls `encode(image)`, and with `ImageEncoders.Default` that is a real JPEG, PNG or HEIF encode through ImageIO.
- The default setup hits it. `ImagePipeline.shared` uses `.withURLCache`, which has no `dataCache`. The documented call `cache.storeCachedImage(ImageContainer(image: image), for: request)` (DocumentationTests.swift:104-106) uses the default `caches: [.all]`, so it encodes on the calling thread and throws the result away.
- Nothing marks it as intended. Git blame shows the encode-then-store shape unchanged since 2021/2022. The only later change is PR #885 (402da590c), which added the `isPreview` guard and is unrelated. No CHANGELOG entry or doc says encoding always runs. The doc comment says "To store image in the disk cache, it will be encoded", which ties encoding to a disk store.

Limits on severity: this is only wasted work and gives no wrong results. Nothing wrong is written, and the memory cache store is correct. The "safe to call from the main thread" note is about `DataCache` writing asynchronously; even with a data cache configured, the encode already runs synchronously. The real waste is limited to three cases: no data cache (the default), the delegate returning nil from `dataCache(for:)`, and requests with `.disableDiskCacheWrites`. In those cases every call pays a full encode, from a few ms up to tens of ms for large images, often on the main thread. A custom encoder with side effects (logging, metrics) is also called for nothing. Impact is low.

**Suggested fix:**

In `storeCachedImage`, resolve the data cache and check the write option before encoding, and store directly so the delegate is asked for the data cache only once:

```swift
if caches.contains(.disk), !image.isPreview,
   !request.options.contains(.disableDiskCacheWrites),
   let dataCache = dataCache(for: request),
   let data = encodeImage(image, for: request) {
    dataCache.storeData(data, for: makeDataCacheKey(for: request))
}
```

Turn the repro into regression tests in ImagePipelineCacheTests: one where there is no data cache, one where the delegate returns nil from `dataCache(for:)`, and one with `.disableDiskCacheWrites`. In each, `encodeCount == 0`. Keep a positive test showing that with a data cache the encoder runs once and the data is stored.


### D65. A progressive preview in the memory cache makes ImagePrefetcher skip the image

_Severity: low · user impact: low · public API: yes · found by: prefetch-internals_

**Where:** `Sources/Nuke/Prefetching/ImagePrefetcher.swift:139`

**Repro:** [NukeTests/prefetch-internals--cached-preview-skips-prefetch.swift](NukeTests/prefetch-internals--cached-preview-skips-prefetch.swift)

**What:** `guard pipeline.cache[request] == nil else { return }` treats any memory cache entry as already prefetched, including a preview (`isPreview == true`). The memory cache stores previews by default (`isStoringPreviewsInMemoryCache` is true), for example the scans left by a progressive load that was cancelled when its cell scrolled off screen. The pipeline itself doesn't treat a cached preview as final: `TaskLoadImage.start()` delivers it as a preview and keeps loading the full image. The prefetcher instead does nothing and calls didComplete right away. The image then still has to be downloaded when it's displayed, which is the delay the prefetcher exists to remove.

**Expected:** A prefetch task starts (startedTaskCount == 1, one data task) and the full image replaces the preview in the memory cache.

**Actual:** startedTaskCount == 0 and createdTaskCount == 0, and the memory cache still holds the preview (isPreview == true). 5 out of 5 runs.

**Reproduction check:** All 3 iterations failed with `observer.startedTaskCount → 0` (expected 1), `dataLoader.createdTaskCount → 0` (expected 1) and `pipeline.cache[Test.request]?.isPreview → true` (expected false). The failure matches the claim. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-prefetch-internals-2.log

**Refutation attempt (failed):**

I couldn't refute it. The bug is real and reachable through public API, but only in a narrow configuration.

Code: `ImagePrefetcher._startPrefetching(with:)` (Sources/Nuke/Prefetching/ImagePrefetcher.swift:139) returns early whenever `pipeline.cache[request] != nil`. It never checks `isPreview`. The pipeline treats a cached preview differently. `TaskLoadImage.start()` (Sources/Nuke/Tasks/TaskLoadImage.swift:14-19) sends it with `isCompleted: !container.isPreview` and keeps loading the full image. So the prefetcher and the pipeline disagree about whether a cached preview counts as "the image".

Intent and history: the guard has been there since the ImagePreheater days. In 002fadf4 it carried the comment "The image is already in memory cache". No commit message, CHANGELOG entry or DocC article says a preview should count as prefetched. The `didComplete` doc says "every image is already in the memory cache", and a preview isn't the image. The type's stated purpose is "Prefetches and caches images to eliminate delays when requesting the same images later." The existing tests cover only a final `Test.container` hit, not a preview.

How a preview gets there: `storeCachedImageInMemoryCache` stores previews when `isStoringPreviewsInMemoryCache` is true, which is the default. Nothing removes a preview when its task is cancelled or fails. I confirmed this with an end-to-end test that uses only public API, in an exported copy of HEAD in the scratchpad; the repo wasn't touched. The test enables progressive decoding with `MockProgressiveDataLoader` and a real `ImageCache`, waits for the first preview, then cancels the task. The preview stays in the memory cache. `ImagePrefetcher.startPrefetching` then starts no task.

Results:
- The agent's repro fails as described: startedTaskCount 0, createdTaskCount 0, and the cache still holds the preview.
- Control: `pipeline.imageTask(with:)` over the same cached preview does load the final image and replaces the preview in the cache.
- Control: a final image in the memory cache still makes the prefetcher skip, which is the intended behavior.

It isn't a mock or timing artifact, and it isn't platform behavior.

Why the impact is low:
- It needs `isProgressiveDecodingEnabled = true`, which is off by default.
- The image has to be a format the default preview policy covers (progressive JPEG or GIF).
- A load has to stop after at least one scan, for example a cell scrolling off screen, or the app has to store a preview itself.
- When it happens, the prefetch silently does nothing and `didComplete` fires early. The image still displays correctly: the preview first, then the full load. You just lose the prefetch benefit for that URL. With `.diskCache` destination, the data also never reaches disk.

I applied the fix below in the scratch copy. The repro passes, and so do all 34 tests in ImagePrefetcherTests, the repro and the controls.

**Suggested fix:**

In Sources/Nuke/Prefetching/ImagePrefetcher.swift `_startPrefetching(with request:)`, skip only when a final image is cached:

    if let image = pipeline.cache[request], !image.isPreview {
        return // The final image is already in the memory cache
    }

No other change is needed. When the prefetch runs, TaskLoadImage already delivers the cached preview and goes on to fetch the full image, which then replaces the preview in the memory cache (and writes to disk for `.diskCache` destination). Add a regression test to ImagePrefetcherTests: seed `pipeline.cache[Test.request] = ImageContainer(image: Test.image, isPreview: true)`, prefetch, then expect one started task and a non-preview entry in the cache. Optionally add a CHANGELOG line along the lines of "Fix `ImagePrefetcher` skipping images that only have a progressive preview in the memory cache".


### D66. GaussianBlur converts wide-gamut (Display P3) images to DeviceRGB (regression from the grayscale crash fix)

_Severity: low · user impact: low · public API: yes · known: defects.md #24 · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift:68`

**Repro:** [NukeTests/processing-graphics-encoding--gaussian-blur-drops-wide-gamut.swift](NukeTests/processing-graphics-encoding--gaussian-blur-drops-wide-gamut.swift)

**What:** Commit 9e3af8e6 (#880, the fix for the grayscale blur crash) forces CGColorSpaceCreateDeviceRGB() for the scratch contexts of every image, not only for the color spaces vImage's ARGB8888 layout can't take. Before that commit, blur used the image's own color space and P3 stayed P3. Resize, Circle, RoundedCorners and decompression all keep the wide gamut and have extendedColorSpaceSupport tests; blur now clips P3 colors to sRGB. Reproduces on macOS and iOS.

**Expected:** The blurred image-p3.jpg keeps a wide-gamut color space (`isWideGamutRGB == true`).

**Actual:** The output color space is kCGColorSpaceDeviceRGB (`isWideGamutRGB == false`).

**Reproduction check:** `colorSpace.isWideGamutRGB` failed in 3/3 iterations on macOS and in 3/3 on a private iOS 26.5 simulator. The precondition that the input image-p3.jpg is wide gamut passed. Logs: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-4.log and repro-processing-graphics-encoding-4-ios.log

**Refutation attempt (failed):**

I couldn't refute this one. It's a real regression, unintended and undocumented, that users can hit through the public API.

History:
- Nuke 12's Core Image blur also returned a non-wide-gamut image. I checked on macOS: CIContext.createCGImage gave kCGColorSpaceDeviceRGB.
- 428828e0 rewrote blur on Accelerate (shipped in 13.0.x). It drew into `CGContext.make(self, size:, alphaInfo:)`, which uses `image.colorSpace`, so a P3 image stayed P3.
- 9e3af8e6 (PR #880, shipped in 13.1.0) changed both scratch contexts to `CGColorSpaceCreateDeviceRGB()` for every image. That fixed grayscale images, whose 16-bit gray+alpha buffers vImageBoxConvolve_ARGB8888 overran. The PR text, the code comment and the CHANGELOG entry mention only grayscale, not wide gamut. So dropping P3 was a side effect, not a decision. Later commits (c6089f21 opacity, 40d2d0c9 radius 0) kept the DeviceRGB spaces.

Current behavior goes against the library's own convention. CHANGELOG #408 says "Add support for extended color spaces", and "Decompression and resizing now preserve image color space". Resize, Circle, RoundedCorners, decompression and the pipeline all have P3-preserving tests. Blur is the only processor that goes through a DeviceRGB context.

Verified with a standalone probe (scratchpad/refute-blur-p3/main.swift) that runs the exact current blur code on Tests/Resources/image-p3.jpg:
- The input is kCGColorSpaceDisplayP3.
- The current output is kCGColorSpaceDeviceRGB, with isWideGamutRGB == false.
- The same code using the image's own color space (the 13.0.x behavior) outputs DisplayP3, with isWideGamutRGB == true.

This is not just a tag change. Drawing P3 into DeviceRGB converts the colors the same way sRGB does, so out-of-gamut colors are clipped. For example, P3 (51,204,76) comes out as (0,208,51), and P3 pure red becomes sRGB red, which is (234,51,35) when converted back to P3.

The repro only uses public API: `ImageProcessors.GaussianBlur(radius:).process`, the existing `Test.image` fixture helper, and CGColorSpace.isWideGamutRGB. Through the pipeline, a request with `.gaussianBlur()` for a P3 image gets the same result. It is not a platform quirk, since Nuke chooses the context color space. It is not a test artifact either.

Impact is low. The output is a blurred image, which is mostly used for placeholders and backgrounds. Clipping saturated P3 colors to sRGB is visible on wide-gamut displays but is not a crash or a functional failure, and Nuke 12 behaved the same way.

**Suggested fix:**

In `CGImage.blurred(radius:)` (Sources/Nuke/Processing/ImageProcessors+GaussianBlur.swift:68-69), switch to DeviceRGB only for color spaces that don't give a 4-channel 8-bit layout. Use the same space for both contexts, and fall back to DeviceRGB if CGContext rejects the space, for example extended-range spaces at 8 bpc:

```swift
let rgbSpace = colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
func makeContexts(_ cs: CGColorSpace) -> (CGContext, CGContext)? {
    guard let i = CGContext.make(self, size: size, alphaInfo: alphaInfo, colorSpace: cs),
          let o = CGContext.make(self, size: size, alphaInfo: alphaInfo, colorSpace: cs) else { return nil }
    return (i, o)
}
guard let (inputCtx, outputCtx) = rgbSpace.flatMap(makeContexts) ?? makeContexts(CGColorSpaceCreateDeviceRGB()) else { return nil }
```

Grayscale, CMYK and indexed images still go through DeviceRGB, so the #880 crash fix stays in place. Add a GaussianBlurTests `extendedColorSpaceSupport` test using image-p3.jpg and expecting `isWideGamutRGB`, matching the Resize, Circle and RoundedCorners tests. Keep `blurGrayscaleImageDoesNotCrash`.


### D67. Resize(width:)/Resize(height:) cap the other dimension at 9999, shrinking tall or wide images below the requested size

_Severity: low · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+Resize.swift:45`

**Repro:** [NukeTests/processing-graphics-encoding--resize-width-height-capped-at-9999.swift](NukeTests/processing-graphics-encoding--resize-width-height-capped-at-9999.swift)

**What:** `init(width:)` is `.aspectFit` into (width, 9999), and `init(height:)` into (9999, height), in the unit given, so 9999 px on macOS or with `.pixels`. If the image's other side would exceed 9999 at the requested size, that side becomes the limit. The image is then scaled below the requested width or height. It is even downscaled when it is already narrower than the target and `upscale` is false. This affects tall images (long screenshots, webtoon strips) and wide panoramas. The docs say 'Scales an image to the given width preserving aspect ratio.'

**Expected:** Resize(width: 5, unit: .pixels) of a 10x30000 image gives 5x15000. Resize(height: 5) of a 30000x10 image gives 15000x5. Resize(width: 200) of a 100x20000 image returns the input unchanged.

**Actual:** 3x9999, 9999x3, and a downscaled 50x9999.

**Reproduction check:** All 3 tests failed in all 3 iterations (macOS). Resize(width: 5, unit: .pixels) of 10x30000 gave 3x9999. Resize(height: 5, unit: .pixels) of 30000x10 gave 9999x3. Resize(width: 200, unit: .pixels) of 100x20000 returned a new image instead of the input (`output === input` false). Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-5.log

**Refutation attempt (failed):**

The report is accurate, and it comes from the public API. I checked it against the code; I did not run the test.

**How the numbers come out.** `init(width:)` builds `Resize(size: (width, 9999), contentMode: .aspectFit)`, and `init(height:)` builds `Resize(size: (9999, height), contentMode: .aspectFit)` (Sources/Nuke/Processing/ImageProcessors+Resize.swift:45,55). `ImageTargetSize` multiplies both sides by `Screen.scale` for `.points`. On macOS that scale is always 1, and with `.pixels` nothing is scaled, so the other side is capped at 9999 px. In Sources/Nuke/Internal/Graphics.swift:43-48, `byResizing` takes `getScale(.aspectFit)`, which is `min(scaleHor, scaleVert)` (Graphics.swift:252-253), and returns the input only if that scale is at least 1 and `upscale` is false. Worked through by hand:
- 10x30000 at width 5: min(0.5, 0.3333) gives 3.33x9999, which rounds to **3x9999**.
- 100x20000 at width 200: min(2, 0.49995) is below 1, so it is downscaled to **50x9999**, not returned unchanged.
- The height case (30000x10 at height 5) is the same calculation with the sides swapped.

**What the docs promise.** The doc comments on `Resize.init(width:)`, `init(height:)` and the `.resize(width:)` / `.resize(height:)` shorthands (ImageProcessors.swift:32-49) only say "Scales an image to the given width/height preserving aspect ratio." No cap is mentioned there, in Nuke.docc, in the CHANGELOG (line 1256 announces the initializers with no caveat), or in any test. The only place 9999 shows up is the `description` string that ImagePipelineTests.swift:477 checks. The existing tests (ResizeTests.swift:38-58) cover only a 640x480 image.

**Is the cap intentional?** In part. f3dfce5c (2020-03) first used `.greatestFiniteMagnitude`, meaning no limit. The next day, 160ef0ba ("Specify max height for fill resizers") changed it to 4096. Then 4c9f842f (Dec 2020) raised it to 9999 without explaining why. So a bound was chosen on purpose, but it works as a large stand-in for "no limit" that is never documented. Nothing states that users should expect a result narrower than the width they asked for. It is also not a platform behavior or a test artifact: the repro only uses public API (`process(_:)`) on an ordinary CGImage-backed image.

**Who hits it.** You need an extreme aspect ratio. Undershooting the requested width happens when width × (image height / image width) > 9999 in the chosen unit, for example ratios above about 31:1 for `.resize(width: 320)`. Downscaling an image that should be left alone happens when the original is taller than 9999 × scale px (29997 px on a 3x iPhone, 9999 px on macOS or with `.pixels`). Realistic cases are webtoon strips, stitched long screenshots and wide panoramas used with `resize(height:)`, and they are most likely on macOS. The result is quietly smaller and blurrier than requested, with no crash or error. Impact is low.

**Suggested fix.** See `suggestedFix`. The key constraint is that simply putting `.greatestFiniteMagnitude` back no longer works.

**Suggested fix:**

Do not go back to `.greatestFiniteMagnitude`. `ImageTargetSize` stores `Float`, so the value becomes `inf`, and `byResizing` now returns nil for a non-finite target (Graphics.swift:40, added in 1affc80e). That would turn the cap into a processing failure.

Minimal fix: have `Resize` remember which side is the constraint, for example `private enum Fit { case size, width, height }`, set by `init(width:)` and `init(height:)`. In `process(_:)`, for `.width` and `.height`, work out the other side of the target from the image itself before calling `byResizing(contentMode: .aspectFit)`:
```swift
// .width case
let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
target = CGSize(width: size.width, height: size.width * h / w)
```
Use the pixel size as oriented for display, so that `rotatedForOrientation` still behaves correctly for EXIF-rotated images on UIKit. `.height` is the mirror image. The scale is then `targetWidth / imageWidth`, so `upscale: false` returns the input whenever the image is already narrower than requested, however tall it is. This does not change the target for any image whose other side stays under 9999 at the requested size, so results for ordinary images stay the same.

Decide on purpose whether to change `identifier`/`hash`. Leaving `s=(w, 9999.0)` keeps existing disk and memory cache keys but can serve old, capped results for the affected images. Adding a `fit=width` component makes those entries miss once. Also update the doc comments, and add regression tests for 10x30000 at width 5 px (expect 5x15000), 30000x10 at height 5 px (expect 15000x5), and 100x20000 at width 200 px (expect the same instance back).


### D68. Resize fails (returns nil) for thin images whose short side scales below half a pixel

_Severity: low · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Internal/Graphics.swift:47`

**Repro:** [NukeTests/processing-graphics-encoding--resize-thin-image-fails.swift](NukeTests/processing-graphics-encoding--resize-thin-image-fails.swift)

**What:** `byResizing` rounds the scaled size. A side that scales below 0.5 px rounds to 0, which the pixelDimension guard (added for #888) rejects. Resize.process returns nil and the request fails with processingFailed. This hits separators, progress bars and gradient strips, e.g. a 1000x2 image with `.resize(width: 100)` or an aspect-fit into 100x100. Image I/O's own downsampling (ThumbnailOptions) returns 100x1 for the same input and target.

**Expected:** A 1000x2 image fitted into 100x100, or resized to width 100, gives 100x1.

**Actual:** nil (processing fails).

**Reproduction check:** fittingThinImageProducesAOnePixelThinImage and resizingThinImageToWidth both failed at `try #require(output?.cgImage)` in 3/3 iterations, because Resize.process returned nil. The control test, which runs ThumbnailOptions.makeThumbnail on the same 1000x2 PNG, passed with 100x1. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-6.log

**Refutation attempt (failed):**

I could not refute this. The bug is real and a user can hit it through the public API, although only in rare cases.

Where it happens: in `byResizing` (Sources/Nuke/Internal/Graphics.swift:47), `let size = cgImage.size.scaled(by: scale).rounded()`. A 1000x2 image with `.aspectFit` into 100x100 gets scale 0.1, so the height is 0.2 and rounds to 0. `CGContext.make` then returns nil because `pixelDimension` requires a value of at least 1, and `Resize.process` returns nil.

What I ran: a scratch SwiftPM package with a copy of Sources/Nuke. I did not modify the repo.
- The repro's two Resize tests fail with `output?.cgImage == nil`. The `ThumbnailOptions` test passes and gives 100x1.
- Other sizes with `.resize(width:unit:.pixels)`:
  - 1000x2 → 100, 1000x4 → 100, 2000x2 → 300 and 3000x1 → 1000 all return nil.
  - 1000x1 → 600 gives 600x1 and 1200x3 → 200 gives 200x1, because those heights round to 1 or more.
- Through the real pipeline, loading a 1000x2 PNG with `processors: [.resize(width: 100, unit: .pixels)]` throws "Failed to process the image using processor Resize(size: (100.0, 9999.0) pixels, contentMode: .aspectFit ...)", which is `processingFailed`. The same file with `request.thumbnail = ThumbnailOptions(size: 100x100, unit: .pixels, contentMode: .aspectFit)` gives 100x1.

The repro uses `@testable import`, but it only calls public API (`ImageProcessors.Resize.process`, `ThumbnailOptions.makeThumbnail`), and the pipeline path shows the same failure.

Is it intentional? I found nothing saying so. The doc comments for `resize(width:)`, `resize(height:)` and `Resize(size:contentMode:.aspectFit)` say "Scales an image to the given width preserving aspect ratio", with no caveat about extreme aspect ratios. The #888 tests (`drawingPrimitivesReturnNilForInvalidTargetSizes`, `thatProcessingFailsForInvalidTargetSize`) only require nil for invalid targets the user passes in: NaN, infinity, 0x0 and negative sizes. They don't cover a valid target where the scaled size is computed internally. Neither CHANGELOG.md nor the commit history says thin images should fail.

One detail in the report is wrong. The behavior did not come from #888. The rounding line dates from 505129dc (2021), and before #888 `CGContext(width: 0, ...)` also returned nil. So this is a long-standing bug, not a regression.

It is Nuke's own drawing code, not ImageIO, UIKit or URLSession behavior: ImageIO's own downsampling handles the same input. It is not a test artifact either, since the image is a plain CGContext bitmap and the pipeline path reproduces it.

Impact is low:
- It only affects `.aspectFit`, which includes `resize(width:)` and `resize(height:)`.
- It needs an aspect ratio above twice the target's long side in pixels. For example, `.resize(width: 320)` on a 3x device is 960 px, so the image needs a width-to-height ratio above 1920, like a 2000x1 hairline or a 4000x2 strip.
- The default `.resize(size:)` uses `.aspectFill`, which scales by the larger ratio and is not affected.
- When it does happen, though, the whole request fails and no image is shown at all, when a 1-px-thin image was possible.

A related edge exists in `byResizingAndCropping` when `upscale == false`: `canvasSize = targetSize.scaled(by: 1 / scale).rounded()` can also round to 0, for example a 10x10 image cropped into a 1000x1 target. That case is contrived.

**Suggested fix:**

In `ImageProcessingExtensions.byResizing` (Sources/Nuke/Internal/Graphics.swift), clamp each scaled side to at least 1 px. Keep rejecting non-positive targets so the existing #888 tests still pass:

```swift
let scale = cgImage.size.getScale(targetSize: targetSize, contentMode: contentMode)
guard scale > 0 else {
    return nil // A zero or negative target has nothing to draw in
}
guard scale < 1 || upscale else {
    return image
}
let scaled = cgImage.size.scaled(by: scale).rounded()
// A side that scales below half a pixel still has to be drawn, like Image I/O thumbnails do
let size = CGSize(width: max(1, scaled.width), height: max(1, scaled.height))
return image.draw(inCanvasWithSize: size)
```

Optionally apply the same `max(1, …)` clamp to `canvasSize` in the `!upscale` branch of `byResizingAndCropping`.

Tests to add:
- 1000x2 with `.resize(width: 100, unit: .pixels)` gives 100x1.
- 2x1000 with `.resize(height: 100, unit: .pixels)` gives 1x100.
- 1000x2 with `.aspectFit` into 100x100 gives 100x1.
- 0x0 and negative targets still return nil.


### D69. Circle/RoundedCorners draw the border at half the requested width

_Severity: low · user impact: low · public API: yes · known: defects.md #22 · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Internal/Graphics.swift:123`

**Repro:** [NukeTests/processing-graphics-encoding--border-drawn-at-half-width.swift](NukeTests/processing-graphics-encoding--border-drawn-at-half-width.swift)

**What:** `byAddingRoundedCorners` clips to the rounded-rect path, then strokes the same path with `setLineWidth(border.width)`. A stroke is centred on its path, so the outer half falls outside the clip and is lost. A 6 px border renders 3 px wide, and the 1 pt default renders half a point. `Border.width` is documented as the border width and appears in identifiers and descriptions as 'width: 6.0 pixels'. The reference snapshot for the disabled snapshot test (s-rounded-corners-border.png) shows the same 2 px border for a requested 4 px, so the maintainer may consider it intended. A fix could inset the stroked path by width/2.

**Expected:** The 6 pixel rows along the top edge are the border color.

**Actual:** Only the first 3 rows are red: [255, 255, 255, 4, 4, 4, …].

**Reproduction check:** In 3/3 iterations, the first 8 pixel rows of column 20 had red channel [255, 255, 255, 4, 4, 4, 4, 4]. Only 3 rows were red for a 6 px border, so `prefix(6).allSatisfy { $0 > 200 }` failed. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-7.log

**Refutation attempt (failed):**

I couldn't refute this. The bug is real, it goes back years, and users can reach it through the public API.

**How the code draws it.** In Sources/Nuke/Internal/Graphics.swift:115-127, `byAddingRoundedCorners` adds the rounded-rect path and clips to it. It then strokes the same path with `ctx.setLineWidth(border.width)`. Core Graphics centres a stroke on its path, so the outer half lands outside the clip and is lost. `byDrawingInCircle` calls the same function, so `ImageProcessors.Circle(border:)` has the same problem as `ImageProcessors.RoundedCorners(radius:unit:border:)`. Both are public.

**Checked without touching the repo.** I wrote a standalone CoreGraphics script in the scratchpad (scratchpad/borderchk/chk.swift and chk2.swift) that copies the algorithm:
- A 6 px border fills only 3 rows with the border colour. That matches the claim.
- 2 px gives 1 row and 4 px gives 2 rows.
- 1 px is worse than half-width. It gives one antialiased row half blended with the image (R130/B126 over blue), not a solid line. So `Border(color:width:1, unit:.pixels)`, or the 1 pt default on a 1x Mac screen, produces a muddy line.
- Moving the stroke inward by width/2 gives exactly the requested number of solid rows.

**The reference images match the bug, but don't show it was intended.** I measured Tests/Resources/Snapshots/s-rounded-corners-border.png and s-circle-border.png. Both show about 2 px of red for a requested 4 px. They look like output captured from the current code, and the tests that use them (`thatBorderIsAdded` in CircleTests and RoundedCornersTests) are `.disabled()`.

**Intent.** Nothing documents or intends half-width:
- `Border.width` is documented as "Border width."
- `description` and identifiers print "width: N pixels".
- The `- important:` note on `Border` only covers matching the image size to the view and preferring layer borders. It says nothing about the width.
- The history is commit c96a3ba1 / PR #327 (2019), titled "RoundedCorners and Circle image processor Border width". Its whole aim was to make the stroke respect `border.width`, since it had always been 1. The clip-then-stroke pattern came from the earlier `UIBezierPath` code, and nobody discussed the halving.
- CHANGELOG and the docc pages don't mention it, and I found no GitHub issue about it.
- A reasonable user would compare with `CALayer.borderWidth`, which draws the full width inside the bounds.

**Not a test artifact.** The repro goes through the public `ImageProcessors.RoundedCorners(...).process`, and the geometry is plain Core Graphics behaviour applied to Nuke's own drawing order. The existing `GraphicsTests.addingRoundedCornersWithBorderDrawsTheBorder` only samples y: 1, which falls inside the surviving half, so it misses this.

**Impact: low.** It's cosmetic, and there are workarounds: double the width, or use a layer border as the docs already recommend. A fix will double the visible border for every existing user, so it needs a CHANGELOG line and new reference snapshots.

**Suggested fix:**

In `byAddingRoundedCorners` (Sources/Nuke/Internal/Graphics.swift:123-127), keep the clip and double the stroke width, so the half that stays inside the clip is the full requested width. The outer edge then still matches the clip exactly, and the inner corner radius becomes radius − width. This also fixes Circle, which calls the same function:

    if let border {
        ctx.setStrokeColor(border.color.cgColor)
        ctx.addPath(path)
        ctx.setLineWidth(border.width * 2) // the stroke is centered on the clipped path; only the inner half is visible
        ctx.strokePath()
    }

Another option is to stroke `CGPath(roundedRect: rect.insetBy(dx: w/2, dy: w/2), cornerWidth: max(0, radius - w/2), cornerHeight: max(0, radius - w/2), transform: nil)` with `setLineWidth(w)`.

To go with the fix:
- Regenerate s-circle-border.png and s-rounded-corners-border.png.
- Tighten `GraphicsTests.addingRoundedCornersWithBorderDrawsTheBorder` to check that rows 0..<6 are red and row 6 isn't. Add a 1 px case that checks the edge row is solid red rather than blended.
- Add a short CHANGELOG entry noting that borders are now drawn at the full requested width, previously half.


### D70. macOS: processors that keep the pixel size change the NSImage point size of high-DPI images

_Severity: low · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Internal/Graphics.swift:323`

**Repro:** [NukeTests/processing-graphics-encoding--macos-processing-changes-image-point-size.swift](NukeTests/processing-graphics-encoding--macos-processing-changes-image-point-size.swift)

**What:** `NSImage.make(cgImage:source:)` ignores `source` and returns NSImage(cgImage:size: .zero), one point per pixel. The UIKit version keeps `source.scale` and orientation. On macOS, ImageDecoders.Default decodes with NSImage(data:), which sizes an image by its DPI. A 144-DPI PNG or JPEG, which is what a Retina Mac writes for a screenshot, decodes to half its pixel size in points. After GaussianBlur, CoreImageFilter or RoundedCorners it displays twice as large as the unprocessed image.

**Expected:** A 40x40 px image with a 20x20 pt size (including one decoded from a 144-DPI PNG by ImageDecoders.Default) is still 20x20 pt after a blur, CoreImage filter or rounded corners.

**Actual:** 40x40 pt.

**Reproduction check:** All 4 cases failed in 3/3 iterations on macOS with `output.size → (40.0, 40.0)`: the 144-DPI PNG decoded by ImageDecoders.Default, then GaussianBlur, CoreImageFilter(CISepiaTone) and RoundedCorners applied to an NSImage of 40x40 px at 20x20 pt. The precondition that the decoded 144-DPI input is 20x20 pt passed. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-8.log

**Refutation attempt (failed):**

I could not refute this. It is a real defect with low impact. The mechanism is clear from the code and I reproduced it outside the test suite.

1. Sources/Nuke/Internal/Graphics.swift:323-325. `NSImage.make(cgImage:source:)` ignores `source` and returns `NSImage(cgImage:size: .zero)`, which is one point per pixel. The UIKit version keeps `source.scale` and orientation. The same code has been there since 9a0162fc in 2019 ("Make ImageProcessor.Resize available on macOS"), and that commit gives no reason for dropping the size. No doc, DocC page or CHANGELOG entry says that processed NSImages are resized to their pixel size.

2. A standalone check confirms the macOS decoder's input. `ImageDecoders.Default._decode` calls `NSImage(data:)`. That call sizes PNG, JPEG and HEIC by their DPI: a 40 px image at 144 DPI is 20 pt, and at 300 DPI it is 9.6 pt. A second check confirms the output. `NSImage(cgImage:size:20x20).cgImage` gives back the 40 px CGImage, and wrapping it with `size: .zero` gives 40x40 pt. So GaussianBlur, CoreImageFilter, RoundedCorners and Circle all return an image with a different point size than the one they were given. `isDecompressionEnabled = true` on macOS goes through the same `draw(inCanvasWithSize:)` → `make` path, so it has the same effect.

3. The strongest counter-argument is that Nuke on macOS generally uses 1 pt = 1 px. `Screen.scale` is 1, and progressive previews, thumbnails and `_make` all produce pixel-sized NSImages. On that reading, AppKit's DPI sizing in `NSImage(data:)` is the odd one out. But a recent commit, cb50b39a ("Size an AppKit frame in points, not pixels"), fixed this same kind of problem in NukeUI's AnimatedImagePlayer and added a test for it. Its comment says a pixel-sized NSImage "draws twice as large as it should wherever nothing rescales it". So the maintainer treats pixel-sized AppKit images as a bug.

4. The issue is not limited to images from the pipeline. `ImageProcessing.process(_:)` is public, and any NSImage whose point size differs from its pixel size hits it. Examples: a 144-DPI Retina screenshot, a 300-DPI photo, an asset-catalog image with an @2x representation, or an image from a custom decoder. The repro uses only public API plus the `Test` fixtures, and does not misuse anything.

Why the impact is low: the size only matters where the image is shown at its own size, such as an NSImageView sized by its intrinsic content size, `.scaleNone`, or a SwiftUI `Image` without `.resizable()`. LazyImage's default content is `.resizable().aspectRatio(contentMode: .fit)`, so point size doesn't matter there. It only affects macOS, and only images whose point size differs from their pixel size. Nothing crashes and the pixels are correct.

Relevant paths: /Users/kean/Developer/Nuke/Sources/Nuke/Internal/Graphics.swift (lines 323-325, and callers at 104, 132, 157), /Users/kean/Developer/Nuke/Sources/Nuke/Decoding/ImageDecoders+Default.swift (lines 201-213), /Users/kean/Developer/Nuke/Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift (lines 486-499, the precedent).

**Suggested fix:**

Keep the source's points-per-pixel ratio, which matches how UIKit keeps `source.scale`, instead of hard-coding `.zero`. Every caller already has the source CGImage, so it can be passed in to avoid a second `cgImage(forProposedRect:)` call:

```swift
static func make(cgImage: CGImage, source: NSImage, sourceCGImage: CGImage? = nil) -> NSImage {
    guard let src = sourceCGImage ?? source.cgImage, src.width > 0, src.height > 0,
          source.size.width > 0, source.size.height > 0 else {
        return NSImage(cgImage: cgImage, size: .zero)
    }
    let sx = source.size.width / CGFloat(src.width)
    let sy = source.size.height / CGFloat(src.height)
    return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) * sx,
                                                  height: CGFloat(cgImage.height) * sy))
}
```

With this change, processors that keep the pixel size also keep the point size, and Resize/Circle scale the point size by the same ratio as the pixels, as UIImage.scale does. 1x inputs, which are all the existing macOS test fixtures, are unaffected. A narrower alternative is to normalise `ImageDecoders.Default._decode` on macOS to pixel size, as previews and thumbnails already are. That removes the DPI-image case but does not fix user-supplied @2x NSImages.


### D71. Docs: Resize `crop` says it has no effect with .aspectFill, but it only works with .aspectFill

_Severity: low · user impact: low · public API: yes · known: defects.md #25 · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+Resize.swift:29`

**Repro:** [NukeTests/processing-graphics-encoding--resize-crop-doc-names-wrong-content-mode.swift](NukeTests/processing-graphics-encoding--resize-crop-doc-names-wrong-content-mode.swift)

**What:** The doc comments on Resize.init(size:…crop:…) ('Has no effect when `contentMode` is `.aspectFill`') and on ImageProcessing.resize(size:…) at ImageProcessors.swift:26 ('Does nothing with content mode .aspectFill') name the wrong content mode. The code (`if crop && contentMode == .aspectFill`) does the opposite, and that is the correct behavior: crop only makes sense with aspectFill. The existing test thatImageIsntCroppedWithAspectFitMode pins it. The repro asserts the documented behavior and fails. The fix belongs in the two doc comments, not the code.

**Expected:** Per the docs, crop changes nothing with .aspectFill.

**Actual:** A 640x480 image is 400x400 with crop: true and 533x400 without (the docs are wrong).

**Reproduction check:** In 3/3 iterations `lhs.sizeInPixels == rhs.sizeInPixels` was false: 400x400 with crop: true and 533x400 with crop: false under .aspectFill. This contradicts the doc comment's "Has no effect when contentMode is .aspectFill". Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-9.log

**Refutation attempt (failed):**

This is a real bug, but only in the documentation. The code has been right all along. Two public doc comments say the opposite of what the code does:

- Sources/Nuke/Processing/ImageProcessors+Resize.swift:28-29 says: "crop: If `true`, crops the image to exactly match the target size. Has no effect when `contentMode` is `.aspectFill`."
- Sources/Nuke/Processing/ImageProcessors.swift:25-26 says: "Does nothing with content mode .aspectFill."

The code in `process(_:)` is `if crop && contentMode == .aspectFill { byResizingAndCropping } else { byResizing }`. So `crop` only works with `.aspectFill` and is ignored with `.aspectFit`.

**Tests agree with the code, not the docs.** In Tests/NukeTests/ImageProcessorsTests/ResizeTests.swift:
- `thatImageIsCropped` uses the default content mode, `.aspectFill`, with `crop: true` and expects 400x400. That already contradicts the docs.
- `thatImageIsntCroppedWithAspectFitMode` pins that `crop` does nothing with `.aspectFit`.

**History shows a typo, not a design change.** The wrong sentence first appeared in commit c1c32ee1 ("Fix an issue with ImageProcessors.Resize String identifier being equal with different content modes"). The same commit fixed a copy-paste bug where `.aspectFit` printed as ".aspectFill". The code at that commit already had `if crop && contentMode == .aspectFill`, so the doc was wrong from the day it was written; the author meant `.aspectFit`. Commit cc581e83 ("Update documentation", 2026-03) reworded the sentence and kept the error. No CHANGELOG entry or doc page says `crop` should be ignored with `.aspectFill`. Nuke.docc only links the symbol, so the misleading text shows up in the generated API reference.

**The repro is valid.** It uses the public initializer and public parameters. Nothing depends on @testable. The result doesn't come from ImageIO or the platform: `byResizingAndCropping` versus `byResizing` is Nuke's own branch.

**Impact is low.** No behavior is wrong. But `.aspectFill` is the default content mode, so a reader who trusts these docs would think `crop: true` does nothing with the defaults. They might drop it, or they might not understand why they get a 400x400 image instead of 533x400.

**Suggested fix:**

Fix only the doc comments and leave the code alone.
- In Sources/Nuke/Processing/ImageProcessors+Resize.swift:29, change "Has no effect when `contentMode` is `.aspectFill`." to "Has no effect when `contentMode` is `.aspectFit`."
- In Sources/Nuke/Processing/ImageProcessors.swift:25-26, change "Does nothing with content mode .aspectFill." to "Has no effect when `contentMode` is `.aspectFit`."

The existing tests `thatImageIsCropped` and `thatImageIsntCroppedWithAspectFitMode` already cover the behavior. Optionally, add a test that compares `crop: true` and `crop: false` with `.aspectFill` (400x400 vs 533x400) to show the flag matters there.


### D72. ImageProcessors.Anonymous.description is missing its closing parenthesis

_Severity: low · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+Anonymous.swift:29`

**Repro:** [NukeTests/processing-graphics-encoding--anonymous-description-unbalanced.swift](NukeTests/processing-graphics-encoding--anonymous-description-unbalanced.swift)

**What:** The format string is "AnonymousProcessor(identifier: \(identifier)", with no closing parenthesis. Every other processor's description is balanced, and descriptions appear in Composition.description and processing errors. This is cosmetic, and the description isn't part of a cache key, so fixing it invalidates nothing.

**Expected:** "AnonymousProcessor(identifier: sepia)"

**Actual:** "AnonymousProcessor(identifier: sepia"

**Reproduction check:** In 3/3 iterations `processor.description` was "AnonymousProcessor(identifier: sepia" and `Composition([processor]).description` was "Composition(processors: [AnonymousProcessor(identifier: sepia])". Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-10.log

**Refutation attempt (failed):**

I couldn't refute this. It's a real typo, though only cosmetic. Line 29 of /Users/kean/Developer/Nuke/Sources/Nuke/Processing/ImageProcessors+Anonymous.swift returns `"AnonymousProcessor(identifier: \(identifier)"`, which has no closing parenthesis. The typo goes back to commit bead228d ("Document the remaining image processors and add debug descriptions"), which added the description. Commit 505129dc later moved it into its own file unchanged.

Why it isn't intentional:
- Every other processor's description is balanced: Circle, GaussianBlur, Resize, RoundedCorners, Composition, and CoreImageFilter with its error cases.
- No test, DocC page or CHANGELOG entry mentions or asserts the current string. A grep for "AnonymousProcessor" across Sources, Tests, Documentation and CHANGELOG.md finds only the offending line.

Users can hit it through public API alone. `ImageProcessors.Anonymous(id:_:)` is public, and the description reaches users through:
- `ImagePipeline.Error.description` for `.processingFailed` ("Failed to process the image using processor \(processor).")
- `Composition.description`
- the processors field in `ImageTask.Metrics` formatting (ImageTask+MetricsFormat.swift:176)

The repro doesn't rely on anything test-only. `@testable` isn't needed, and nothing depends on ImageIO or the platform.

Nothing depends on the exact text. Cache keys use `identifier`/`hashableIdentifier`, and diagnostics summaries map `\.identifier`. Changing the description therefore invalidates no caches.

Impact is low: it only makes log and error output look wrong.

**Suggested fix:** In Sources/Nuke/Processing/ImageProcessors+Anonymous.swift:29, change the string to `"AnonymousProcessor(identifier: \(identifier))"`. Add a test asserting `ImageProcessors.Anonymous(id: "sepia") { $0 }.description == "AnonymousProcessor(identifier: sepia)"`, plus the Composition case from the repro.


### D73. Creating a pipeline resets prefersIncrementalDelivery on a DataLoader shared with another pipeline

_Severity: low · user impact: low · public API: yes · known: defects.md #60 · found by: request-model_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline.swift:95`

**Repro:** [NukeTests/request-model--shared-data-loader-incremental-delivery-clobbered.swift](NukeTests/request-model--shared-data-loader-incremental-delivery-clobbered.swift)

**What:** `ImagePipeline.init` writes `(configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery = configuration.isProgressiveDecodingEnabled`. `DataLoader` is a class, and copies of a configuration share it (the Configuration docs point out that copies share their class-typed members). So a second pipeline derived from the first one's configuration overwrites the shared loader's setting, and whichever pipeline was created last wins. The first pipeline's configuration still says progressive decoding is on, but `URLSession` stops delivering the body in pieces, so it stops producing progressive previews. The reverse also happens: a progressive pipeline turns incremental delivery on for another pipeline sharing its loader, or for a loader the app configured by hand.

**Expected:** `dataLoader.prefersIncrementalDelivery` stays `true` for the pipeline created with `isProgressiveDecodingEnabled = true`.

**Actual:** Creating `ImagePipeline(configuration:)` from a copy with `isProgressiveDecodingEnabled = false` sets it to `false` on the shared loader.

**Reproduction check:** Failed in all 3 iterations: `dataLoader.prefersIncrementalDelivery → false` after `ImagePipeline(configuration:)` was created from a copy with isProgressiveDecodingEnabled = false. The earlier check that it was `true` after the first pipeline passed, and `progressive.configuration.isProgressiveDecodingEnabled` is still true.

**Refutation attempt (failed):**

I could not refute this. I confirmed it by reading the code and did not run the repro test, because the mechanism is a single deterministic line.

1. **What the code does.** `ImagePipeline.init` in /Users/kean/Developer/Nuke/Sources/Nuke/Pipeline/ImagePipeline.swift (line 96 in the current tree) runs `(configuration.dataLoader as? DataLoader)?.prefersIncrementalDelivery = configuration.isProgressiveDecodingEnabled`. `DataLoader` is a class, and `Configuration.dataLoader` is an `any DataLoading` existential, so a copied configuration holds the same loader instance. The setter in /Users/kean/Developer/Nuke/Sources/Nuke/Loading/DataLoader.swift writes into a lock and has no guard. `DataLoader.loadData` copies the flag onto each new `URLSessionDataTask`. So the last pipeline created decides the flag for every pipeline that shares the loader.

2. **Effect on URLSession.** The Foundation header (NSURLSession.h) says that when `prefersIncrementalDelivery` is `false` "the task only delivers data when complete". A progressive pipeline whose loader was reset this way gets one chunk at the end. `TaskFetchOriginalImage` then never gets partial data to decode, so no previews are produced, even though the pipeline's configuration still says progressive decoding is on.

3. **Intent and history.** The line comes from commit 184d3fc9 ("Disable incremnetal delivery by default", Nuke 11.1.1). The CHANGELOG entry for it says: "When progressive decoding is disabled, it now uses `prefersIncrementalDelivery` on `URLSessionTask`, slightly increasing the performance". The goal was only to align a pipeline's own loader with its own setting. Nothing documents that creating a pipeline changes a shared loader, and the `DataLoader.prefersIncrementalDelivery` doc says only "By default, `false`." PR #928 ("Synchronize access to DataLoader.prefersIncrementalDelivery") names this exact scenario: "simply creating a second pipeline that shares a `DataLoader` with a running one is enough to trip the thread sanitizer." It fixed the data race but left the setting-overwrite problem in place. So the maintainers treat sharing a `DataLoader` across pipelines as a real, supported case.

4. **Docs.** The `Configuration` doc and `ImagePipelineConfiguration-Extension.md` warn only that copies share `TaskQueue`s, and that warning is about the user mutating a shared queue themselves. Here the user changes only a value-type `Bool` on their own copy, which they would reasonably expect not to affect the original pipeline. The docs promise nothing that makes this expected.

5. **Repro validity.** The repro uses only public API: `DataLoader()`, `ImagePipeline { }`, `pipeline.configuration`, `ImagePipeline(configuration:)` and `prefersIncrementalDelivery`. It needs no `@testable` access and does not depend on mocks or timing. A realistic trigger: `ImagePipeline.shared = ImagePipeline { $0.isProgressiveDecodingEnabled = true }`, then `var c = ImagePipeline.shared.configuration; c.isProgressiveDecodingEnabled = false; let thumbs = ImagePipeline(configuration: c)`. After that, the shared pipeline silently stops producing progressive previews.

**Impact is low.** Final images still load correctly. The loss is progressive previews, and the effect depends on the order in which pipelines are created, which makes it hard to diagnose. The reverse direction, where a non-progressive pipeline or a hand-configured loader gets incremental delivery turned on, costs only a small amount of performance. The trigger needs two pipelines that share one `DataLoader` and have different progressive settings. That is uncommon, because `Configuration()` and the predefined configurations each create their own loader.

**Suggested fix:**

Make the flag a per-request decision instead of writing to the shared loader in init.

1. Remove the `prefersIncrementalDelivery` write from `ImagePipeline.init`.
2. Give `DataLoader`'s private `loadData(with:collectsMetrics:...)` an internal parameter such as `prefersIncrementalDelivery: Bool` and set the task with `task.prefersIncrementalDelivery = prefersIncrementalDelivery || self.prefersIncrementalDelivery`. The loader's own public setting then acts as a floor: whatever the app set by hand still applies.
3. In `TaskFetchOriginalData.loadData(with:dataLoader:)`, when `dataLoader as? DataLoader` succeeds, which is already checked there for diagnostics metrics, call that internal overload with `pipeline.configuration.isProgressiveDecodingEnabled`.

The public `DataLoading` protocol does not change.

A smaller alternative is to write the flag in init only to turn it on: `if configuration.isProgressiveDecodingEnabled { loader.prefersIncrementalDelivery = true }`. It is never reset to `false`, so a non-progressive pipeline can no longer disable previews on a progressive one. The cost is that a non-progressive pipeline sharing the loader keeps the small performance overhead of incremental delivery.

Either way, add a regression test: two pipelines share a `DataLoader`, one with progressive decoding on and one off, and the tasks each pipeline creates must carry that pipeline's own setting.


## Unverified (12)

### D74. Progressive/thumbnail previews ignore EXIF orientation; final image honors it

_Severity: medium · known: defects.md #23 · found by: decoding_

**Where:** `Sources/Nuke/Decoding/ImageDecoders+Default.swift:209`

**Repro:** [NukeTests/decoding--preview-ignores-exif-orientation.swift](NukeTests/decoding--preview-ignores-exif-orientation.swift)

**What:** Every preview built from partially downloaded data goes through `_make(_:scale:)`. That covers `.incremental`, the `.thumbnail` policy and the thumbnail fallback. It wraps the CGImage with `orientation: .up` on UIKit, or as-is on AppKit, so the EXIF orientation is dropped. The final image comes from UIImage(data:) / NSImage(data:), which apply it. A rotated progressive JPEG gets the `.incremental` policy by default, so with progressive decoding on its previews lie on their side and the image snaps a quarter turn when the download finishes. Before ed89f39c (the switch to CGImageSourceCreateIncremental), previews were decoded with UIImage(data:scale:) and kept the orientation.

**Expected:** Preview image.size equals final image.size (300×400 for a 400×300 JPEG with orientation 6)

**Actual:** Preview image.size is 400×300 while the final image is 300×400 (macOS and iOS; both the incremental and the .thumbnail policy)


### D75. AssetType sniffs real M4A audio and Canon CR3 as .mp4 via compatible brands

_Severity: medium · found by: decoding_

**Where:** `Sources/Nuke/Decoding/AssetType.swift:174`

**Repro:** [NukeTests/decoding--m4a-and-cr3-sniffed-as-mp4.swift](NukeTests/decoding--m4a-and-cr3-sniffed-as-mp4.swift)

**What:** Since 9b1973f8 the sniffer walks every compatible brand and returns the first known one. Real M4A files (ftyp as written by Apple's afconvert: `M4A ` + `M4A mp42 isom`) and CR3 (`crx ` + `crx isom`) therefore sniff as .mp4. This contradicts the doc comment on `_makeISOBaseMedia(_:)`, which says MPEG-4 audio returns nil, and supported-image-formats.md, which says CR3 sniffs as nil. `AssetType.isVideo` is then true, so a registered `ImageDecoders.Video` claims these files ahead of the Default decoder and returns an empty placeholder instead of letting Image I/O decode the CR3. The existing test only checks a bare `M4A ` major brand with no compatible brands, which no encoder writes.

**Expected:** AssetType(data) == nil for the M4A and CR3 ftyp headers

**Actual:** AssetType(data) == .mp4 (public.mpeg-4) for both


### D76. A huge declared ftyp size makes every AssetType sniff walk the whole file (pipeline-actor stall)

_Severity: medium · found by: decoding_

**Where:** `Sources/Nuke/Decoding/AssetType.swift:189`

**Repro:** [NukeTests/decoding--ftyp-size-walks-whole-file.swift](NukeTests/decoding--ftyp-size-walks-whole-file.swift)

**What:** `_brands(in:)` reads one brand every 4 bytes, allocating a String each time, up to min(declared size, data.count), and `_makeISOBaseMedia` only stops at a known brand. A file with `ftyp` at offset 4, a declared size of 0xFFFFFFFF and no known brand makes each `AssetType(data)` O(file size): 2.6 s for 32 MB in a Debug build on macOS, 4.6 s on the iOS simulator. The sniff runs on the pipeline actor: `Default.decode`, since Default is synchronous without a thumbnail, and also `PreviewPolicy.default(for:)`, `ImageDecoders.Video.init?(context:)`, and every chunk when progressive decoding is on. One crafted image therefore stalls all image loading for seconds each time it's loaded. The repro includes a deterministic check: a brand 1 MB into the data is still read.

**Expected:** The sniff reads a bounded header: it finishes in well under 100 ms, and a brand 1 MB into the file is not read

**Actual:** 2.56 s for 32 MB, and AssetType returns .heic from a brand 1,000,016 bytes in


### D77. Video preview ignores the track's preferred transform, so portrait videos get sideways previews

_Severity: medium · found by: video-extensions_

**Where:** `Sources/NukeVideo/ImageDecoders+Video.swift:75`

**Repro:** [NukeVideoTests/video-extensions--rotated-video-preview-sideways.swift](NukeVideoTests/video-extensions--rotated-video-preview-sideways.swift)

**What:** `makePreview(for:type:)` creates an `AVAssetImageGenerator` without setting `appliesPreferredTrackTransform = true`, which defaults to false. The frame is therefore returned in its encoded orientation, not the one AVPlayerLayer and VideoPlayerView display. Phones record portrait video as landscape pixels with a 90° transform, so the preview shown in place of the video (by `decode` and `decodePartiallyDownloadedData`) comes out rotated 90° from the video that replaces it once playback starts. I checked in a standalone script: the same generator gives 32x16 without the flag and 16x32 with it.

**Expected:** A video encoded 32x16 with a 90° preferred transform, which AVFoundation displays as 16x32, gets a 16x32 preview.

**Actual:** The preview is 32x16 (sideways), both from `decode(_:)` and from `decodePartiallyDownloadedData(_:)`.


### D78. Decoding a video from a Data slice crashes the process in the resource loader

_Severity: medium · found by: video-extensions_

**Where:** `Sources/NukeVideo/AVDataAsset.swift:78`

**Repro:** [NukeVideoTests/video-extensions--data-slice-crashes-resource-loader.swift](NukeVideoTests/video-extensions--data-slice-crashes-resource-loader.swift)

**What:**

The resource loader subscripts `data` with AVFoundation's requested offsets as if they were indices (`data[requestedOffset...]` at line 75 and `data[requestedOffset..<requestedOffset+requestedLength]` at line 78). Offsets count from the start of the resource, but the indices of a Data slice start at `startIndex`. The first request (offset 0) is therefore out of bounds and Data traps on a global queue; the crash report shows EXC_BREAKPOINT in `Data.subscript.getter`, called from `DataAssetResourceLoader.resourceLoader(_:shouldWaitForLoadingOfRequestedResource:)` at AVDataAsset.swift:78.

This is reachable through public pipeline API. `ImageRequest(id:data:)` passes the returned Data to the decoder unchanged, and TaskFetchOriginalData does the same with the first chunk from a custom DataLoading (`data = chunk`). `AssetType(_:)` and `ImageDecoders.Default` handle slices; only the video path crashes. The repro uses exit tests so the crash doesn't take down the test runner.

**Expected:** A video passed as `buffer[100...]` decodes the same way as the same bytes in a fresh Data (a 32x16 first frame plus the asset), both from `ImageDecoders.Video.decode` and from `ImagePipeline` with `ImageRequest(id:data:)`.

**Actual:** The process dies with SIGTRAP. The exit tests report: expected exit status .success, but .signal(SIGTRAP) was reported instead.


### D79. A thumbnail request gets full-size progressive previews

_Severity: medium · found by: decoding_

**Where:** `Sources/Nuke/Decoding/ImageDecoders+Default.swift:100`

**Repro:** [NukeTests/decoding--review-thumbnail-request-previews-full-size.swift](NukeTests/decoding--review-thumbnail-request-previews-full-size.swift)

**What:** `decodePartiallyDownloadedData(_:)` never looks at `request.thumbnail`, so with the default `.incremental` preview policy for progressive JPEGs every preview of a thumbnail request is decoded at the full size of the image (450x300 previews for a `maxPixelSize: 64` request whose final image is 64x43). The previews can land in the memory cache under the thumbnail key.

**Expected:** Previews of a thumbnail request are no larger than the requested thumbnail (or there are none).

**Actual:** Previews are decoded at the full image size.


### D80. A request created after invalidate() returned can still succeed

_Severity: low · found by: concurrency-stress_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline.swift:131`

**Repro:** [NukeThreadSafetyTests/concurrency-stress--invalidate-unordered-with-new-requests.swift](NukeThreadSafetyTests/concurrency-stress--invalidate-unordered-with-new-requests.swift)

**What:**

`invalidate()` sets `isInvalidated` in an unstructured hop, and each new task is started by a hop of its own (`makeStartedImageTask`, line 184). When invalidate() is called from a lower-QoS thread than the one that creates the next task, the task's start overtakes the invalidation. `startImageTask` then sees `isInvalidated == false` (line 205) and runs the request. A memory-cache hit completes it successfully. A request that must load data is cancelled a moment later instead, so it fails with `.cancelled` rather than `.pipelineInvalidated`.

The doc comment of invalidate() says: "Any new requests will immediately fail with pipelineInvalidated error." The repro holds the actor briefly so both hops queue up first. The same sequence with both calls at the same QoS fails with `.pipelineInvalidated` as documented (control case in the repro).

**Expected:** `invalidate()` from a .background thread, then (after it returned) `imageTask(with:)` from a .userInitiated thread for an image in the memory cache: the task fails with .pipelineInvalidated.

**Actual:** The task succeeds with the cached image.


### D81. Custom AnimatedImageSource accepts an infinite/overflowing canvas; bytesPerFrame traps

_Severity: low · found by: decoding_

**Where:** `Sources/Nuke/Decoding/AnimatedImageSource.swift:95`

**Repro:** [NukeTests/decoding--custom-animation-canvas-overflow-traps.swift](NukeTests/decoding--custom-animation-canvas-overflow-traps.swift)

**What:** `init(data:delays:loopCount:size:makeFrameDecoder:)` only checks `size.width > 0, size.height > 0`, so it accepts an infinite canvas or one like 0xFFFFFFFF × 0xFFFFFFFF parsed from a damaged header. `bytesPerFrame` (`Int(size.width) * Int(size.height) * 4`) then traps, either on the Int conversion or on the multiplication overflow. NukeUI's `AnimatedImageFrameStore.bytesPerFrame(for:maxPixelSize:)` reads it as soon as a view plays the animation, so a custom decoder that passes header dimensions straight through crashes the app on a hostile file.

**Expected:** No trap: either the initializer returns nil for a canvas that can't be played, as it does for an empty one, or bytesPerFrame saturates

**Actual:** The exit test child process dies with SIGTRAP for both the 4294967295² canvas and the infinite-width canvas


### D82. A delay of exactly minimumDelay (11 ms) is replaced with 0.1 s because of Float precision

_Severity: low · found by: decoding_

**Where:** `Sources/Nuke/Decoding/AnimatedImageFormat.swift:68`

**Repro:** [NukeTests/decoding--minimum-delay-float-precision.swift](NukeTests/decoding--minimum-delay-float-precision.swift)

**What:** `minimumDelay` is documented as 'Delays below this value are replaced': 0.011. Image I/O reports APNG, WebP and HEICS delays as 32-bit floats, so 11 ms comes back as Float(0.011) = 0.010999999940395355, which compares below the Double threshold and is replaced by `defaultDelay`. An animation that asks for 11 ms frames plays about 9× slower. WebKit, which the threshold comes from, compares in float (`value < 0.011f`) and keeps the delay.

**Expected:** An APNG written with delays [0.011, 0.011] reports delays of about 0.011 each

**Actual:** delays == [0.1, 0.1]


### D83. The GIF preview isn't numbered, and the final image doesn't count it (docs vs. behavior)

_Severity: low · found by: decoding_

**Where:** `Sources/Nuke/Decoding/ImageDecoders+Default.swift:116`

**Repro:** [NukeTests/decoding--gif-preview-not-numbered.swift](NukeTests/decoding--gif-preview-not-numbered.swift)

**What:** The Default decoder docs say 'The previews are numbered in the order they are produced and the index is available in scanNumberKey'. The scanNumberKey docs say the default decoder also attaches it to the final image 'where it is the total number of previews that preceded it'. The GIF branch returns its preview with `userInfo: [:]` and never increments `numberOfScans`. As a result the GIF preview has no scanNumberKey, and neither does the final image even though a preview preceded it.

**Expected:** preview.userInfo[.scanNumberKey] == 1 and final.userInfo[.scanNumberKey] == 1

**Actual:** Both are nil


### D84. ImageDecoders.Video.decode crashes on 0 or 1 bytes of data

_Severity: low · found by: video-extensions_

**Where:** `Sources/NukeVideo/AVDataAsset.swift:78`

**Repro:** [NukeVideoTests/video-extensions--short-data-crashes-resource-loader.swift](NukeVideoTests/video-extensions--short-data-crashes-resource-loader.swift)

**What:**

The resource loader answers a byte-range request with `data[offset..<offset+length]` without clamping it to the data it has. AVFoundation's first loading request asks for the content information plus the first 2 bytes, whatever content length the delegate reports in the same call. With fewer than 2 bytes the range is out of bounds and Data traps.

`decode(_:)` is public and takes its data independently of the context the decoder was created from, so `decode(Data())` or `decode(Data([0]))` brings down the process. With 2 to 16 bytes it returns an empty image instead, which is what callers would expect for data with no frames. The pipeline always passes 12 or more bytes, so only direct callers are affected. This is the same site as the slice crash but a separate missing check (range clamping rather than index base).

**Expected:** `decode(Data())` and `decode(Data([0]))` either return a container with an empty image, as they do for any data without a decodable frame, or throw.

**Actual:** The process crashes with SIGTRAP. The exit tests report .signal(SIGTRAP) for the 0- and 1-byte cases; the 2-byte case passes.


### D85. ImageDecoders.Video ignores the .disabled preview policy and still produces video previews

_Severity: low · found by: video-extensions_

**Where:** `Sources/NukeVideo/ImageDecoders+Video.swift:45`

**Repro:** [NukeVideoTests/video-extensions--disabled-preview-policy-ignored.swift](NukeVideoTests/video-extensions--disabled-preview-policy-ignored.swift)

**What:**

`init?(context:)` never reads `context.previewPolicy`, and `decodePartiallyDownloadedData` always runs AVAssetImageGenerator on the partial data. The documented contract says otherwise:
- `PreviewPolicy.disabled`: "No previews are generated for partially downloaded data".
- The ImagePipeline docs: ".disabled — No previews".
- `PreviewPolicy.default(for:)` returns .disabled for MP4.
- The formats table in supported-image-formats.md lists "–" under Previews for MP4/M4V/MOV.

The CHANGELOG fixed the same defect in `ImageDecoders.Default` for GIFs (#892). As a result, with progressive decoding on, a user can't turn off video previews, even with a delegate that returns .disabled for everything. For a video whose movie header is at the end, the generator runs, and fails, on every chunk until the download completes. The repro opens the gated data loader once the decoder has seen the partial data (or declined it), so it stays deterministic whichever way the bug is fixed.

**Expected:** A decoder created with `previewPolicy: .disabled` returns nil from `decodePartiallyDownloadedData`. The pipeline delivers no `.preview` event for a progressive video download, either with the default delegate (which resolves MP4 to .disabled) or with a delegate that returns .disabled.

**Actual:** The decoder returns a first-frame preview, and the pipeline delivers one `.preview` event in both configurations (3 failed expectations).


## Rejected (17)

### D86. A new player falls in behind a player that has finished, so a play-once animation never plays in a second view

_Severity: medium · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageFrameStore.swift:188`

**Repro:** [NukeUITests/animated-frames-view--review-joins-finished-player.swift](NukeUITests/animated-frames-view--review-joins-finished-player.swift)

**What:** leadingIndex() returns the playhead of the first member with keepsFullBuffer == true. finish() sets isPlaying to false and pauses the clock, but it leaves keepsFullBuffer set. So a player that has played all its loops and stopped on its last frame still leads every player that joins its store. A joining player (isSynchronizationEnabled is on by default) therefore starts on the last frame with completedLoopCount 0. On its first tick nextFrameIndex is nil, so it finishes after showing a single frame. The writer's joining-player bug makes it worse: that frame is never even displayed. An AnimatedImageView showing it keeps its poster, or stays blank, and never animates. The leadingIndex() doc says it returns nil 'when nothing else is playing this animation', and the sharing tests say a player that isn't playing is 'not a position worth falling in behind'. Realistic case: a reaction or sticker GIF with loop count 1 that has finished in one cell and then appears in another cell or screen.

**Expected:** A finished (not playing) player is not a leader. The second player starts at frame 0 and plays the animation through its loops.

**Actual:** second.currentFrameIndex == 3 (of 4). After one tick of 0.1 s, second.isFinished == true and second.isPlaying == false. Confirmed on the iOS simulator.

**Reproduction check:** macOS, 3 of 3 iterations: second.currentFrameIndex → 3 (expected 0). After one 0.1 s tick, second.isFinished → true and second.isPlaying → false. The first player's preconditions passed (finished, not playing, on frame 3). Same on the iOS simulator.

**Why it was rejected:**

The code does what the report says. finish() in Sources/NukeUI/AnimatedImages/AnimatedImagePlayer.swift sets isPlaying to false but leaves keepsFullBuffer true. AnimatedImageFrameStore.leadingIndex() (line 187) returns the playhead of the first member with keepsFullBuffer set. So when a finished play-once player is still on screen, a new player joins on the last frame with completedLoopCount 0 and finishes on its first tick.

That outcome is what the documented synchronization model asks for, not a departure from it:
- The public docs (NukeUI.docc/AnimatedImages.md, Sharing) give the goal as "the copies on a screen sit on the same frame".
- The Options.isSynchronizationEnabled doc says the player "starts on the frame the other players of the same animation are showing". A finished player is showing its last frame.
- The same doc, the commit that added it (0a2ab073) and the demo text all name browser parity as the reason: "the way a browser plays every copy of one image". In WebKit, all copies of one image share one animation state, so an img added after a play-once GIF has finished shows the last frame and does not replay. Nuke's result here, both copies on the last frame, matches that.
- The case is the natural limit of a documented trade-off. A copy that joins a play-once animation mid-play plays only the rest of it. Joining at the last frame of a player that is still playing gives exactly the same result as joining a finished one.
- The doc names the escape hatch for this very case: "Set it to false for a player that should always begin at the beginning – an animation played once as a transition, say."
- The repro's "expected" (frame 0, full playback) comes from the loose wording "whatever is already playing" in the NukeUI doc and in the internal leadingIndex() comment. The rest of the contract and the browser model point the other way. The cited sharing test only covers a player that has not started; it says nothing about finished players.

Two narrower problems are real but are not this report:
- The joining player never displays the frame it starts on, so an AnimatedImageView keeps its poster (frame 0) instead of showing the last frame. That is the writer's separate joining-player bug, and it is what makes the result look wrong.
- Loop counts are not synchronized. With a loop count of 2 or more, the joiner plays more loops after the leader has finished.

Impact is low. It needs a play-once animation, which means a GIF without a NETSCAPE block or an app-set .finite repeatCount. It needs the same AnimatedImageSource at the same size key. And it needs the finished copy still in a window and visible, because a copy that moves off screen sets keepsFullBuffer to false and stops leading. The visible result, a static copy of a finished play-once animation, is also what a browser shows.


### D87. CoreImageFilter crashes the app on an unknown parameter key (NSUnknownKeyException)

_Severity: medium · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+CoreImage.swift:101`

**Repro:** [NukeTests/processing-graphics-encoding--coreimage-unknown-parameter-key-crashes.swift](NukeTests/processing-graphics-encoding--coreimage-unknown-parameter-key-crashes.swift)

**What:** `applyFilter(named:parameters:to:)` hands the parameters to `CIFilter(name:parameters:)`. That sets each one with KVC and raises an Objective-C NSUnknownKeyException for a key the filter doesn't have. Swift can't catch it, so the process terminates on the processing queue. A typo in a key, or a key that only exists on newer OS versions, crashes a production app. The processor documents `failedToCreateFilter(name:parameters:)` for this case. A fix could check the keys against `filter.inputKeys` first. The repro crashes the test runner rather than recording a failure.

**Expected:** The processor throws ImageProcessors.CoreImageFilter.Error.failedToCreateFilter, and the request fails with processingFailed.

**Actual:** *** Terminating app due to uncaught exception 'NSUnknownKeyException', reason: '[<CISepiaTone> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key inputIntensty.'

**Reproduction check:** The test process crashed: "*** Terminating app due to uncaught exception 'NSUnknownKeyException', reason: '[<CISepiaTone 0x...> setValue:forUndefinedKey:]: this class is not key value coding-compliant for the key inputIntensty.'" Backtrace: +[CIFilter(CIFilterRegistry) filterWithName:withInputParameters:] <- CIFilter.init(name:parameters:) <- ImageProcessors.CoreImageFilter.applyFilter(named:parameters:to:) <- _process <- process(_:context:) <- the test. xcodebuild printed "Restarting after unexpected exit, crash..." and listed the test under Failing tests (TEST FAILED). Because the crash kills the runner, only the first of the 3 iterations actually ran. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-2.log

**Why it was rejected:**

The crash does happen. A standalone probe (scratchpad/ci_probe.swift) that calls `CIFilter(name: "CISepiaTone", parameters: ["inputIntensty": 0.5])` with no Nuke involved terminates with the same NSUnknownKeyException, thrown from -[CIFilter setValue:forUndefinedKey:] inside +[CIFilter filterWithName:withInputParameters:]. So the crash comes from Core Image's KVC behavior, not from Nuke. `CoreImageFilter(name:parameters:identifier:)` is a thin wrapper that passes the parameters to that Apple initializer, and anyone calling Core Image directly gets the same crash. The same is true of the processor's other public path, `init(_ filter: CIFilter, identifier:)`, where the user sets the keys themselves.

Nuke never promises to validate keys. `failedToCreateFilter` was added in commit 139d40e7 ("ImageProcessing now supports throwing") as the `else` branch of `guard let filter = CIFilter(name:parameters:)`. It maps the initializer's nil return, which happens for an unknown filter name and is covered by the existing test with name "yo". Its doc comment ("Failed to create a CIFilter with the given name and parameters") describes that nil case, not key validation. No doc, CHANGELOG entry or test says bad keys are recoverable.

A misspelled key is a programmer error. It crashes deterministically on the first processed image, so it shows up at once in development rather than failing silently in production. The "key only exists on newer OS" case is ordinary platform-availability hygiene: a direct CIFilter caller needs `#available` for it too.

The suggested fix, rejecting keys not in `filter.inputKeys`, is also not clearly correct. CIFilter accepts valid KVC keys that aren't listed in `inputKeys`, such as `name`, so the check could reject parameters that work today. At most this is a hardening request, not a defect.


### D88. A player shared by two views: the first view freezes for good once the second is handed the player

_Severity: low · user impact: low · public API: yes · found by: animated-frames-view_

**Where:** `Sources/NukeUI/AnimatedImages/AnimatedImageView.swift:74`

**Repro:** [NukeUITests/animated-frames-view--player-shared-by-two-views-freezes-one.swift](NukeUITests/animated-frames-view--player-shared-by-two-views-freezes-one.swift)

**What:** AnimatedImageView.player.didSet installs the view in the player's single onFrameForDisplay slot, silently replacing the view that had it. The displaced view keeps holding the player, and re-assigning the same player does nothing (guard oldValue !== player), so it never gets frames again. After the second view is deallocated its [weak self] handler becomes a no-op, and the first view stays frozen while the player keeps playing. Example: a model-owned player shown with AnimatedImage(player:) in both a list row and a detail screen. Popping the detail leaves the row stuck. The docs present the player as the way to control playback from outside and do not limit a player to one view.

**Expected:** A view whose player is p shows p's frames: after player.seek(toFrame: 1), row.image === player.image.

**Actual:** row.image is still frame 0 while player.image is frame 1.

**Reproduction check:** macOS, 3 of 3 iterations: after row.player = p, detail.player = p, detail = nil, row.player = p and p.seek(toFrame: 1), `row.image === player.image` failed. The row still showed the frame-0 NSImage while player.image (non-nil) was frame 1. Same on the iOS simulator.

**Why it was rejected:**

The mechanism is real, and the repro would fail as described. AnimatedImageView.player.didSet (Sources/NukeUI/AnimatedImages/AnimatedImageView.swift:58-80) writes the view's handler into the player's single internal `onFrameForDisplay` slot. `guard oldValue !== player` means re-assigning the same player never puts it back, and nothing clears the slot when the second view deallocates. After `detail.player = p; detail = nil`, `seek(toFrame:)` calls `display` and goes to a dead `[weak self]` handler, so the row keeps frame 0.

It is still not a defect in a supported use. The design gives one player to one view at a time:

1. **The view runs the player.** The `player` doc says "the view starts and stops it as it moves in and out of a window, exactly as it does its own." `updatePlaybackState()` pauses the player, and clears `keepsFullBuffer`, whenever that view leaves the window or is hidden. With two views on one player, each view's visibility pauses or plays the one playhead the other view shows. Follow the list/detail case the bug describes through a UINavigationController or NavigationStack push:
   - The detail is added and plays.
   - The row's view then leaves the window and pauses the player, so the detail freezes too.
   - On pop, the detail leaves last and pauses the player again. The row sits in the window with a paused player.

   So the "row frozen while the player keeps playing" story does not hold in the real flow. A multicast frame handler alone would not make sharing work, because the play/pause conflict is in the design, not in the handler slot.
2. **The docs name a different way to show one animation in several places.** They describe separate players that share one set of decoded frames. The frame pool and store are built for this, `sharingPlayerCount` reports it, and `isSynchronizationEnabled` makes new players "fall in behind whatever is already playing." Nothing needs a shared player.
3. **Nothing promises sharing.** No doc, test or CHANGELOG entry (Nuke 14, unreleased, PR #958) says a player can drive two views. "Both views take one" means AnimatedImageView and AnimatedImage each accept a player. Commit 76e6b3c4 added `onFrameForDisplay` only to keep the views from overwriting the user's `onFrame`. It treats the view as the player's one display consumer.
4. **The repro builds its own scenario.** It uses `@testable waitUntilFull()` and assigns the same player to a second view by hand. The claimed row-freeze sequence only follows if you assume the playback conflict from point 1 does not happen.

**What could hit users:** a user coming from AVPlayer, which can feed several AVPlayerLayers, might share a model-owned player between a list row and a detail screen and get a silently frozen view. That is a documentation gap with low impact, not a code bug that would get its own fix.


### D89. DataCache(name: "") takes over the app's Caches directory itself

_Severity: low · user impact: low · public API: yes · found by: data-cache_

**Where:** `Sources/Nuke/Caching/DataCache.swift:151`

**Repro:** [NukeTests/data-cache--empty-name-uses-caches-root.swift](NukeTests/data-cache--empty-name-uses-caches-root.swift)

**What:**

`init(name:)` builds its path with `URL.cachesDirectory.appendingPathComponent(name, isDirectory: true)`. For an empty name this returns the Caches directory unchanged ("." and ".." resolve to it or to Library). The docs say "The cache creates a directory with the given name in a .cachesDirectory", but with an empty name it creates none and treats everything in Caches as its own:
- `removeAll()` calls `removeItem(at: path)` at line 517, deleting the entire Caches directory, including URLCache storage and other libraries' caches.
- The LRU sweep ranks and deletes top-level items in Caches once the files there exceed `sizeLimit`.
- `totalCount` counts unrelated directories as entries.

An empty name is easy to pass by accident, for example `Bundle.main.bundleIdentifier ?? ""`. The repro only builds the cache and checks its path; it never calls anything destructive and releases the cache before a sweep could run.

**Expected:** Init throws for a name that doesn't name a subfolder, or the cache gets a folder of its own.

**Actual:** Init succeeds and `cache.path` equals `URL.cachesDirectory`.

**Reproduction check:** Failed in all 3 iterations: `DataCache(name: "")` did not throw, and `cache.path.standardizedFileURL` was `file:///Users/kean/Library/Caches/`, equal to `URL.cachesDirectory`. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-cache-4.log

**Why it was rejected:**

The mechanics are accurate, but this is a caller passing a bad argument, not a defect in Nuke.

What I confirmed:
- I compiled a small Swift program in the scratchpad. `URL.cachesDirectory.appendingPathComponent("", isDirectory: true)` returns ~/Library/Caches unchanged. "." and "/" also resolve to Caches, and ".." resolves to ~/Library.
- `performRemoveAll` (DataCache.swift:516-519) runs `removeItem(at: path)` and then recreates the directory. `performSweep` and `totalCount` list the top level of `path`.
- So `DataCache(name: "")` does adopt the Caches directory, and the public `withDataCache(name: "")` does the same.

Why it is refuted:
1. **Nothing promises validation.** The doc says `name` is "The name of the directory in which the cache is stored", and the initializer "creates a directory with the given `name`". An empty string is not a directory name, so the argument breaks the documented meaning of the parameter. No doc, CHANGELOG entry or commit (history back to 806ed750 "Add experimental Disk Cache implementation") says the name is sanitized or that the cache always gets a subfolder of its own.
2. **Letting the caller pick the directory is the design.** The public `init(path:)` lets a caller point the cache at any directory, including `URL.cachesDirectory` itself, and the result is exactly the reported "takeover". `DataCache.path` is documented as "the directory managed by the cache". Picking a directory the cache can own is the caller's job, whichever initializer they use. `init(name:)` is a thin wrapper that joins a string to Caches, and it inherits Foundation's path rules for "", "." and "..".
3. **The claimed trigger is speculative.** Every example in the docs, README and CHANGELOG uses a fixed reverse-DNS literal ("com.myapp.datacache", "com.github.kean.Nuke.DataCache"), and the built-in default is a constant. Getting "" needs an explicit fallback like `Bundle.main.bundleIdentifier ?? ""`, which is an app-code choice that no documented flow suggests.
4. **The repro proves only that `path == cachesDirectory`.** It shows no data loss through any documented flow, and it confirms Foundation behavior rather than a broken Nuke invariant.

Note for balance: the result would be bad if someone hit it. `removeAll()` would wipe the app's Caches, and on unsandboxed macOS it would try to wipe the shared ~/Library/Caches. Kingfisher, for example, refuses an empty cache name. That makes this a reasonable hardening idea, but it is not a bug in behavior Nuke promises. It is reachable through public API, but only with a caller-supplied argument that is invalid by the parameter's own description, so the impact is low.


### D90. ResumableDataStorage.defaultCostLimit is not capped at 32 MB as its doc comment says

_Severity: low · user impact: low · public API: no · known: defects.md #14 · found by: data-loader_

**Where:** `Sources/Nuke/Internal/ResumableData.swift:77`

**Repro:** [NukeTests/data-loader--resumable-cost-limit-not-capped.swift](NukeTests/data-loader--resumable-cost-limit-not-capped.swift)

**What:** The doc comment reads "Cost limit for resumable data: 1% of physical memory, capped at 32 MB", but the code returns `Int(Double(physicalMemory) * 0.01)` with no cap. Before commit f0f07cc0 the limit was a fixed 32 MB; that commit kept the cap in the comment but dropped it from the code. As a result, partial downloads held in memory can grow to about 80 MB on an 8 GB iPhone and about 687 MB on this 64 GB Mac. The largest single entry grows the same way, because Cache drops any entry above 10% of the limit.

**Expected:** defaultCostLimit <= 32 MB on every device.

**Actual:** defaultCostLimit is 1% of RAM (about 687 MB here), so the check fails on any machine with more than about 3.2 GB of RAM.

**Reproduction check:** All 3 repetitions failed with "Expectation failed: limit <= 32 * 1024 * 1024": limit is 687194767 against 33554432, on a machine with 68719476736 bytes of RAM. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-4.log

**Why it was rejected:**

The code and its doc comment disagree, but the code is the version that matches the documented intent. The only defect is a stale comment on an internal symbol.

1. The only thing promising a 32 MB cap is a `///` comment on `ResumableDataStorage.defaultCostLimit` (Sources/Nuke/Internal/ResumableData.swift:76). That type is internal. It is not in Documentation/Nuke.docc or any public API doc, and the repro can only reach it through `@testable import`.

2. The public record agrees with the code. Commit f0f07cc0 is titled "Make ResumableData limit dynamic". The CHANGELOG entry from that same commit, still at CHANGELOG.md:245, says: "The storage cost limit of `ResumableDataStorage` is now dynamic and varies depending on the available RAM." No cap is mentioned. With a 32 MB cap, 1% of RAM would equal the old fixed 32,000,000 on every device with more than about 3.2 GB of RAM, which is nearly every current device. The change the commit title and CHANGELOG describe would then do almost nothing. In the same commit, the CHANGELOG also described `ImageCache.defaultCostLimit` as having "no hard cap". The 768 MB cap on ImageCache came a week later (a8b65e92, "Update ImageCache size"), and that commit did not touch the resumable limit. The phrase "capped at 32 MB" looks like leftover wording from the old fixed 32 MB, not a missing `min`.

3. A user sees no real harm. The storage is a `Cache` with countLimit 100. It clears completely on memory-pressure warnings (DispatchSource `.warning`/`.critical`) and trims to 10% when the app goes to the background on iOS, tvOS and visionOS. It holds only partial downloads whose server sent `Accept-Ranges: bytes` plus an ETag or Last-Modified validator, and only after a cancelled or failed load. Getting anywhere near 80 MB on an 8 GB iPhone takes many large, partly downloaded images. The larger per-entry limit (10% of the limit) actually lets bigger downloads resume, which is the purpose of the feature.

4. The repro's "expected <= 32 MB on every device" treats the internal comment as the contract and ignores the CHANGELOG. It is not a behavior a user of the public API could rely on. The numbers themselves are correct: this Mac has 68,719,476,736 bytes of RAM, so the limit here is about 687 MB (655 MiB).

What is real: a doc comment that contradicts its code, which is a documentation inconsistency. Relevant files: /Users/kean/Developer/Nuke/Sources/Nuke/Internal/ResumableData.swift (lines 76-79), /Users/kean/Developer/Nuke/Sources/Nuke/Caching/Cache.swift (lines 79-86, memory pressure; lines 185-195, background trim), /Users/kean/Developer/Nuke/CHANGELOG.md:245.


### D91. Resumable downloads send a weak ETag in If-Range (RFC 9110 §13.1.5 violation)

_Severity: low · user impact: low · public API: yes · found by: data-loader_

**Where:** `Sources/Nuke/Internal/ResumableData.swift:35`

**Repro:** [NukeTests/data-loader--weak-etag-sent-in-if-range.swift](NukeTests/data-loader--weak-etag-sent-in-if-range.swift)

**What:** _validator(from:) returns the ETag unchanged, including weak tags such as W/"abc", and resume(request:) sends it as If-Range. RFC 9110 §13.1.5 (formerly RFC 7233 §3.2) says a client MUST NOT send a weak entity tag in If-Range. A weak tag doesn't guarantee the bytes are identical, and joining a stored prefix to a new range needs exactly that. A compliant server never matches it and always answers 200 with the full body, so the stored partial data is wasted and still takes up storage. A lenient server or proxy that compares weakly can answer 206 for a representation that is only equivalent (for example re-encoded), and the pipeline then joins bytes from two different files into one image. Servers such as nginx and Apache send weak ETags whenever they compress the response.

**Expected:** A weak ETag is not used as the If-Range validator: either no resumable data is created, or the request doesn't depend on that tag.

**Actual:** The request carries If-Range: W/"abc".

**Reproduction check:** All 3 repetitions failed with "Expectation failed: ifRange?.hasPrefix(\"W/\") != true", and the message is If-Range: W/"abc". Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-data-loader-5.log

**Why it was rejected:**

The observation is accurate. `ResumableData._validator(from:)` (/Users/kean/Developer/Nuke/Sources/Nuke/Internal/ResumableData.swift:34-48) returns the ETag string unchanged, and `resume(request:)` sends it as If-Range, so `W/"abc"` goes out. That is against the letter of RFC 9110 §13.1.5. However, it is not a defect a user would hit:

1. Nothing promises otherwise. The docs (loading-data.md, performance-guide.md, CHANGELOG "Resumable Downloads") only say "Both validators are supported: ETag and Last-Modified". Neither the linked kean.blog post nor git history (the code dates to eecbee74 / 7231b501) says anything about validator strength. The Last-Modified path is equally lax: it sends the date without the strong-date check from §8.8.2.2. So the approach is "use whatever validator exists", not strict validator checking.

2. With a server that follows the spec, nothing visible happens. A weak tag fails the strong If-Range comparison, so the server answers 200. `TaskFetchOriginalData.dataTask(didReceiveResponse:)` only reuses the stored bytes on a 206 (`isResumedResponse`). Otherwise it drops them and uses the full body. The image is correct, and it is exactly what the proposed fix (no resumable data) would give. The "wasted storage" point is small. `performDataLoad` takes the entry out of the cache (`removeResumableData`) on the next load of that image, and the cache is limited to about 1% of RAM and 100 entries.

3. The data corruption case is theoretical. It needs all of these at once:
   (a) a server that sends a weak ETag together with Accept-Ranges: bytes and a Content-Length;
   (b) a server that compares If-Range weakly;
   (c) the same weak tag reused for different bytes;
   (d) the resource changing between the interrupted load and the resumed one.
   The lenient servers you actually meet derive weak tags from file identity. For example, Node's `send`/serve-static (Express static files) makes weak `W/"size-mtime"` ETags by default and matches If-Range by string, so it returns 206 only for the same file. There, the current behavior gives correct, working resumes. The suggested fix would turn resuming off for every such host, which is a real regression traded for a theoretical risk.

4. The evidence in the report is weak. As far as I recall the server sources (not checked in this session), nginx's gzip filter both weakens the ETag and clears Accept-Ranges, so Nuke never creates resumable data for those responses. Apache's mod_deflate by default adds a "-gzip" suffix to a strong ETag rather than making it weak, and it drops Content-Length, so the `data.count < expectedContentLength` check fails. Servers also rarely gzip images.

The repro calls an internal type through @testable. The public API reaches the same code (a cancelled load with a weak-ETag response, then a new request), so the test is not an artifact, but all it shows is the header value, not any harm. At most this is a strictness/hygiene item.


### D92. Progressive decoding never produces previews when the response has no Content-Length

_Severity: low · user impact: low · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:260`

**Repro:** [NukeTests/data-loading-tasks--no-previews-without-content-length.swift](NukeTests/data-loading-tasks--no-previews-without-content-length.swift)

**What:** The line `guard data.count < response.expectedContentLength + resumedDataCount else { return }` is never true when `expectedContentLength == -1` (unknown length: chunked transfer, or HTTP/2 without Content-Length). So partial data never reaches the decoder. The code comment mentions only the 0 case. The docs promise previews "as data arrives" with no Content-Length requirement, and the completion already marks the final chunk.

**Expected:** A progressive JPEG in 3 chunks produces the same previews with and without Content-Length.

**Actual:** 1 preview with Content-Length (the control case passes) and 0 without it.

**Reproduction check:** The reportsContentLength=false case failed 3/3 iterations with previews.value → 0. The control case reportsContentLength=true passed every iteration (log: scratchpad/logs/repro-data-loading-tasks-7.log).

**Why it was rejected:**

The behavior is real, and the public API reaches it. A custom DataLoading, or a real URLSession response with chunked transfer or no Content-Length, both hit it. `data.count < -1 + resumedDataCount` can never be true, so partial chunks never reach the decoder. But this is a deliberate limitation that dates back to the original design. It is not a defect.

1. The intent is documented in history. The guard was added in dbf4a511, "Implement progressive decoding" (2018), with the comment "In case `expectedContentLength` is undetermined (e.g. 0) we don't allow progressive decoding." NSURLResponseUnknownLength (-1) is exactly the "undetermined" case, and the code treats it the same as 0. Commit a7184a8c (2019, "Update documentation and comments") only reworded the comment to "is `0`". The code did not change. Commit 4120ea5f / PR #903 later adjusted the guard only for the resumed-206 case, which is a different bug where the length was known but compared wrongly. Nothing in the history or CHANGELOG suggests unknown-length previews were ever supported or intended.
2. The guard has a purpose. Without a known length, the pipeline can't tell whether the chunk it just got is the last one. Sending every chunk would also hand the complete payload to the decoder as a non-final "preview", right before the completion decodes it again.
3. Peer libraries do the same. SDWebImage (local checkout, SDWebImageDownloaderOperation.m:448-450 and 526-534) maps `expectedContentLength <= 0` to 0. When the size is unknown it returns early and skips progressive decoding entirely.
4. No doc promises previews without a Content-Length. The "as data arrives" wording in ImagePipeline-Extension.md and supported-image-formats.md describes the feature in general terms. It does not guarantee previews for every transfer encoding. The `DataLoading` docs only say chunks are used for progressive decoding.
5. Impact is minimal. The final image still loads and decodes correctly. Only the optional previews (which are opt-in and off by default) are missing, and most image CDNs send Content-Length.

At most there is a comment inaccuracy ("is `0`" should also mention -1/unknown) and a small documentation gap. This is a feature request, not a bug.


### D93. An ImagePipeline.Error thrown from willLoadData isn't wrapped in dataLoadingFailed, contrary to the delegate docs

_Severity: low · user impact: none · public API: yes · found by: data-loading-tasks_

**Where:** `Sources/Nuke/Tasks/TaskFetchOriginalData.swift:138`

**Repro:** [NukeTests/data-loading-tasks--will-load-data-pipeline-error-not-wrapped.swift](NukeTests/data-loading-tasks--will-load-data-pipeline-error-not-wrapped.swift)

**What:** The delegate docs say: "If an error is thrown, the image request fails with dataLoadingFailed(error:) wrapping the error"; loading-data.md says the same. `performDataLoad` shares one catch between the delegate and the download, and passes any `ImagePipeline.Error` through unchanged (the pass-through exists for `.dataDownloadExceededMaximumSize`). A custom `data` closure that throws the same error IS wrapped by `performAsyncDataLoad`, so the two paths disagree. The repro file includes that closure case as a passing control.

**Expected:** `.dataLoadingFailed(error: ImagePipeline.Error.dataMissingInCache)`

**Actual:** `.dataMissingInCache`, an error the request never produced itself; it doesn't use returnCacheDataDontLoad.

**Reproduction check:** pipelineErrorThrownFromWillLoadDataIsWrapped failed 3/3 iterations with 'Expected dataLoadingFailed, got Failed to load data from cache and download is disabled.' (a bare .dataMissingInCache). The control case pipelineErrorThrownFromDataClosureIsWrapped passed (log: scratchpad/logs/repro-data-loading-tasks-9.log).

**Why it was rejected:**

The code does behave as described. In Sources/Nuke/Tasks/TaskFetchOriginalData.swift:137, `performDataLoad` has one `catch` for both the delegate call and the download, and it passes any `ImagePipeline.Error` through unchanged. So a delegate that throws `.dataMissingInCache` gets `.dataMissingInCache` back, not `.dataLoadingFailed(.dataMissingInCache)`. The only mismatch is with the wording of two docs: the delegate doc comment ("wrapping the error") and loading-data.md. That wording skips the case where the thrown error is already an `ImagePipeline.Error`. I don't count this as a defect a user could hit:

1. It matches an existing Nuke convention. FetchImage.swift:215 does the same thing (`error as? ImagePipeline.Error ?? .dataLoadingFailed(error: error)`). Its doc comment, and the Nuke 14 Migration Guide, state the rule outright: "An error that isn't already an `ImagePipeline.Error` is reported as `dataLoadingFailed(error:)` wrapping it, the same way the pipeline reports the errors thrown by the async `ImageRequest` sources." The willLoadData path follows that rule. The `data` closure path (`performAsyncDataLoad`) wraps everything, including pipeline errors, so that path is the one that differs, not willLoadData.

2. History shows the pass-through was not added by accident for this hook. Commit 28c47d65 added `willLoadData` inside the existing do/catch, which already passed pipeline errors through. The original test (`willLoadDataThrowingCancelsWithDataLoadingFailed`) only covers a custom error type, which is the case the docs describe, and that case still wraps correctly.

3. The only way to trigger this is for the user's own delegate to throw an `ImagePipeline.Error`. They then get back exactly the error they threw, which is hard to call surprising. The report's claim that the request "never produced" the error is misleading, because the user's delegate produced it.

4. The "expected" result is worse than what happens today. If a delegate throws `.cancelled` (for example, to reject a request quietly), pass-through keeps `error.isCancelled == true` and gives the deprecated `ImageTask.state` of `.cancelled` (ImageTask.swift:471). Wrapping it would turn that into a real failure. The same goes for a delegate that throws `.dataLoadingFailed(error: x)` to follow the docs: pass-through avoids a double-wrapped `.dataLoadingFailed(.dataLoadingFailed(x))`. Nobody reasonably wants a pipeline error nested inside `dataLoadingFailed`.

5. The repro's "control" case (the `data` closure wraps a pipeline error) is really showing the less sensible of the two paths, and it doesn't show that willLoadData is wrong.

What is left is a small inaccuracy in the docs, not a behavior bug.


### D94. trim(toCount:) and trim(toCost:) remove the most recently used image when every image has been read

_Severity: low · user impact: low · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:225`

**Repro:** [NukeTests/memory-cache--trim-evicts-most-recently-used.swift](NukeTests/memory-cache--trim-evicts-most-recently-used.swift)

**What:** This is a mismatch between the docs and the behavior. trim(toCount:) and trim(toCost:) are documented as "Removes least recently used items", ImageCache as "An LRU memory cache", and cache-layers.md says "least recently used are removed first". Since the switch to CLOCK in 13.0.5 (commit a01bcfb3), a read only sets a reference bit (line 124) and the list stays in insertion order. When every entry is referenced, the sweep becomes first-in-first-out and removes the entry inserted first, however recently it was read. If this approximation is intended, the docs should say so. A related wording issue: the docs also say trimming continues until the total is "less than" the limit, but the code stops as soon as the total is at or below the limit.

**Expected:** After reads of c, then b, then a, trim(toCount: 2) (or trim(toCost: 20) with cost-10 entries) removes c, the least recently used image, and keeps a.

**Actual:** a, the most recently used image, is removed and c is kept.

**Reproduction check:** All 3 iterations failed, for both trim(toCount: 2) and trim(toCost: 20). `cache[key("a")] != nil` failed because a, the most recently read, was removed, and `cache[key("c")] == nil` failed because c, the least recently read, was kept. 12 issues in total. Log: scratchpad/logs/repro-memory-cache-4.log

**Why it was rejected:**

The mechanics are real, but they are the intended CLOCK approximation, not a defect.

I confirmed the claim by compiling the real Sources/Nuke/Caching/Cache.swift and Sources/Nuke/Internal/LinkedList.swift into a scratchpad harness. With a, b, c inserted and then read in the order c, b, a, both trim(toCount: 2) and trim(toCost: 20) keep [b, c] and drop a. Without the reads, trim also drops a (plain FIFO). This is the textbook property of second-chance/CLOCK: when every reference bit is set, the sweep clears them all and falls back to insertion order.

Why this is intentional:
- Commit a01bcfb3 is titled "Switch to CLOCK LRU in Cache".
- The code comments at Cache.swift:120-122 and 226-228 name the algorithm (CLOCK / second chance) and the reason (keep the read critical section to a single store under the unfair lock).
- The 13.0.5 CHANGELOG ships it as "Optimize ImageCache reads and writes for concurrent access patterns".
- Tests/NukeTests/CacheTests.swift has a dedicated "Eviction Order (CLOCK)" section (recentlyUsedEntriesGetASecondChance, overwritingAnEntryCountsAsAUse).
- The existing ImageCacheTests.trimToCountRespectsLRUOrder still passes, because the untouched entry is the victim.

The public docs ("An LRU memory cache", "Removes least recently used items") describe the policy in general terms. They promise no exact order, and CLOCK is conventionally described as an LRU policy. No public API exposes the eviction order. A reasonable app does not depend on which of several recently read images a manual trim drops; the only cost is one extra reload from disk or network.

The "less than" wording is not a regression. It dates from 2016 (ef60dc73), and the `> limit` loop condition predates CLOCK (48b4bc5d, 2022). "Trim to count N" leaving N items is the natural meaning, and trimToCountRespectsLRUOrder asserts totalCount == 2 after trim(toCount: 2). That is only a wording nit.

Related quirk found while verifying (not the reported claim, same root cause, also low impact): set() appends the new entry unreferenced and trims afterwards. With countLimit 3 and a, b, c all read, set(d) evicts d itself, so the image just stored is gone (verified: [a, b, c] remain). This happens once per fully referenced state, because the sweep clears every bit. The pipeline still hands the image to the task that loaded it; only a later lookup for the same key misses.

Overall this is a docs-precision issue, not a behavioral bug.


### D95. Entering the background removes nothing from a cache that is less than 10% full (iOS, tvOS, visionOS)

_Severity: low · user impact: low · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:185`

**Repro:** [NukeTests/memory-cache--background-trim-keeps-lightly-filled-cache.swift](NukeTests/memory-cache--background-trim-keeps-lightly-filled-cache.swift)

**What:** clearCacheOnEnterBackground() trims to 10% of the limits (costLimit * 0.1 and countLimit * 0.1), not to 10% of what the cache holds. Several docs describe the behavior differently. The ImageCache doc comment and cache-layers.md say it "removes *most* stored elements when the app enters the background", performance-guide.md says it "removes a portion of its contents", and the Nuke 12 CHANGELOG says "it clears 90% of the used RAM". With the default limits (cost up to 768 MB, count Int.max), an app holding less than about 77 MB of images keeps all of them in the background. The repro posts didEnterBackgroundNotification the same way the existing ImageCacheTests do. It first waits for the observer to register, using a cache that is full by count, so the result doesn't depend on timing. It was confirmed failing on the iOS 16e simulator.

**Expected:** After the notification, at most a minority of the 5 stored images remain (at most 2).

**Actual:** All 5 images remain, because together they cost 50 of a 1000-byte limit.

**Reproduction check:** Ran on the iOS Simulator (iPhone 16e, id 7A8A0173-1A55-462F-8A3A-33A21DB67FBF, derived data dd-memory-cache-ios). All 3 iterations failed `cache.totalCount <= 2` with totalCount 5. Log: scratchpad/logs/repro-memory-cache-5.log

**Why it was rejected:**

The repro is accurate: 5 entries costing 50 of a 1000-byte limit all survive the notification. But this is intended behavior that has been in place for about ten years, not a defect.

1) Intent. The trim was added in cb4beac7 (2016, "Cache trims objects on entering background") with exactly `trim(toCost: costLimit * 0.1)` and `trim(toCount: countLimit * 0.1)`. 48b4bc5d (2022) carried it over unchanged. The code comment at Sources/Nuke/Caching/Cache.swift:176-179 still says "This feature is not documented and may be subject to change". The design caps the cache's background footprint at 10% of its limits. A cache already under that cap is small by definition and has nothing to give back.

2) Tests pin these semantics. The existing tests in Tests/NukeTests/ImageCacheTests.swift:407-446 (someImagesAreRemovedOnDidEnterBackground and someImagesAreRemovedBasedOnCostOnDidEnterBackground) fill the cache exactly to countLimit=10 or costLimit=10*cost and expect 1 entry to remain. That is "10% of the limit", not "10% of the contents".

3) Docs. "Removes *most* stored elements" in the ImageCache doc comment and cache-layers.md, and "a portion of its contents" in performance-guide.md, are loose descriptions. None of them promises a trim proportional to what the cache holds. "A portion" can even be read as consistent with removing nothing when the cache is lightly filled. The Nuke 12 CHANGELOG line ("clears 90% of the used RAM") argues for the default size limit, so it is about a cache running at that limit, where 10% of the limit really does equal 10% of the RAM in use. No API contract or test promises content-relative trimming, and a user can't observe a correctness problem from it. At worst an app keeps up to about 77 MB (10% of the 768 MB default cap) in the background. The memory-pressure source still clears everything on warning or critical, so the OS can reclaim that memory when it needs to.

The behavior can be reached through the public API: a real didEnterBackground notification on a public ImageCache. Still, the most this finding amounts to is imprecise wording in the docs. It is not a defect in the code.


### D96. An image that costs exactly the documented maximum entry cost is refused

_Severity: low · user impact: none · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:134`

**Repro:** [NukeTests/memory-cache--entry-at-max-cost-rejected.swift](NukeTests/memory-cache--entry-at-max-cost-rejected.swift)

**What:** entryCostLimit is documented as "The maximum cost of an entry in proportion to the costLimit", but the admission check is `guard cost < _conf.entryMaxCost`. That strict comparison refuses the documented maximum itself. With entryCostLimit = 1, an image costing exactly costLimit is refused even though the cache has room for it (totalCost <= costLimit). With the default 0.1 and a 1000-byte limit, a 100-byte image is refused.

**Expected:** An image whose cost equals entryCostLimit times costLimit is stored.

**Actual:** It is dropped: cache[key] is nil and totalCost is 0. Only images that cost strictly less are stored.

**Reproduction check:** All 3 iterations failed. With entryCostLimit 1, costLimit 100 and cost 100, `cache[key] != nil` failed (nil) and `cache.totalCost == 100` failed (0). With the default 0.1, costLimit 1000 and cost 100, `cache[key] != nil` failed. 9 issues in total. Log: scratchpad/logs/repro-memory-cache-6.log

**Why it was rejected:**

The report describes the code correctly. `Cache.set` (Sources/Nuke/Caching/Cache.swift:134) uses `guard cost < _conf.entryMaxCost`, so an entry costing exactly entryCostLimit × costLimit is refused. The repro only uses public API (ImageCache(costLimit:countLimit:), entryCostLimit, ImageCacheKey(key:), subscript), so it is reachable. It is still not a real defect a user can hit:

1. Strict comparison has always been the behavior. The original commit 879fb183 "Add entryCostLimit" (Nuke 10.1.0, 2021) wrote `cost < Int(sanitizedEntryLimit * Double(costLimit))`. Every later refactor (79d85e20, which moved it into Cache; 3c3f3cff; 2fb459e8 "Precompute entryMaxCost") kept `<` on purpose.

2. Existing tests rely on the exclusive bound. `InternalCacheTests.negativeEntryCostLimitRejectsEverything` expects that entryCostLimit clamped to 0 rejects even a cost-0 entry, which only holds with `<`. `entryCostLimitIsClampedToTheValidRange` uses cost 99 against a limit of 100, not 100.

3. Nothing promises an inclusive bound. The doc comment ("The maximum cost of an entry in proportion to the costLimit") and the CHANGELOG entry are loose descriptions of a heuristic that keeps a few large images from filling the cache. Neither the docs nor DocC says an entry costing exactly the product is kept.

4. The impact is effectively zero. For real images, `memoryCost` is bytesPerRow × height + data.count. The chance that it lands on the exact byte of the threshold is negligible, and when it does, the outcome is the same as for an image 1 byte bigger: it isn't memory-cached and is fetched or decoded again. No crash, no leak, no wrong image. Only a synthetic test that builds the cost to the exact byte shows it.

This is a documentation-precision nit about an exclusive vs inclusive boundary, not a behavioral bug.


### D97. To make room, the cache evicts a live image and keeps an expired one it will never return

_Severity: low · user impact: low · public API: yes · found by: memory-cache_

**Where:** `Sources/Nuke/Caching/Cache.swift:225`

**Repro:** [NukeTests/memory-cache--review-expired-entry-outlives-live-one.swift](NukeTests/memory-cache--review-expired-entry-outlives-live-one.swift)

**What:** The CLOCK sweep in _trim(while:) never checks Entry.isExpired. If an entry was read while fresh, its reference bit is set, and that bit still earns it a second chance after its TTL has run out. The sweep moves the expired entry to the tail and evicts the next unreferenced entry, which is a live image. The expired entry then only gets dropped by the next lookup, which misses. Until then it keeps counting toward totalCount and totalCost. True LRU would also evict the expired entry here, since its last use came before the live image was stored. With a TTL in use and a full cache, images that were on screen shortly before they expired push out fresh, never-read images.

**Expected:** When 'c' is stored into a full cache (countLimit 2) holding an expired, previously read 'a' and a live 'b', 'a' is removed. Afterwards 'b' and 'c' are both served and totalCount is 2.

**Actual:** 'b' is evicted. 'a' survives the sweep and is dropped on the next lookup, so the cache ends up holding only 'c' (totalCount 1) even though it had room for two images.

**Reproduction check:** All 3 iterations failed. `cache[key("b")] != nil` failed because the live b was evicted, and `cache.totalCount == 2` failed with 1. `cache[key("c")] != nil` and `cache[key("a")] == nil` passed. 6 issues in total. Log: scratchpad/logs/repro-memory-cache-7.log

**Why it was rejected:**

The trace is correct. With countLimit 2, reading 'a' sets its reference bit. Storing 'c' makes the sweep rotate 'a' to the tail and evict 'b'. The next lookup of 'a' finds it expired and removes it, which leaves totalCount at 1. So the behaviour is real, but it is not a defect for these reasons.

1. The recency ordering is the intended CLOCK approximation. Commit a01bcfb3 ("Switch to CLOCK LRU in Cache", shipped in 13.0.5 as "Optimize ImageCache reads and writes for concurrent access patterns") deliberately replaced move-to-tail on read with a reference bit to shorten the lock hold. The same sequence with no TTL at all (read 'a', store 'b', store 'c') also evicts 'b' under CLOCK and 'a' under strict LRU. The report's point that "true LRU would evict 'a'" is this known trade-off, restated in TTL terms.

2. Eviction has never looked at expiry. Expiry has always been lazy: it is checked only in value(forKey:). The pre-CLOCK _trim(while:) was `while condition(), let node = list.first { _remove(node: node) }` with no isExpired check. Under that strict LRU, a slightly different order also evicts the live 'b' and keeps the expired 'a' (store 'a' with a TTL, store 'b', read 'a' while fresh so it moves to the tail, let 'a' expire, store 'c'). Expired entries have always counted toward totalCount and totalCost until a lookup or the sweep reaches them. This is not a regression.

3. Nothing promises otherwise. The ImageCache.ttl doc says only "Can be used to make sure that the entries get validated at some point", which means stale images are not served, and the cache does honour that ('a' is never returned after it expires). No doc comment, DocC article or CHANGELOG entry promises that expired entries are evicted first or that their memory is freed promptly. The docs call the cache "LRU" loosely, and CLOCK is a standard LRU approximation.

4. The impact is marginal. It needs a TTL, a full cache, and an entry that was read while fresh, expired, and was not looked up again before the next sweep. Even then the expired entry loses its bit on that pass and is evicted on the next one, so it costs at most one extra eviction per such entry. The result is a slightly lower hit rate, not a correctness, memory-safety or stale-data problem.

The repro uses only public ImageCache API (ttl, the subscript, totalCount, and ImageCacheKey(key:) is public), so a user can reach it. What it shows is a possible optimisation, not a broken contract.


### D98. LazyImage restarts a still-running request on reappear, even when onDisappear(nil) or .lowerPriority kept it alive

_Severity: low · user impact: low · public API: yes · found by: nukeui-swiftui_

**Where:** `Sources/NukeUI/LazyImage.swift:189`

**Repro:** [NukeUITests/nukeui-swiftui--lazyimage-reappear-restarts-live-request.swift](NukeUITests/nukeui-swiftui--lazyimage-reappear-restarts-live-request.swift)

**What:** onAppear() always calls viewModel.load(context?.request), and FetchImage.load starts with cancel(). With a single subscriber, that cancel tears down the whole task graph (AsyncTask terminate(.cancelled)), so the in-flight data task is cancelled and a new one starts. Everything downloaded while the view was off screen is lost, which defeats `.onDisappear(nil)` ('disable any behavior on disappear') and `.lowerPriority`, whose only point is to keep the download going. The same unconditional load also double-starts a request: if the URL changes while the view is off screen, SwiftUI delivers both onAppear and onChange on reappear, and each one calls load.

**Expected:** On reappear the running ImageTask is kept (its priority restored) and no second data task is created. A request that changed off screen is started once.

**Actual:** The first ImageTask is cancelled and a second one starts. The data loader gets a DidCancelTask and then a second data task for the same URL (createdTaskCount 2). A URL changed off screen gets 2 tasks, one of them cancelled right away.

**Reproduction check:** All 3 tests failed on all 3 iterations. (1) onDisappear(nil): '!firstTask.isCancelled' and 'tasks.value.count == 1' failed after showContent; the same check after hideContent passed (line 68), so the task stayed alive off screen and was cancelled on reappear. (2) .lowerPriority: '!firstTask.isCancelled', 'tasks.value.count == 1' and 'dataLoader.createdTaskCount == 1' failed. The data loader got DidCancelTask and then created a second data task. (3) Request changed off screen: 'tasksForOtherURL.count == 1' and '!tasksForOtherURL.contains { $0.isCancelled }' failed, meaning 2 tasks for the new URL, one of them cancelled.

**Why it was rejected:**

The repro does what it says. I ran it on macOS in a scratch worktree of HEAD 2c2b23f6. HEAD's test target doesn't compile alone ("ambiguous use of 'Color'"), so I applied the uncommitted `SwiftUI.Color` diff from the main checkout. All 7 expectations failed: on reappear, the running ImageTask is cancelled, a second one starts, the MockDataLoader creates a second data task, and a URL changed off screen gets 2 ImageTasks. The mechanism is correct: `onAppear()` always calls `viewModel.load(...)`, `FetchImage.load` begins with `cancel()`, and the cancel reaches `@ImagePipelineActor` before the new start. With one subscriber, `AsyncTask.unsubsribe` then calls `terminate(.cancelled)`.

The behavior is intended and documented, though, so this is a feature request rather than a defect:

1. **Docs.** `Documentation/NukeUI.docc/Extensions/LazyImage-Extensions.md` describes this cycle: "when it disappears, the current request automatically gets canceled. When the view reappears, the download picks up where it left off, thanks to resumable downloads." `isResumableDataEnabled` is on by default. `TaskFetchOriginalData.onCancelled` calls `tryToSaveResumableData()`, and the restarted request resumes with Range/If-Range.
2. **Committed test.** `priorityRestoredWhenViewReappears` in `Tests/NukeUITests/LazyImageTests.swift` (commit 181d6d7f) says "Reappearing restarts the request" and asserts `#expect(secondTask !== firstTask)`. The repro's expected outcome directly contradicts a test the maintainer committed.
3. **History.** Commit b40a4a7d edited this exact line in `onAppear` to add `viewModel.priority = nil`, with the comment "so that the requests use their own priorities again", and deliberately kept the `load`. `onAppear` has reloaded unconditionally since NukeUI was moved in (154f8fdc, 2022).
4. **Nothing promises the "expected" behavior.** `.onDisappear(nil)` is documented as "disable any behavior on disappear", which is true: nothing happens on disappear. `.lowerPriority` is documented as "Lowers the request's priority to very low", which is also true. Neither says anything about what happens on appear.
5. **`.lowerPriority` still does its job.** The download keeps running off screen. If it finishes there, reappear gets a synchronous memory-cache hit in `FetchImage.load`. If it doesn't, resumable data continues from the saved bytes.
6. **"Everything downloaded is lost" is overstated.** The MockDataLoader returns no ETag/Last-Modified or Accept-Ranges, so the test can't show resumption. Against real servers that send those headers (most CDNs), the bytes are kept. They are lost only when the server doesn't support ranges.

The double start after an off-screen URL change is real (`onAppear` and `onChange(of: context)` both call `load`). But the first task is cancelled before any callback: `FetchImage.cancel` guarantees no more callbacks. The user-visible effects are `onStart` firing twice and one cancelled ImageTask reported to the pipeline delegate. It depends on SwiftUI holding back `onChange` until reappear, and I saw that only in the ViewHost window-detach harness. It's a minor inefficiency, not a correctness bug.

What remains is a reasonable enhancement: reuse a still-running task on reappear. It isn't a defect that breaks a documented contract.


### D99. Default disk cache keys concatenate their parts without separators and collide

_Severity: low · user impact: low · public API: yes · found by: pipeline-caching_

**Where:** `Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:236`

**Repro:** [NukeTests/pipeline-caching--disk-key-concatenation-collision.swift](NukeTests/pipeline-caching--disk-key-concatenation-collision.swift)

**What:** `makeDataCacheKey` concatenates imageID, thumbnail identifier and processor identifiers with no separator, and `ImageProcessors.Composition.identifier` also joins with "". Processors ["blur","red"] and ["blurred"] get the same disk key, and so do URL ".../example.jpeg" with processor "1" and URL ".../example.jpeg1". The memory keys for these requests differ. The result is that the disk cache serves one request's processed image to the other.

**Expected:** Requests with different memory cache keys don't share a disk cache entry, and each request's own processor runs.

**Actual:** Both requests get "http://test.com/example.jpegblurred". After the first request stores its image under `.automatic`, the second is served that image from disk and its processor never runs.

**Reproduction check:** In 3/3 iterations, makeDataCacheKey returned "http://test.com/example.jpegblurred" for both [blur, red] and [blurred], and "http://test.com/example.jpeg1" for both url+processor "1" and url "...example.jpeg1". The memory keys differed (that assertion passed). In the end-to-end test under .automatic, the second request had `response.cacheType == .disk` and its own processor ran 0 times (expected 1). Log: scratchpad/logs/repro-pipeline-caching-6.log

**Why it was rejected:**

The claim is technically true: `makeDataCacheKey` (Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:235) builds the key as imageID + thumbnail identifier + `ImageProcessors.Composition.identifier`, and that last part is `processors.map { $0.identifier }.joined()` with no separator (ImageProcessors+Composition.swift:48). So the function can return the same key for different requests. But this is deliberate, long-standing behaviour, and a user only hits it by breaking the documented identifier convention.

1. **Intentional and pinned by tests.** The format goes back to `makeCacheKeyForFinalImageData` and survived refactors in 1f1fc21a (2024) and 35e951d29 (2026-03), which only swapped the imageID accessor. Tests/NukeTests/ImagePipelineTests/ImagePipelineTests.swift:309-313 (`cacheKeyForRequestWithProcessors`) asserts the exact string the repro calls a collision: `Anonymous(id: "1")` gives "http://test.com/example.jpeg1". The thumbnail tests at lines 316-331 also assert plain concatenation.

2. **The repro relies on identifiers the docs steer users away from.** `ImageProcessing.identifier` says it "uniquely identifies the processor. Consider using the reverse DNS notation." image-processing.md says the same. Every built-in identifier starts with a fixed marker: "com.github.kean/nuke/..." for processors and "com.github/kean/nuke/thumbnail?..." for thumbnails. Each part therefore starts with a recognisable marker, so a concatenation of built-ins, or of reverse-DNS custom ids, can be read back in only one way. A collision needs overlapping custom ids like "blur"/"red" vs "blurred", or bare numbers like "1", or a URL that literally ends with another request's processor id. The repro uses exactly those.

3. **Memory and disk keys were never meant to match.** `MemoryCacheKey` includes `scale` and compares processors by `hashableIdentifier`, which is documented as possibly different from `identifier`. The disk key uses neither. So "different memory keys imply different disk keys" is not a documented guarantee.

4. **No field reports.** A GitHub issue search turns up nothing about key collisions in about six years. The only related bug, #705, was about thumbnail options in the original-data key, and was fixed in 192964e3.

5. **Changing it has a real cost, and there is already a way out.** Disk keys persist across launches, so any format change throws away users' existing processed-image caches. Users who need different keys can already supply them through `ImagePipeline.Delegate.cacheKey(for:pipeline:)`.

One detail the agent missed: the TaskLoadImage start path looks up the processed key on disk unconditionally. So the URL-plus-"1" case collides even with the default `.storeOriginalData` policy: data for URL "…/example.jpeg1" would be served to "…/example.jpeg" with processor "1". That makes the ambiguity a bit wider than claimed, but it still needs identifiers crafted to overlap. The repro uses @testable helpers (MockDataCache, Test.url), but the same path is reachable through the public API.

Verdict: a latent weakness, not a defect a user following the docs would hit. Low impact.


### D100. A NaN request scale breaks key equality: memory cache never hits and the pipeline leaks

_Severity: low · user impact: low · public API: yes · found by: pipeline-caching_

**Where:** `Sources/Nuke/Internal/ImageRequestKeys.swift:93`

**Repro:** [NukeTests/pipeline-caching--nan-scale-breaks-keys-and-leaks-pipeline.swift](NukeTests/pipeline-caching--nan-scale-breaks-keys-and-leaks-pipeline.swift)

**What:** `MemoryCacheKey` and the struct `TaskFetchOriginalImageKey` compare `scale` with `==`, so a NaN scale makes a key unequal to itself, which breaks the Hashable contract. Consequences: `cache[request] = image` followed by `cache[request]` returns nil, and every load adds another entry that can never be read or removed. `TaskPool` also can't remove the disposed `TaskFetchOriginalImage` (`map[key] = nil` finds nothing), and that task holds the pipeline strongly, so the pipeline and its caches leak permanently. `TaskLoadImageKey` has an `===` short-circuit and does not leak.

**Expected:** A stored image can be read back, and the pipeline is deallocated once it has no outstanding work. With scale 1 it deallocates within milliseconds.

**Actual:** The memory lookup returns nil, and with a NaN scale the pipeline is still alive after 5 s.

**Reproduction check:** In 3/3 iterations, `pipeline.cache[request] != nil` failed right after `pipeline.cache[request] = Test.container` with scale NaN. For scale NaN, `waitUntil` timed out after 5 s and `weakPipeline.value == nil` failed. The scale 1 case passed. Log: scratchpad/logs/repro-pipeline-caching-8.log

**Why it was rejected:**

The mechanism is real, and it can be reached through the public API. I reproduced it on macOS with a standalone copy of Sources/ (scratchpad/nanrepro) that uses only public calls:
- `pipeline.cache[request]` returns nil right after a store when `request.scale = .nan`.
- With `imageCache = nil` and a data-backed request, the pipeline was still alive after 5 s with NaN. With scale 1 it was released almost at once.

Why it happens:
- `ImageRequest.scale` stores `Float(newValue)`, so NaN stays NaN.
- `MemoryCacheKey.==` (ImageRequestKeys.swift:49) compares `lhs.scale == rhs.scale`. The synthesized `==` of the struct `TaskFetchOriginalImageKey` does the same, so NaN != NaN.
- `TaskPool.publisherForKey`'s `onDisposed` runs `map[key] = nil` (AsyncTask.swift:391). That finds nothing, so the disposed `TaskFetchOriginalImage` stays in the pool. It holds `pipeline` strongly (AsyncPipelineTask.swift:10), which gives pipeline -> tasksFetchOriginalImage -> map -> task -> pipeline.

I still don't count this as a defect a user would reasonably hit, for four reasons:
1. The input is nonsensical. The property is documented as "The display scale of the image. By default, `1`", and the only sources the docs show (the migration guides use `traitCollection.displayScale` and `2.0`) never produce NaN. The worst realistic bad value is 0 (the CHANGELOG mentions `displayScale` reporting 0 outside UIKit), and 0 compares equal to itself, so it causes no leak.
2. NaN also breaks the image itself. The decoder passes `context.request.scale` straight into `UIImage(data:scale:)` / `UIImage(cgImage:scale:orientation:)` (ImageDecoders+Default.swift:205/213, Graphics.swift:504/522). So on iOS/tvOS/watchOS/visionOS a NaN scale is already garbage for the decoded image, apart from any caching problem.
3. Any `Hashable` key built from floating-point values behaves the same way. Swift's own `Dictionary<Double, _>` / `Set<Double>` can never look up or remove a NaN key; the standard library accepts that IEEE behavior. Nuke's keys inherit it; they don't introduce a new contract violation.
4. With the usual long-lived `ImagePipeline.shared`, the "pipeline leak" can't be seen. What's left is one small leaked task entry (request, decoder, pipeline reference) per NaN-scaled load. The memory-cache entries can't be read, but they are still bounded and evicted by the cost limit.

Nothing in the docs or CHANGELOG promises how a NaN scale behaves. Git history (2b55252b "Fix an issue with scale and coalesing", 66f90711, 3776cae7) shows scale was added to the keys on purpose, with no thought given to non-finite values.

This is a cheap hardening candidate for invalid input, not a bug a user of the API would reasonably hit, so I rate it refuted with low impact.


### D101. Composition identifiers are joined with no separator, so different processor lists share a disk cache key

_Severity: low · user impact: low · public API: yes · found by: processing-graphics-encoding_

**Where:** `Sources/Nuke/Processing/ImageProcessors+Composition.swift:48`

**Repro:** [NukeTests/processing-graphics-encoding--review-composition-identifier-collision.swift](NukeTests/processing-graphics-encoding--review-composition-identifier-collision.swift)

**What:** Composition.identifier is processors.map(\.identifier).joined(). makeDataCacheKey (ImagePipeline+Cache.swift:235) joins imageID, the thumbnail id and that identifier, also with no separators. [Anonymous(id: "blur"), Anonymous(id: "red")] and [Anonymous(id: "blurred")] both give "blurred", even though each processor's identifier is unique, which is all the protocol asks for. The memory cache keeps them apart because it compares hashableIdentifiers element by element. The disk cache doesn't, so one request is served the other's processed image once the memory cache no longer has it. The repro shows it end to end with .storeEncodedImages: a request that doesn't resize at all is served another request's 13x10 image from disk. Reverse-DNS ids, which the docs recommend, make a collision unlikely. Short Anonymous ids don't.

**Expected:** Different processor lists produce different data cache keys, as they already produce different memory cache keys.

**Actual:** Both requests get the key "http://test.com/example.jpegblurred". The second request returns cacheType .disk and the other list's 13x10 image instead of 640x480.

**Reproduction check:** In 3/3 iterations on macOS, both requests got makeDataCacheKey → "http://test.com/example.jpegblurred", while the memory cache keys were different (that expectation passed). End to end with .storeEncodedImages and no memory cache, the second request returned cacheType .disk and a 13x10 image instead of loading and getting 640x480. Log: /private/tmp/claude-501/-Users-kean-Developer-Nuke/57bfcb06-d830-4948-a24c-27cb27eb2ad7/scratchpad/logs/repro-processing-graphics-encoding-12.log

**Why it was rejected:**

The mechanics are accurate. `ImageProcessors.Composition.identifier` is `processors.map(\.identifier).joined()` (Sources/Nuke/Processing/ImageProcessors+Composition.swift:48). `makeDataCacheKey` (Sources/Nuke/Pipeline/ImagePipeline+Cache.swift:235) builds `imageID + thumbnail id + composition id` with no separator. So the key derivation can map two different inputs to the same key.

It is still not a defect a user would realistically hit:
1. **The collision needs a contrived identifier.** One processor's identifier must exactly equal the concatenation of two other processors' identifiers, and both must be applied to the same image URL. The repro's end-to-end test builds this on purpose (`"blur" + Resize(...).identifier`). The first test needs an app that uses ids "blur", "red" and "blurred" on the same URL.
2. **The docs point away from it.** `ImageProcessing.identifier` says "Consider using the reverse DNS notation". Every built-in processor uses a `com.github.kean/nuke/...` prefix, so each identifier in the joined string starts with a domain. A single identifier equal to `com.a/xcom.b/y` is not something anyone writes.
3. **The report's README claim is wrong.** It says the README uses short `Anonymous` ids. Grepping README.md and Documentation/*.docc finds no `Anonymous(id:` or `process(id:` examples with short ids.
4. **The same limitation is already accepted elsewhere in the key.** The key also concatenates `imageID` directly with the processor id, so URL `…/a.jpg` plus processor `x` equals URL `…/a.jpgx`. The unseparated disk key format dates back to the original `ImagePipeline.Cache` API (c006aeeb) and appears deliberate and long-standing.
5. **A fix has a real cost.** Changing the format would change the disk cache key of every processed image for every user on upgrade, invalidating their caches.

This is a theoretical weakness in how the key is built, not a bug a reasonable user of the public API would run into. Impact is low: if it ever happens, the wrong processed image is served from disk.


### D102. ImageRequest.scale doesn't read back the CGFloat it was set to (stored as Float)

_Severity: low · user impact: none · public API: yes · found by: request-model_

**Where:** `Sources/Nuke/ImageRequest.swift:114`

**Repro:** [NukeTests/request-model--scale-float-roundtrip.swift](NukeTests/request-model--scale-float-roundtrip.swift)

**What:** Nuke 14 changed the public type of `scale` to `CGFloat`. The migration guide says this matches the types you get from UIKit and SwiftUI. But the storage is still `Float` (`Container.scale: Float` at line 516; the setter does `Float(newValue)`). Any value that `Float` can't hold exactly gets rounded, including real device scales. The decoded image gets the rounded scale too, because `ImageDecoders.Default` reads `context.request.scale`.

**Expected:** `request.scale = 2.608` (the nativeScale of the Plus-size iPhones) reads back as `2.608`.

**Actual:** It reads back as `2.6080000400543213`. The same happens for 2.88 and 1.1.

**Reproduction check:** Failed in all 3 iterations for every argument. 2.608 read back as 2.6080000400543213, 2.88 as 2.880000114440918, and 1.1 as 1.100000023841858.

**Why it was rejected:**

The arithmetic is right: `CGFloat(Float(2.608))` gives 2.6080000400543213, and the public getter/setter do round-trip through `Float` (Sources/Nuke/ImageRequest.swift:112-115, `Container.scale: Float` at :516). I still don't think it's a defect a user could hit.

1. **The `Float` storage is deliberate.** Commit 4aa041ac ("Put scale property in a gap in memory") moved the 4-byte `Float` into the padding after `resource`/`priority`/`options`, so it costs no space in the CoW container. The container-size test (`ImageRequestTests.memoryLayout`, expects 104 bytes) is currently disabled, but the intent is plain. Commit 66f90711 (PR #910) changed only the public type, on purpose. The migration guide and CHANGELOG line promise a type change "matching the types you get from UIKit and SwiftUI". Neither they nor the doc comment ("The display scale of the image. By default, `1`.") promises that the value reads back bit-for-bit.

2. **Precision is the same as Nuke 13.** Before, the property was `Float` and the documented pattern was `request.scale = Float(traitCollection.displayScale)`, which rounds the same way. The migration only removes a conversion at the call site.

3. **Real display scales are exact.** The migration guide shows `traitCollection.displayScale`, which is always 1, 2 or 3 on iOS/tvOS/visionOS/watchOS. `backingScaleFactor` on macOS is 1 or 2. `Float` holds all of these exactly; I checked that 1, 2 and 3 round-trip. Fractional values like 2.608 and 2.88 are `UIScreen.nativeScale`, which isn't what you set as an image's display scale.

4. **Nothing inside Nuke breaks.** Every internal reader sees the same rounded value: `MemoryCacheKey`, `TaskFetchOriginalImageKey`, `ImageDecoders.Default`, the NukeUI `AnimatedImageView`/`AnimatedImagePlayer` scale matching, and the diagnostics digest. So cache keys, coalescing and the poster-to-animation handoff stay consistent. The disk cache key (`makeDataCacheKey`) doesn't include scale at all.

5. **The size effect is invisible.** A 1000 px image comes out about 6e-6 to 2e-5 pt off (I measured 2.608, 2.88 and 1.1). The only way to notice is exact `==` between `request.scale` (or `image.scale`) and a non-representable `CGFloat`. That is a floating-point equality check on a property whose precision was never promised.

The public getter/setter do reach this path, but the only symptom is `==` failing on a non-representable fractional scale. That doesn't change behavior or pixels.

