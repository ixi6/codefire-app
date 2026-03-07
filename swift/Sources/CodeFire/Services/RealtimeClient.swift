import Foundation

/// Lightweight Supabase Realtime client using native WebSocket.
/// Implements the Phoenix Channel protocol for postgres_changes subscriptions.
class RealtimeClient: NSObject, URLSessionWebSocketDelegate {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
    }

    struct Change {
        let table: String
        let type: ChangeType
        let record: [String: Any]?
        let oldRecord: [String: Any]?

        enum ChangeType: String {
            case insert = "INSERT"
            case update = "UPDATE"
            case delete = "DELETE"
        }
    }

    typealias ChangeHandler = (Change) -> Void
    typealias PresenceHandler = ([String: PresenceEntry]) -> Void

    struct PresenceEntry {
        let userId: String
        let displayName: String
        let status: String  // "active", "idle"
        let activeFile: String?
        let gitBranch: String?
    }

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTimer: Timer?
    private var reconnectTimer: Timer?
    private var ref: Int = 0
    private var joinedChannels: Set<String> = []

    private let supabaseUrl: String
    private let anonKey: String
    private var accessToken: String?
    private var subscriptions: [(schema: String, table: String, handler: ChangeHandler)] = []
    private var presenceHandlers: [String: PresenceHandler] = [:]  // channel -> handler
    private var presenceState: [String: [String: PresenceEntry]] = [:]  // channel -> {key: entry}
    private var presenceUserStates: [String: [String: Any]] = [:]  // channel -> user state for rejoin

    private(set) var state: ConnectionState = .disconnected
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    var onStateChange: ((ConnectionState) -> Void)?

    init(supabaseUrl: String, anonKey: String) {
        self.supabaseUrl = supabaseUrl
        self.anonKey = anonKey
        super.init()
    }

    // MARK: - Public API

    /// Connect to Supabase Realtime WebSocket.
    func connect(accessToken: String?) {
        self.accessToken = accessToken
        guard state == .disconnected || state == .reconnecting else { return }

        state = .connecting
        onStateChange?(.connecting)

        let wsUrl = supabaseUrl
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let urlString = "\(wsUrl)/realtime/v1/websocket?apikey=\(anonKey)&vsn=1.0.0"

        guard let url = URL(string: urlString) else {
            print("RealtimeClient: invalid URL")
            return
        }

        var request = URLRequest(url: url)
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()
        startHeartbeat()
    }

    /// Disconnect and clean up.
    func disconnect() {
        state = .disconnected
        onStateChange?(.disconnected)
        stopHeartbeat()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        joinedChannels.removeAll()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
        reconnectAttempts = 0
    }

    /// Subscribe to postgres_changes on a table.
    func subscribe(schema: String = "public", table: String, handler: @escaping ChangeHandler) {
        subscriptions.append((schema: schema, table: table, handler: handler))

        // If already connected, join the channel immediately
        if state == .connected {
            joinChannel(schema: schema, table: table)
        }
    }

    /// Remove all subscriptions and leave channels.
    func unsubscribeAll() {
        for topic in joinedChannels {
            leaveChannel(topic: topic)
        }
        subscriptions.removeAll()
        joinedChannels.removeAll()
    }

    // MARK: - Presence API

    /// Join a presence channel and track this user's state.
    func joinPresence(channel: String, userState: [String: Any], handler: @escaping PresenceHandler) {
        presenceHandlers[channel] = handler
        presenceUserStates[channel] = userState
        presenceState[channel] = [:]

        if state == .connected {
            joinPresenceChannel(channel: channel, userState: userState)
        }
    }

    /// Update presence state (e.g., active file changed).
    func updatePresence(channel: String, userState: [String: Any]) {
        guard state == .connected else { return }
        let topic = "realtime:\(channel)"
        let message: [String: Any] = [
            "topic": topic,
            "event": "presence",
            "payload": ["type": "track", "event": "track", "payload": userState],
            "ref": nextRef(),
        ]
        sendJSON(message)
    }

    /// Leave a presence channel.
    func leavePresence(channel: String) {
        let topic = "realtime:\(channel)"
        leaveChannel(topic: topic)
        presenceHandlers.removeValue(forKey: channel)
        presenceState.removeValue(forKey: channel)
    }

    private func joinPresenceChannel(channel: String, userState: [String: Any]) {
        let topic = "realtime:\(channel)"
        guard !joinedChannels.contains(topic) else { return }

        let token = accessToken ?? anonKey

        let payload: [String: Any] = [
            "config": [
                "presence": ["key": ""]
            ],
            "access_token": token,
        ]

        let joinMsg: [String: Any] = [
            "topic": topic,
            "event": "phx_join",
            "payload": payload,
            "ref": nextRef(),
        ]
        sendJSON(joinMsg)
        joinedChannels.insert(topic)

        // Track our presence after a short delay to ensure join completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updatePresence(channel: channel, userState: userState)
        }
    }

    // MARK: - Phoenix Channel Protocol

    private func nextRef() -> String {
        ref += 1
        return "\(ref)"
    }

    private func joinChannel(schema: String, table: String) {
        let topic = "realtime:public:\(table)"
        guard !joinedChannels.contains(topic) else { return }

        let token = accessToken ?? anonKey

        let payload: [String: Any] = [
            "config": [
                "postgres_changes": [
                    [
                        "event": "*",
                        "schema": schema,
                        "table": table,
                    ]
                ]
            ],
            "access_token": token,
        ]

        let message: [String: Any] = [
            "topic": topic,
            "event": "phx_join",
            "payload": payload,
            "ref": nextRef(),
        ]

        sendJSON(message)
        joinedChannels.insert(topic)
    }

    private func leaveChannel(topic: String) {
        let message: [String: Any] = [
            "topic": topic,
            "event": "phx_leave",
            "payload": [:] as [String: Any],
            "ref": nextRef(),
        ]
        sendJSON(message)
    }

    private func sendHeartbeat() {
        let message: [String: Any] = [
            "topic": "phoenix",
            "event": "heartbeat",
            "payload": [:] as [String: Any],
            "ref": nextRef(),
        ]
        sendJSON(message)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(str)) { error in
            if let error {
                print("RealtimeClient: send error: \(error)")
            }
        }
    }

    // MARK: - Receive Loop

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue receiving
                self.receiveMessage()

            case .failure(let error):
                print("RealtimeClient: receive error: \(error)")
                self.handleDisconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let event = json["event"] as? String ?? ""

        switch event {
        case "phx_reply":
            // Channel join confirmation
            if let payload = json["payload"] as? [String: Any],
               let status = payload["status"] as? String {
                if status == "ok" && state == .connecting {
                    state = .connected
                    onStateChange?(.connected)
                    reconnectAttempts = 0
                }
            }

        case "postgres_changes":
            // Database change event
            if let payload = json["payload"] as? [String: Any],
               let payloadData = payload["data"] as? [String: Any] {
                handlePostgresChange(payloadData)
            }

        case "presence_state":
            handlePresenceState(json)

        case "presence_diff":
            handlePresenceDiff(json)

        case "phx_error":
            print("RealtimeClient: channel error: \(json)")

        case "phx_close":
            handleDisconnect()

        default:
            break
        }
    }

    private func handlePostgresChange(_ data: [String: Any]) {
        guard let table = data["table"] as? String,
              let typeStr = data["type"] as? String,
              let changeType = Change.ChangeType(rawValue: typeStr) else { return }

        let record = data["record"] as? [String: Any]
        let oldRecord = data["old_record"] as? [String: Any]

        let change = Change(table: table, type: changeType, record: record, oldRecord: oldRecord)

        // Dispatch to matching subscribers
        for sub in subscriptions where sub.table == table {
            sub.handler(change)
        }
    }

    // MARK: - Presence Handling

    private func handlePresenceState(_ json: [String: Any]) {
        guard let topic = json["topic"] as? String,
              let payload = json["payload"] as? [String: Any] else { return }

        let channel = topic.replacingOccurrences(of: "realtime:", with: "")
        var entries: [String: PresenceEntry] = [:]

        for (key, value) in payload {
            if let metas = (value as? [String: Any])?["metas"] as? [[String: Any]],
               let meta = metas.first,
               let entry = parsePresenceEntry(key: key, meta: meta) {
                entries[key] = entry
            }
        }

        presenceState[channel] = entries
        presenceHandlers[channel]?(entries)
    }

    private func handlePresenceDiff(_ json: [String: Any]) {
        guard let topic = json["topic"] as? String,
              let payload = json["payload"] as? [String: Any] else { return }

        let channel = topic.replacingOccurrences(of: "realtime:", with: "")
        var current = presenceState[channel] ?? [:]

        // Process joins
        if let joins = payload["joins"] as? [String: Any] {
            for (key, value) in joins {
                if let metas = (value as? [String: Any])?["metas"] as? [[String: Any]],
                   let meta = metas.first,
                   let entry = parsePresenceEntry(key: key, meta: meta) {
                    current[key] = entry
                }
            }
        }

        // Process leaves
        if let leaves = payload["leaves"] as? [String: Any] {
            for (key, _) in leaves {
                current.removeValue(forKey: key)
            }
        }

        presenceState[channel] = current
        presenceHandlers[channel]?(current)
    }

    private func parsePresenceEntry(key: String, meta: [String: Any]) -> PresenceEntry? {
        let userId = meta["user_id"] as? String ?? key
        let displayName = meta["display_name"] as? String ?? "Unknown"
        let status = meta["status"] as? String ?? "active"
        let activeFile = meta["active_file"] as? String
        let gitBranch = meta["git_branch"] as? String
        return PresenceEntry(userId: userId, displayName: displayName, status: status, activeFile: activeFile, gitBranch: gitBranch)
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        guard state != .disconnected else { return }
        state = .reconnecting
        onStateChange?(.reconnecting)
        stopHeartbeat()
        joinedChannels.removeAll()

        guard reconnectAttempts < maxReconnectAttempts else {
            print("RealtimeClient: max reconnect attempts reached")
            disconnect()
            return
        }

        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0) // Exponential backoff, max 30s

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.state == .reconnecting else { return }
            print("RealtimeClient: reconnecting (attempt \(self.reconnectAttempts))")
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            self.connect(accessToken: self.accessToken)
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("RealtimeClient: connected")
        state = .connected
        onStateChange?(.connected)
        reconnectAttempts = 0

        // Join all subscribed channels
        for sub in subscriptions {
            joinChannel(schema: sub.schema, table: sub.table)
        }

        // Rejoin presence channels
        for (channel, userState) in presenceUserStates {
            if presenceHandlers[channel] != nil {
                joinPresenceChannel(channel: channel, userState: userState)
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("RealtimeClient: closed with code \(closeCode)")
        handleDisconnect()
    }
}
