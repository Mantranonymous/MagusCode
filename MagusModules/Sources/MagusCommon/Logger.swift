import os

public enum MagusLogger {
    private static let subsystem = "com.magus.app"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let core = Logger(subsystem: subsystem, category: "core")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let perception = Logger(subsystem: subsystem, category: "perception")
    public static let decision = Logger(subsystem: subsystem, category: "decision")
    public static let execution = Logger(subsystem: subsystem, category: "execution")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
