import AVFoundation
import Vision

/// Reads a video at 8 frames a second and finds the person's wrists in each frame with Vision,
/// on the phone. Clips longer than two minutes are cut at two minutes.
nonisolated enum PoseExtractor {
    static let framesPerSecond = 8.0
    static let maxSeconds = 120.0

    static func samples(from url: URL) async throws -> [PoseSample] {
        let asset = AVURLAsset(url: url)
        let duration = min(try await asset.load(.duration).seconds, maxSeconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        var out: [PoseSample] = []
        var t = 0.0
        while t < duration {
            try Task.checkCancellation()
            let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            out.append(PoseSample(time: t, hands: try hands(in: image)))
            t += 1 / framesPerSecond
        }
        return out
    }

    static func hands(in image: CGImage) throws -> CGPoint? {
        let request = VNDetectHumanBodyPoseRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        // The most confident person is the lifter in nearly every gym clip.
        guard let body = request.results?.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let wrists = [VNHumanBodyPoseObservation.JointName.leftWrist, .rightWrist]
            .compactMap { try? body.recognizedPoint($0) }.filter { $0.confidence > 0.3 }.map(\.location)
        guard !wrists.isEmpty else { return nil }
        return CGPoint(x: wrists.map(\.x).reduce(0, +) / CGFloat(wrists.count), y: wrists.map(\.y).reduce(0, +) / CGFloat(wrists.count))
    }
}
