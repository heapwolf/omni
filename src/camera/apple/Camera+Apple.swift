
#if os(iOS)
import Foundation
import AVFoundation
import UIKit
import UniformTypeIdentifiers

func makePlatformCamera() -> any CameraCapture { AppleCamera() }

public struct AppleCamera: CameraCapture {
    public init() {}

    public var authorization: CameraAuthorization {
        get async { Self.map(AVCaptureDevice.authorizationStatus(for: .video)) }
    }

    public func requestAuthorization() async -> CameraAuthorization {
        let current = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        // Only .notDetermined can be moved by asking; request on a denied status
        // returns false without re-prompting.
        guard current == .notDetermined else { return current }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .authorized : .denied
    }

    public func capture(_ options: CaptureOptions) async throws -> CapturedImage {
        let state = await requestAuthorization()
        guard state == .authorized else { throw CameraError.notAuthorized(state) }
        // Trailing closure, not MainActor.run({ ... }): run(resultType:body:) has a
        // defaulted first parameter that a parenthesised closure matches instead.
        guard await MainActor.run(body: { UIImagePickerController.isSourceTypeAvailable(.camera) }) else {
            throw CameraError.noCameraAvailable
        }
        return try await present(source: .camera, options: options)
    }

    public func pickImage() async throws -> CapturedImage {
        // The library needs no camera permission: the picker runs out of process.
        try await present(source: .photoLibrary, options: CaptureOptions())
    }

    @MainActor
    private func present(source: UIImagePickerController.SourceType,
                         options: CaptureOptions) async throws -> CapturedImage {
        guard let presenter = Self.topViewController() else {
            throw CameraError.platform("No window to present from.")
        }

        let picker = UIImagePickerController()
        picker.sourceType = source
        if source == .camera {
            picker.cameraDevice = options.facing == .front ? .front : .rear
        }

        return try await withCheckedThrowingContinuation { continuation in
            let coordinator = PickerCoordinator(options: options) { result in
                presenter.dismiss(animated: true)
                continuation.resume(with: result)
            }
            // UIKit holds the delegate unowned.
            picker.delegate = coordinator
            objc_setAssociatedObject(picker, &PickerCoordinator.associationKey,
                                     coordinator, .OBJC_ASSOCIATION_RETAIN)
            presenter.present(picker, animated: true)
        }
    }

    /// The topmost presented controller, so capture presents above an existing
    /// sheet rather than failing behind it.
    @MainActor
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first

        guard var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
                ?? scene?.windows.first?.rootViewController else { return nil }

        while let presented = top.presentedViewController { top = presented }
        return top
    }

    private static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }
}

// MARK: - Delegate bridge

private final class PickerCoordinator: NSObject, UIImagePickerControllerDelegate,
                                       UINavigationControllerDelegate {
    nonisolated(unsafe) static var associationKey: UInt8 = 0

    private let options: CaptureOptions
    private var finish: ((Result<CapturedImage, Error>) -> Void)?

    init(options: CaptureOptions, finish: @escaping (Result<CapturedImage, Error>) -> Void) {
        self.options = options
        self.finish = finish
    }

    /// Resumes exactly once: the picker can deliver both a selection and a
    /// dismissal.
    private func complete(_ result: Result<CapturedImage, Error>) {
        guard let finish else { return }
        self.finish = nil
        finish(result)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        guard let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage) else {
            complete(.failure(CameraError.platform("The picker returned no image.")))
            return
        }
        do { complete(.success(try AppleImageEncoder.encode(image, options: options))) }
        catch { complete(.failure(error)) }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        complete(.failure(CameraError.cancelled))
    }
}

// MARK: - Resizing and encoding

enum AppleImageEncoder {
    static func encode(_ image: UIImage, options: CaptureOptions) throws -> CapturedImage {
        let resized = resize(image, options: options)
        let size = resized.size
        let width = Int(size.width * resized.scale)
        let height = Int(size.height * resized.scale)

        let data: Data?
        switch options.format {
        case .jpeg: data = resized.jpegData(compressionQuality: options.quality)
        case .png: data = resized.pngData()
        case .heic: data = heicData(resized, quality: options.quality)
                        ?? resized.jpegData(compressionQuality: options.quality)
        }

        guard let data else { throw CameraError.platform("Could not encode the image.") }
        return CapturedImage(data: data, format: options.format, width: width, height: height)
    }

