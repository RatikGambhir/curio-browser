import UIKit

#if DEBUG
extension BrowserViewController {
    /// Debug builds can be driven from the environment for screenshots and
    /// UI checks:
    /// - `CURIO_DEBUG_URL` opens a page.
    /// - `CURIO_DEBUG_COMMANDS` runs comma-separated steps: command names
    ///   (e.g. `ToggleAiPanel`), or `Fold` / `Unfold`, which switch the
    ///   width class the way folding and unfolding a foldable phone does.
    /// - `CURIO_DEBUG_STEP` sets the seconds between steps (default 0.9).
    func runDebugLaunchActions() {
        let environment = ProcessInfo.processInfo.environment
        let url = environment["CURIO_DEBUG_URL"]
        let steps = (environment["CURIO_DEBUG_COMMANDS"] ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let delay = Double(environment["CURIO_DEBUG_STEP"] ?? "") ?? 0.9
        guard url != nil || !steps.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return }
            closeCommandBar()
            if let url { session.open(url, newTab: true) }
            for step in steps {
                try? await Task.sleep(for: .seconds(delay))
                runDebugStep(step)
            }
        }
    }

    private func runDebugStep(_ step: String) {
        switch step {
        case "Fold":
            // Goes through the same trait-change path as a real fold.
            traitOverrides.horizontalSizeClass = .compact
        case "Unfold":
            traitOverrides.remove(UITraitHorizontalSizeClass.self)
        default:
            if let command = CurioCommand(rawValue: "curio::\(step)") { perform(command) }
        }
    }
}
#endif
