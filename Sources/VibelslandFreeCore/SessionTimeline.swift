import Foundation

package enum SessionResolutionState: Equatable {
    case active
    case completed
    case failed
}

package struct SessionTimeline: Equatable {
    package private(set) var events: [AgentEvent]

    package init(events: [AgentEvent] = []) {
        self.events = events.sorted { $0.timestamp < $1.timestamp }
    }

    package var latestEvent: AgentEvent? {
        events.last
    }

    package var status: SessionStatus {
        SessionStateReducer.status(for: events)
    }

    package var resolutionState: SessionResolutionState {
        SessionStateReducer.resolutionState(for: events)
    }

    package mutating func append(_ event: AgentEvent) {
        if let last = events.last, last.timestamp <= event.timestamp {
            events.append(event)
        } else {
            events.append(event)
            events.sort { $0.timestamp < $1.timestamp }
        }
    }
}

package enum SessionStateReducer {
    package static func status(for timeline: SessionTimeline) -> SessionStatus {
        status(for: timeline.events)
    }

    package static func status(for events: [AgentEvent]) -> SessionStatus {
        events
            .sorted { $0.timestamp < $1.timestamp }
            .reduce(.idle) { status(after: $0, event: $1) }
    }

    package static func status(after current: SessionStatus, event: AgentEvent) -> SessionStatus {
        let next = SessionStatusResolver.status(for: event)
        if SessionStatusResolver.shouldPreserveDoneStatus(current: current, next: next, event: event) {
            return current
        }
        return next
    }

    package static func shouldApplyTranscriptCompletion(_ transcript: AgentTranscriptSnapshot, to event: AgentEvent) -> Bool {
        guard transcript.isComplete else {
            return false
        }
        guard SessionStatusResolver.status(for: event) != .failed else {
            return false
        }

        if let latestActiveAt = transcript.latestActiveAt,
           let completedAt = transcript.completedAt,
           latestActiveAt > completedAt {
            return false
        }

        guard let completedAt = transcript.completedAt else {
            return !SessionStatusResolver.isNewWorkStart(event)
        }

        if SessionStatusResolver.isNewWorkStart(event),
           completedAt < event.timestamp {
            return false
        }
        return true
    }

    package static func shouldApplyTranscriptContent(_ transcript: AgentTranscriptSnapshot, to event: AgentEvent) -> Bool {
        guard SessionStatusResolver.isNewWorkStart(event) else {
            return true
        }

        let eventTitle = EventParser.title(for: event)
        if let lastUserMessage = transcript.lastUserMessage,
           !lastUserMessage.isEmpty,
           lastUserMessage == eventTitle {
            return true
        }

        let newestTranscriptAt = [transcript.completedAt, transcript.latestActiveAt].compactMap { $0 }.max()
        guard let newestTranscriptAt else {
            return false
        }

        if let completedAt = transcript.completedAt,
           completedAt < event.timestamp,
           transcript.latestActiveAt.map({ $0 <= completedAt }) ?? true {
            return false
        }

        return newestTranscriptAt >= event.timestamp.addingTimeInterval(-2)
    }

    package static func resolutionState(for events: [AgentEvent]) -> SessionResolutionState {
        switch status(for: events) {
        case .done:
            return .completed
        case .failed:
            return .failed
        case .idle, .thinking, .runningTool, .waitingApproval, .waitingQuestion:
            return .active
        }
    }
}
