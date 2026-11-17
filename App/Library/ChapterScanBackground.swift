import Foundation
import UIKit
import BackgroundTasks

/// Keeps Find Chapters going after you leave the app.
///
/// - iOS 26 and later: a *continued processing task*. iOS keeps the app running while chapters
///   are being found, shows the progress in its own system UI ("Finding chapters · Book title"),
///   and lets you stop it from there.
/// - Earlier systems: the extra half-minute or so that iOS gives any app after you leave it.
///   (While a book is playing, the app keeps running anyway, so scans carry on then too.)
///
/// `ChapterScanner` calls `scanStarted`, `progressed` and `scanningFinished`; nothing else needs to.
@MainActor
final class ChapterScanBackground {
    static let shared = ChapterScanBackground()

    /// Must match `BGTaskSchedulerPermittedIdentifiers` in App-Info.plist
    /// (`$(PRODUCT_BUNDLE_IDENTIFIER).findChapters.*`).
    private static let identifierPrefix = (Bundle.main.bundleIdentifier ?? "audiobooks") + ".findChapters."

    /// The running continued-processing task (a `BGContinuedProcessingTask` on iOS 26+).
    private var continuedTask: AnyObject?
    /// Submitted, but iOS hasn't started it yet.
    private var waitingToStart = false
    private var latestTitle = ""
    private var latestFraction = 0.0
    private var fallbackTask: UIBackgroundTaskIdentifier = .invalid
    private var lastProgressUpdate = Date.distantPast

    private init() {}

    /// A book's scan is starting (the first of a run, or the next in the queue).
    func scanStarted(title: String) {
        latestTitle = title
        latestFraction = 0
        if #available(iOS 26.0, *) {
            if let task = continuedTask as? BGContinuedProcessingTask {
                task.updateTitle("Finding chapters", subtitle: title)
                task.progress.completedUnitCount = 0
                return
            }
            if waitingToStart { return }
            if submitContinuedTask(title: title) { return }
        }
        beginFallback()
    }

    /// Progress of the current book (0…1).
    func progressed(_ fraction: Double) {
        latestFraction = fraction
        // The system's progress UI doesn't need more than one update a second.
        let now = Date()
        guard now.timeIntervalSince(lastProgressUpdate) >= 1 else { return }
        lastProgressUpdate = now
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64((fraction * 1000).rounded())
        }
    }

    /// Nothing left to scan.
    func scanningFinished() {
        waitingToStart = false
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.setTaskCompleted(success: true)
        }
        continuedTask = nil
        endFallback()
    }

    // MARK: - iOS 26+: continued processing

    @available(iOS 26.0, *)
    private func submitContinuedTask(title: String) -> Bool {
        let identifier = Self.identifierPrefix + UUID().uuidString
        // Registered right before submitting, for this exact identifier (registering only the
        // wildcard pattern isn't reliably matched by iOS).
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                ChapterScanBackground.shared.started(task)
            }
        }
        guard registered else { return false }

        let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                                                       title: "Finding chapters",
                                                       subtitle: title)
        do {
            try BGTaskScheduler.shared.submit(request)
            waitingToStart = true
            return true
        } catch {
            print("Couldn't start background chapter finding: \(error.localizedDescription)")
            return false
        }
    }

    @available(iOS 26.0, *)
    private func started(_ task: BGContinuedProcessingTask) {
        waitingToStart = false
        // The scan may have finished before iOS got round to starting the task.
        guard ChapterScanner.shared.isBusy else {
            task.setTaskCompleted(success: true)
            return
        }
        continuedTask = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = Int64((latestFraction * 1000).rounded())
        task.updateTitle("Finding chapters", subtitle: latestTitle)
        // iOS needs to stop it (the iPhone is hot, or you stopped it from the system's
        // progress UI). The scan isn't thrown away: iOS pauses the app, and the scan carries on
        // from where it was when you open the app again.
        task.expirationHandler = {
            Task { @MainActor in
                ChapterScanBackground.shared.continuedTask = nil
                task.setTaskCompleted(success: false)
            }
        }
        endFallback()
    }

    // MARK: - Earlier systems: a little extra time

    private func beginFallback() {
        guard fallbackTask == .invalid else { return }
        fallbackTask = UIApplication.shared.beginBackgroundTask(withName: "Find Chapters") {
            // Time's up: iOS pauses the app. The scan picks up where it was when you come back.
            Task { @MainActor in ChapterScanBackground.shared.endFallback() }
        }
    }

    private func endFallback() {
        guard fallbackTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(fallbackTask)
        fallbackTask = .invalid
    }
}
