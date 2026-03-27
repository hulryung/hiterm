import AppKit

/// Tracks two-finger horizontal swipe gestures on trackpad for tab switching.
/// Inspired by iTerm2's iTermSwipeTracker: uses scrollWheel events with
/// direction lock and momentum-based animation.
protocol SwipeTrackerDelegate: AnyObject {
    var swipeTabCount: Int { get }
    var swipeCurrentIndex: Int { get }
    var swipeTabWidth: CGFloat { get }
    func swipeBeganSession()
    func swipeSetOffset(_ offset: CGFloat)
    func swipeEndSession(targetIndex: Int)
    func swipeCancelSession()
}

class SwipeTracker {
    weak var delegate: SwipeTrackerDelegate?

    // Direction lock state
    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0
    private var directionLocked = false
    private var isHorizontal = false
    private var isTracking = false
    private var isAnimating = false

    // Swipe state
    private var rawOffset: CGFloat = 0
    private var momentum: CGFloat = 0
    private var momentumTimer: Timer?
    private var animatingTargetIndex: Int = 0

    // Thresholds (matching iTerm2)
    private let directionThreshold: CGFloat = 10
    private let slopeThreshold: CGFloat = 0.4
    private let snapMomentumThreshold: CGFloat = 3

    /// Returns true if the event was handled (horizontal swipe).
    func handleEvent(_ event: NSEvent) -> Bool {
        guard event.hasPreciseScrollingDeltas else { return false }

        // New gesture began.
        if event.phase == .began {
            if isAnimating {
                // Interrupt animation: commit current target immediately, start new session.
                let targetIndex = animatingTargetIndex
                stopMomentum()
                delegate?.swipeEndSession(targetIndex: targetIndex)
                isTracking = false
                isAnimating = false
            }

            accumX = 0
            accumY = 0
            directionLocked = false
            isHorizontal = false
            rawOffset = 0
            momentum = 0
        }

        // Direction detection.
        if !directionLocked {
            accumX += abs(event.scrollingDeltaX)
            accumY += abs(event.scrollingDeltaY)

            if accumX + accumY >= directionThreshold {
                directionLocked = true
                if accumY > slopeThreshold * (accumX + accumY) {
                    isHorizontal = false
                    return false
                } else {
                    isHorizontal = true
                    isTracking = true
                    delegate?.swipeBeganSession()
                }
            } else {
                return true
            }
        }

        guard isHorizontal else { return false }

        // Active dragging.
        if event.phase == .changed || event.phase == .began {
            let delta = event.scrollingDeltaX
            rawOffset += delta
            momentum = delta
            delegate?.swipeSetOffset(squash(rawOffset))
        }

        // Gesture ended.
        if event.phase == .ended || event.phase == .cancelled {
            startMomentum()
        }

        return true
    }

    // MARK: - Momentum

    private func startMomentum() {
        guard let delegate else { cancelTracking(); return }

        let width = delegate.swipeTabWidth
        guard width > 0 else { cancelTracking(); return }

        let currentIndex = delegate.swipeCurrentIndex
        let count = delegate.swipeTabCount

        var targetIndex = currentIndex
        if momentum > snapMomentumThreshold && currentIndex > 0 {
            targetIndex = currentIndex - 1
        } else if momentum < -snapMomentumThreshold && currentIndex < count - 1 {
            targetIndex = currentIndex + 1
        } else {
            let normalizedOffset = rawOffset / width
            if normalizedOffset > 0.3 && currentIndex > 0 {
                targetIndex = currentIndex - 1
            } else if normalizedOffset < -0.3 && currentIndex < count - 1 {
                targetIndex = currentIndex + 1
            }
        }

        let targetOffset = CGFloat(currentIndex - targetIndex) * width
        animateToOffset(targetOffset, targetIndex: targetIndex)
    }

    private func animateToOffset(_ targetOffset: CGFloat, targetIndex: Int) {
        stopMomentum()
        isAnimating = true
        animatingTargetIndex = targetIndex

        momentumTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }

            let distance = targetOffset - self.rawOffset
            if abs(distance) < 1.0 {
                self.rawOffset = targetOffset
                self.delegate?.swipeSetOffset(self.squash(self.rawOffset))
                self.finishTracking(targetIndex: targetIndex)
                return
            }

            self.rawOffset += distance * 0.15
            self.delegate?.swipeSetOffset(self.squash(self.rawOffset))
        }
    }

    private func finishTracking(targetIndex: Int) {
        stopMomentum()
        isTracking = false
        isAnimating = false
        directionLocked = false
        delegate?.swipeEndSession(targetIndex: targetIndex)
    }

    private func cancelTracking() {
        stopMomentum()
        isTracking = false
        isAnimating = false
        directionLocked = false
        delegate?.swipeCancelSession()
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        isAnimating = false
    }

    // MARK: - Squash (elastic boundary)

    private func squash(_ x: CGFloat) -> CGFloat {
        guard let delegate else { return x }
        let width = delegate.swipeTabWidth
        let count = delegate.swipeTabCount
        let currentIndex = delegate.swipeCurrentIndex
        let maxWiggle = width * 0.15

        let upperBound = CGFloat(currentIndex) * width
        let lowerBound = -CGFloat(count - 1 - currentIndex) * width

        if x > upperBound {
            return upperBound + maxWiggle * (1.0 - exp(-(x - upperBound) / maxWiggle))
        } else if x < lowerBound {
            let overshoot = lowerBound - x
            return lowerBound - maxWiggle * (1.0 - exp(-overshoot / maxWiggle))
        }
        return x
    }
}
