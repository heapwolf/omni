import Foundation

/// A silent video from bytes in memory (an MP4: H.264 plays everywhere), drawn like an `Image`:
/// its own size, or `.resizable()` and fitted or filled to its frame. No controls and no
/// sound: a moving picture, as behind an intro, not a player. Until its first frame is decoded
/// it draws nothing, so put a still of that frame under it.
///
/// iOS and macOS (AVPlayer), Android (MediaPlayer on a TextureView, so it fades and moves with
/// everything else). Linux draws nothing.
public struct Video: NativeComponent {
    /// What the video is doing. Set the same again, nothing changes.
    public enum Playback: Sendable, Equatable {
        /// Still, at its first frame.
        case atStart
        /// Playing on from where it is to its end, then still at its last frame.
        case playing
        /// Still, at the frame it shows.
        case paused
    }

    public var data: Data
    public var playback: Playback

    public init(data: Data, playback: Playback = .playing) {
        self.data = data
        self.playback = playback
    }

    /// Told when it has played to its end (not when it's set back to the start or paused), or
    /// `endLead` seconds before, so what follows can start while its last moments play.
    public var onEnd: (() -> Void)?
    public var endLead = 0.0

    /// `action` once it has played to its end, or `lead` seconds before it.
    public func onEnd(before lead: Double = 0, _ action: @escaping () -> Void) -> Video {
        var copy = self; copy.onEnd = action; copy.endLead = max(lead, 0); return copy
    }

    /// Off: the video is its own size.
    public var isResizable = false
    public var contentMode: Image.ContentMode = .fit

    /// The video takes whatever size its frame gives it.
    public func resizable() -> Video {
        var copy = self; copy.isResizable = true; return copy
    }

    public func scaledToFit() -> Video {
        var copy = self; copy.contentMode = .fit; return copy
    }

    /// Fills the frame; the overflow is not cropped until .clipped(), as with an Image.
    public func scaledToFill() -> Video {
        var copy = self; copy.contentMode = .fill; return copy
    }
}
