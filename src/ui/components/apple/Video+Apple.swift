#if os(macOS) || os(iOS)
import Foundation
import AVFoundation

#if os(macOS)
    import AppKit
    typealias VideoHostBase = NSView
#elseif os(iOS)
    import UIKit
    typealias VideoHostBase = UIView
#endif

/// AVPlayer plays from a URL, not bytes: each video's bytes go to a file once a run.
@MainActor private var videoFiles: [Data: URL] = [:]

@MainActor private func file(for data: Data) -> URL? {
    if let url = videoFiles[data] { return url }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("omni-video-\(ProcessInfo.processInfo.processIdentifier)-\(videoFiles.count).mp4")
    guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
    videoFiles[data] = url
    return url
}

/// A view whose layer is the player's: it draws nothing until the first frame is decoded.
@MainActor final class OmniVideoView: VideoHostBase {
    let player = AVPlayer()
    let playerLayer: AVPlayerLayer
    /// The bytes it plays, so the same again aren't loaded again (every frame of a swipe renders).
    var shown: Data?
    var playback: Video.Playback?
    /// The newest render's: told when the item plays to its end, or `endLead` seconds before.
    var onEnd: (() -> Void)?
    private var endLead = 0.0
    private var natural = CGSize.zero
    private var endObserver: NSObjectProtocol?
    /// The boundary `endLead` before the end, once the duration is known.
    private var leadObserver: Any?
    private var duration: CMTime?

    #if os(iOS)
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    #endif

    init() {
        #if os(iOS)
            playerLayer = AVPlayerLayer()
            super.init(frame: .zero)
            // The view's own layer is the player layer (layerClass).
            (layer as? AVPlayerLayer)?.player = player
            isUserInteractionEnabled = false
        #else
            playerLayer = AVPlayerLayer()
            super.init(frame: .zero)
            // Layer-hosting: the layer is set before wantsLayer.
            layer = playerLayer
            wantsLayer = true
            playerLayer.player = player
        #endif
        translatesAutoresizingMaskIntoConstraints = false
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.preventsDisplaySleepDuringVideoPlayback = false
        #if os(iOS)
            player.allowsExternalPlayback = false
        #endif
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var videoLayer: AVPlayerLayer {
        #if os(iOS)
            return layer as! AVPlayerLayer
        #else
            return playerLayer
        #endif
    }

    func show(_ data: Data) {
        guard shown != data else { return }
        shown = data
        playback = nil
        guard let url = file(for: data) else { player.replaceCurrentItem(with: nil); return }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self, self.endLead == 0 { self.onEnd?() } }
        }
        duration = nil
        arm()
        Task { [weak self] in
            if let length = try? await asset.load(.duration) {
                self?.duration = length
                self?.arm()
            }
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize) else { return }
            self?.natural = size
            self?.invalidateIntrinsicContentSize()
        }
    }

    func lead(_ seconds: Double) {
        guard seconds != endLead else { return }
        endLead = seconds
        arm()
    }

    /// Told `endLead` before the end, each time playing crosses it.
    private func arm() {
        if let leadObserver { player.removeTimeObserver(leadObserver) }
        leadObserver = nil
        guard endLead > 0, let duration, duration.isNumeric else { return }
        let at = CMTimeSubtract(duration, CMTime(seconds: endLead, preferredTimescale: 600))
        guard at > .zero else { return }
        leadObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: at)], queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.onEnd?() }
        }
    }

    func fill(_ fills: Bool) {
        videoLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
    }

    func play(_ next: Video.Playback) {
        guard next != playback else { return }
        playback = next
        switch next {
        case .atStart:
            player.pause()
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        case .playing:
            // At its end it stays on its last frame.
            if let item = player.currentItem, item.duration.isNumeric, item.currentTime() >= item.duration { return }
            player.play()
        case .paused:
            player.pause()
        }
    }

    func stop() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let leadObserver { player.removeTimeObserver(leadObserver) }
        leadObserver = nil
        onEnd = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        shown = nil
        playback = nil
    }

    override var intrinsicContentSize: CGSize {
        #if os(macOS)
            natural == .zero ? CGSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) : natural
        #else
            natural == .zero ? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) : natural
        #endif
    }
}

extension Video {
    @MainActor public func makeNative() -> NativeView {
        let view = OmniVideoView()
        view.show(data)
        return view
    }

    @MainActor public func updateNative(_ view: NativeView) {
        // Resizable: the frame decides the size, as an Image's.
        let hugging: Float = isResizable ? 1 : 250
        let resistance: Float = isResizable ? 1 : 750
        view.setContentHuggingPriority(.init(rawValue: hugging), for: .horizontal)
        view.setContentHuggingPriority(.init(rawValue: hugging), for: .vertical)
        view.setContentCompressionResistancePriority(.init(rawValue: resistance), for: .horizontal)
        view.setContentCompressionResistancePriority(.init(rawValue: resistance), for: .vertical)

        guard let video = view as? OmniVideoView else { return }
        video.show(data)
        video.onEnd = onEnd
        video.lead(endLead)
        video.fill(isResizable && contentMode == .fill)
        video.play(playback)
    }

    @MainActor public func unmountNative(_ view: NativeView) {
        (view as? OmniVideoView)?.stop()
    }
}
#endif
