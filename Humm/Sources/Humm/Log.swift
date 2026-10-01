import os

/// View with: /usr/bin/log stream --predicate 'subsystem == "com.kyser.humm"'
/// Never log the API key or transcript text.
enum Log {
    static let app = Logger(subsystem: "com.kyser.humm", category: "app")
    static let input = Logger(subsystem: "com.kyser.humm", category: "input")
    static let net = Logger(subsystem: "com.kyser.humm", category: "transcribe")
}