    /// Scales to CaptureOptions.targetSize. The arithmetic is shared so every
    /// backend crops identically.
    private static func resize(_ image: UIImage, options: CaptureOptions) -> UIImage {
        let source = (width: Int(image.size.width * image.scale),
                      height: Int(image.size.height * image.scale))
        let target = options.targetSize(for: source)
        guard target.width != source.width || target.height != source.height else { return image }

        let size = CGSize(width: target.width, height: target.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // target is already in pixels
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func heicData(_ image: UIImage, quality: Double) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
#elseif os(macOS)
import Foundation
@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func makePlatformCamera() -> any CameraCapture { MacCamera() }

public struct MacCamera: CameraCapture {
    public init() {}

    public var authorization: CameraAuthorization {
        get async { Self.map(AVCaptureDevice.authorizationStatus(for: .video)) }
    }

    public func requestAuthorization() async -> CameraAuthorization {
        let current = await authorization
        guard current == .notDetermined else { return current }
        return await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
    }

    public func capture(_ options: CaptureOptions) async throws -> CapturedImage {
        let state = await requestAuthorization()
        guard state == .authorized else { throw CameraError.notAuthorized(state) }
        guard AVCaptureDevice.default(for: .video) != nil else {
            throw CameraError.noCameraAvailable
        }
        return try await CaptureWindowController(options: options).present()
    }

    public func pickImage() async throws -> CapturedImage {
        try await Self.presentOpenPanel()
    }

    @MainActor
    private static func presentOpenPanel() async throws -> CapturedImage {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .gif, .bmp]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            throw CameraError.cancelled
        }
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CameraError.platform("Could not read the chosen image.")
        }
        return try MacImageEncoder.encode(cgImage, options: CaptureOptions())
    }

    private static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .unavailable
        }
    }
}

// MARK: - Capture window

private final class CaptureWindowController: NSObject, AVCapturePhotoCaptureDelegate, NSWindowDelegate, @unchecked Sendable {
    // Nothing else holds this controller: the caller only chains `.present()`
    // off a temporary instance (`CaptureWindowController(options:).present()`),
    // and once the setup Task below returns, its capture of `self` is the
    // last strong reference. The window keeps running — its delegate and its
    // buttons' targets are unretained on AppKit's side (NSWindow.delegate is
    // weak; NSButton.target is unsafe/unretained, not weak) — so `self` gets
    // deallocated while the window is still showing, and tapping Capture (or
    // any callback into `self`) dereferences freed memory. This holds a real
    // strong reference for the life of one capture flow, cleared in finish().
    nonisolated(unsafe) private static var active: CaptureWindowController?

