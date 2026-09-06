import Foundation

@MainActor
final class StreamingUpdateCoalescer<Value: Sendable> {
    typealias Delivery = @MainActor (Value) -> Void

    private let interval: Duration
    private let delivery: Delivery
    private var pendingValue: Value?
    private var deliveryTask: Task<Void, Never>?

    init(
        interval: Duration = .milliseconds(50),
        delivery: @escaping Delivery
    ) {
        self.interval = interval
        self.delivery = delivery
    }

    func submit(_ value: Value) {
        pendingValue = value

        guard deliveryTask == nil else { return }

        deliveryTask = Task { [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.deliverPendingValue()
        }
    }

    func flush() {
        deliveryTask?.cancel()
        deliveryTask = nil
        deliverPendingValue()
    }

    func cancel() {
        deliveryTask?.cancel()
        deliveryTask = nil
        pendingValue = nil
    }

    private func deliverPendingValue() {
        deliveryTask = nil
        guard let pendingValue else { return }

        self.pendingValue = nil
        delivery(pendingValue)
    }
}
