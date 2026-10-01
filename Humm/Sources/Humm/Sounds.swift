import AppKit

/// Short system sounds: start listening, stop listening, failure, a word learned.
@MainActor
enum Sounds {
    enum Cue { case start, stop, failure, learned }

    private static let start = load("Tink", volume: 0.6)
    private static let stop = load("Pop", volume: 0.6)
    private static let failure = load("Funk", volume: 0.4)
    private static let learned = load("Glass", volume: 0.35)

    static func play(_ cue: Cue) {
        let sound: NSSound? = switch cue {
        case .start: start
        case .stop: stop
        case .failure: failure
        case .learned: learned
        }
        sound?.stop()
        sound?.play()
    }

    private static func load(_ name: String, volume: Float) -> NSSound? {
        let sound = NSSound(named: NSSound.Name(name))
        sound?.volume = volume
        return sound
    }
}