    private let options: CaptureOptions
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "omni.camera.mac.session")

    private var window: NSWindow?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CapturedImage, Error>?

    init(options: CaptureOptions) {
        self.options = options
    }

    func present() async throws -> CapturedImage {
        Self.active = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                do {
                    try self.configureSession()
                    self.showWindow()
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    @MainActor
    private func configureSession() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.noCameraAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.platform("Could not attach the camera.")
        }
        session.addInput(input)
        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CameraError.platform("Could not attach the photo output.")
        }
        session.addOutput(photoOutput)
        session.commitConfiguration()
    }

    @MainActor
    private func showWindow() {
        let preview = PreviewView()
        preview.previewLayer.session = session
        preview.previewLayer.videoGravity = .resizeAspectFill
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 480),
            preview.heightAnchor.constraint(equalToConstant: 360)
        ])

        let shutter = NSButton(title: "Capture", target: self, action: #selector(shutterTapped))
        shutter.bezelStyle = .rounded
        shutter.keyEquivalent = "\r"

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        let controls = NSStackView(views: [cancel, shutter])
        controls.orientation = .horizontal
        controls.spacing = 12

        let root = NSStackView(views: [preview, controls])
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 512, height: 440),
                            styleMask: [.titled, .closable],
                            backing: .buffered, defer: false)
        win.title = "Take Photo"
        win.contentView = root
        win.delegate = self
        // Defaults to true — a pre-ARC convention where close() was meant to
        // be the window's only release. self.window below is a second, ARC
        // one; leaving this true double-releases the window the moment both
        // let go, which is what the zombie ("-[NSKVONotifying_NSWindow
        // release]: message sent to deallocated instance") was catching.
        win.isReleasedWhenClosed = false
        window = win

        sessionQueue.async { [session] in session.startRunning() }

        if let parent = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            parent.beginSheet(win) { _ in }
        } else {
            win.center()
            win.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func shutterTapped() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    @objc private func cancelTapped() {
        finish(.failure(CameraError.cancelled))
    }

    // Holds the outcome from didFinishProcessingPhoto until didFinishCaptureFor
    // says the capture pipeline is actually done. AVCapturePhotoOutput
    // delivers both for one capturePhoto() call, in that order, on the same
    // (serial) delegate queue — didFinishProcessingPhoto only means the photo
    // data is ready, not that the output is finished with the capture, and
    // finish() stops the session and tears down the preview layer. Doing
    // that mid-pipeline is exactly the kind of thing that can leave AVFoundation
    // still touching a layer that is about to disappear.
    private var pendingResult: Result<CapturedImage, Error>?

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            pendingResult = .failure(CameraError.platform(error.localizedDescription))
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            pendingResult = .failure(CameraError.platform("Could not read the captured photo."))
            return
        }
        do { pendingResult = .success(try MacImageEncoder.encode(cgImage, options: options)) }
        catch { pendingResult = .failure(error) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        let result = pendingResult
            ?? .failure(CameraError.platform(error?.localizedDescription ?? "Capture did not produce a photo."))
        pendingResult = nil
        finish(result)
    }

    func windowWillClose(_ notification: Notification) {
        finish(.failure(CameraError.cancelled))
    }

    private func finish(_ result: Result<CapturedImage, Error>) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()

        continuation.resume(with: result)

        Task { @MainActor in
            // Stop the session before tearing down the window, not merely
            // before returning from this method: stopRunning() is async here
            // (it blocks, so it runs on sessionQueue), and closing the window
            // deallocates the preview's AVCaptureVideoPreviewLayer. Racing
            // that teardown against a session still delivering frames to the
            // layer is a use-after-free on a background thread — it can
            // surface anywhere later, including as a crash in an unrelated
            // autorelease pool drain, which is what made this look unrelated
            // to the capture window at all.
            self.sessionQueue.async { [session = self.session] in
                session.stopRunning()
                DispatchQueue.main.async {
                    if let win = self.window {
                        if let parent = win.sheetParent { parent.endSheet(win) }
                        win.close()
                    }
                    self.window = nil
                    if Self.active === self { Self.active = nil }
                }
            }
        }
    }
}

private final class PreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Resizing and encoding

private enum MacImageEncoder {
    static func encode(_ image: CGImage, options: CaptureOptions) throws -> CapturedImage {
        let resized = resize(image, options: options)

        let utType: CFString
        switch options.format {
        case .jpeg: utType = UTType.jpeg.identifier as CFString
        case .png: utType = UTType.png.identifier as CFString
        case .heic: utType = UTType.heic.identifier as CFString
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, utType, 1, nil) else {
            throw CameraError.platform("Could not encode the image.")
        }
        let properties: [CFString: Any] = options.format == .png
            ? [:]
            : [kCGImageDestinationLossyCompressionQuality: options.quality]
        CGImageDestinationAddImage(destination, resized, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CameraError.platform("Could not encode the image.")
        }
        return CapturedImage(data: data as Data, format: options.format,
                             width: resized.width, height: resized.height)
    }

    /// Scales to CaptureOptions.targetSize. The arithmetic is shared so every
    /// backend crops identically.
    private static func resize(_ image: CGImage, options: CaptureOptions) -> CGImage {
        let source = (width: image.width, height: image.height)
        let target = options.targetSize(for: source)
        guard target.width != source.width || target.height != source.height else { return image }

        guard let context = CGContext(
            data: nil, width: target.width, height: target.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        return context.makeImage() ?? image
    }
}
#endif
