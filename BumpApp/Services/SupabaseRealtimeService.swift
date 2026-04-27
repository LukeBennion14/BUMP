import Foundation

final class SupabaseRealtimeService {
    static let shared = SupabaseRealtimeService()

    private var webSocketTask: URLSessionWebSocketTask?
    private var listenTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var joinRef = 1
    private var messageRef = 1
    private var isConnected = false
    private var watchedTables: [String] = []

    private init() {}

    func connect(
        websocketURL: URL,
        accessToken: String?,
        tables: [String],
        onDatabaseChange: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        guard !tables.isEmpty else { return }
        if isConnected, watchedTables == tables {
            return
        }

        disconnect()

        watchedTables = tables
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: websocketURL)
        webSocketTask = task
        task.resume()
        isConnected = true

        if let accessToken {
            send(
                topic: "phoenix",
                event: "access_token",
                payload: ["access_token": accessToken]
            )
        }

        for table in tables {
            let topic = "realtime:public:\(table)"
            let payload: [String: Any] = [
                "config": [
                    "broadcast": ["self": false],
                    "presence": ["key": ""],
                    "postgres_changes": [
                        [
                            "event": "*",
                            "schema": "public",
                            "table": table
                        ]
                    ]
                ]
            ]
            send(topic: topic, event: "phx_join", payload: payload)
        }

        listenTask = Task {
            await listenLoop(onDatabaseChange: onDatabaseChange, onError: onError)
        }
        heartbeatTask = Task {
            await heartbeatLoop()
        }
    }

    func disconnect() {
        isConnected = false
        listenedCancel()
        heartbeatTask?.cancel()
        heartbeatTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        watchedTables = []
    }

    private func listenedCancel() {
        listenTask?.cancel()
        listenTask = nil
    }

    private func listenLoop(
        onDatabaseChange: @escaping @Sendable () -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async {
        while isConnected, let socket = webSocketTask {
            do {
                let message = try await socket.receive()
                switch message {
                case let .string(text):
                    handleIncoming(text: text, onDatabaseChange: onDatabaseChange)
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleIncoming(text: text, onDatabaseChange: onDatabaseChange)
                    }
                @unknown default:
                    break
                }
            } catch {
                onError("Realtime connection interrupted: \(error.localizedDescription)")
                break
            }
        }
        disconnect()
    }

    private func heartbeatLoop() async {
        while isConnected {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard isConnected else { return }
            send(topic: "phoenix", event: "heartbeat", payload: [:])
        }
    }

    private func handleIncoming(text: String, onDatabaseChange: @escaping @Sendable () -> Void) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String
        else {
            return
        }

        if event == "postgres_changes" {
            onDatabaseChange()
        }
    }

    private func send(topic: String, event: String, payload: [String: Any]) {
        guard let webSocketTask else { return }
        let message: [String: Any] = [
            "topic": topic,
            "event": event,
            "payload": payload,
            "ref": "\(messageRef)",
            "join_ref": "\(joinRef)"
        ]
        messageRef += 1
        if event == "phx_join" {
            joinRef += 1
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let text = String(data: data, encoding: .utf8)
        else {
            return
        }

        webSocketTask.send(.string(text)) { _ in }
    }
}
