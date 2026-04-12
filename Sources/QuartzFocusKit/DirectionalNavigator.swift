import Foundation

private struct NavigationScore: Comparable {
    let edgeGap: CGFloat
    let orthogonalOffset: CGFloat
    let centerDistance: CGFloat

    static func < (lhs: NavigationScore, rhs: NavigationScore) -> Bool {
        if lhs.edgeGap != rhs.edgeGap {
            return lhs.edgeGap < rhs.edgeGap
        }

        if lhs.orthogonalOffset != rhs.orthogonalOffset {
            return lhs.orthogonalOffset < rhs.orthogonalOffset
        }

        return lhs.centerDistance < rhs.centerDistance
    }
}

final class DirectionalNavigator {
    func target(from current: WindowCandidate, candidates: [WindowCandidate], direction: Direction)
        -> WindowCandidate?
    {
        var bestCandidate: WindowCandidate?
        var bestScore: NavigationScore?

        for candidate in candidates where !candidate.matches(current) {
            guard let score = score(from: current.frame, to: candidate.frame, direction: direction)
            else {
                continue
            }

            if let bestScore {
                guard score < bestScore else {
                    continue
                }
            }

            bestCandidate = candidate
            bestScore = score
        }

        return bestCandidate
    }

    private func score(from currentFrame: CGRect, to candidateFrame: CGRect, direction: Direction)
        -> NavigationScore?
    {
        let deltaX = candidateFrame.center.x - currentFrame.center.x
        let deltaY = candidateFrame.center.y - currentFrame.center.y

        let orthogonalOffset: CGFloat

        switch direction {
        case .left:
            guard deltaX < -1 else { return nil }
            orthogonalOffset = abs(deltaY)
        case .right:
            guard deltaX > 1 else { return nil }
            orthogonalOffset = abs(deltaY)
        case .down:
            guard deltaY > 1 else { return nil }
            orthogonalOffset = abs(deltaX)
        case .up:
            guard deltaY < -1 else { return nil }
            orthogonalOffset = abs(deltaX)
        }

        return NavigationScore(
            edgeGap: directionalEdgeGap(
                from: currentFrame, to: candidateFrame, direction: direction),
            orthogonalOffset: orthogonalOffset,
            centerDistance: hypot(deltaX, deltaY)
        )
    }

    private func directionalEdgeGap(
        from currentFrame: CGRect, to candidateFrame: CGRect, direction: Direction
    ) -> CGFloat {
        switch direction {
        case .left:
            return max(0, currentFrame.minX - candidateFrame.maxX)
        case .right:
            return max(0, candidateFrame.minX - currentFrame.maxX)
        case .down:
            return max(0, candidateFrame.minY - currentFrame.maxY)
        case .up:
            return max(0, currentFrame.minY - candidateFrame.maxY)
        }
    }
}
