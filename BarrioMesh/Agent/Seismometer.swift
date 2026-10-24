import CoreMotion
import Foundation

/// Feeds the accelerometer into `SeismicDetector` at 50 Hz while the app is open.
@MainActor
final class Seismometer {
    var onShaking: ((SeismicEvent) -> Void)?

    private let motion = CMMotionManager()
    private var detector = SeismicDetector()

    var isAvailable: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            if let event = self.detector.ingest(time: data.timestamp, x: a.x, y: a.y, z: a.z) {
                self.onShaking?(event)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
