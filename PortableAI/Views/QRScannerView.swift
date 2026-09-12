@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// QR scanner.
///
/// Critical: this target sets SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor.
/// Capture the session reference into queue blocks — never MainActor `self` —
/// so start/stop/configure run off the main actor.
///
/// Interruption reason 4 (`videoDeviceNotAvailableWithMultipleForegroundApps`)
/// is a confirmed iOS bug on some iPhones (Apple forums 791671 / 785206).
/// `isMultitaskingCameraAccessSupported` is often false, so Apple's mitigation
/// API is unavailable. Keep scanning + [PAI-CAM] logs; fail gracefully to manual entry.
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    /// Reason-4 / camera unavailable — host should dismiss and focus manual entry.
    var onCameraBlocked: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onCode = onCode
        vc.onError = onError
        vc.onCameraBlocked = onCameraBlocked
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.onError = onError
        uiViewController.onCameraBlocked = onCameraBlocked
    }
}

enum CameraScanMessages {
    /// Shown when live camera hits interruption reason 4 / won't start.
    static let iosMultitaskingBug = """
    Camera scanning isn't available right now due to a known iOS bug affecting camera access on some devices (not specific to this app — see developer.apple.com/forums/thread/791671 and /785206). Please use manual entry below instead.
    """
}

private final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

private final class CaptureSessionController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    nonisolated(unsafe) let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.portableai.qr.session")
    nonisolated(unsafe) private var isConfigured = false
    nonisolated(unsafe) private var didEmit = false
    nonisolated(unsafe) private var startGeneration = 0
    nonisolated(unsafe) var onCode: ((String) -> Void)?
    nonisolated(unsafe) var onStartResult: ((StartOutcome) -> Void)?

    enum StartOutcome: Sendable {
        case running
        case blockedByMultitasking
        case failed(String)
    }

    nonisolated func configure(completion: @escaping @Sendable (String?) -> Void) {
        // Touch session via `self` only — capturing AVCaptureSession in a
        // @Sendable closure warns (AVFoundation types aren't Sendable).
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.configureLocked(session: self.session)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    /// Stop, clear configured flag, and build the session again (Try again).
    nonisolated func reconfigure(completion: @escaping @Sendable (String?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            self.startGeneration += 1
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.isConfigured = false
            self.didEmit = false
            do {
                try self.configureLocked(session: self.session)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    nonisolated func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.didEmit = false
            guard self.isConfigured else {
                self.onStartResult?(.failed("Camera session was not configured."))
                return
            }
            if self.session.isRunning {
                self.onStartResult?(.running)
                return
            }

            // Defensive: Apple's mitigation for reason 4 when the API is available.
            // On this device logs show supported=false — keep logging for others.
            let multitaskingSupported = self.session.isMultitaskingCameraAccessSupported
            if multitaskingSupported {
                self.session.isMultitaskingCameraAccessEnabled = true
            }
            #if DEBUG
            print("[PAI-CAM] before startRunning multitasking supported=\(multitaskingSupported) enabled=\(self.session.isMultitaskingCameraAccessEnabled)")
            #endif

            self.startGeneration += 1
            let generation = self.startGeneration
            self.session.startRunning()
            let running = self.session.isRunning
            #if DEBUG
            print("[PAI-CAM] startRunning finished isRunning=\(running) thread=\(Thread.isMainThread ? "main" : "bg") multitasking=\(self.session.isMultitaskingCameraAccessEnabled)")
            #endif
            if running {
                self.onStartResult?(.running)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self else { return }
                guard generation == self.startGeneration else { return }
                #if DEBUG
                print("[PAI-CAM] delayed recheck isRunning=\(self.session.isRunning)")
                #endif
                if !self.session.isRunning {
                    self.onStartResult?(.blockedByMultitasking)
                }
            }
        }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.startGeneration += 1
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    nonisolated private func configureLocked(session: AVCaptureSession) throws {
        if isConfigured { return }

        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }

        let device =
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            throw APIError(message: "No camera available on this device.")
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let multitaskingSupported = session.isMultitaskingCameraAccessSupported
        if multitaskingSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
        #if DEBUG
        print("[PAI-CAM] multitaskingCameraAccess supported=\(multitaskingSupported) enabled=\(session.isMultitaskingCameraAccessEnabled)")
        #endif

        for existing in session.inputs {
            session.removeInput(existing)
        }
        for existing in session.outputs {
            session.removeOutput(existing)
        }

        guard session.canAddInput(input) else {
            throw APIError(message: "Couldn't access the camera.")
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            throw APIError(message: "Couldn't configure the camera for scanning.")
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        guard output.availableMetadataObjectTypes.contains(.qr) else {
            throw APIError(message: "QR codes aren't supported on this camera.")
        }
        output.metadataObjectTypes = [.qr]
        isConfigured = true
        #if DEBUG
        print("[PAI-CAM] configureLocked OK inputs=\(session.inputs.count) outputs=\(session.outputs.count)")
        #endif
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmit,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let value = obj.stringValue
        else { return }
        didEmit = true
        stop()
        let callback = onCode
        DispatchQueue.main.async { callback?(value) }
    }
}

final class ScannerViewController: UIViewController {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onCameraBlocked: (() -> Void)?

    private let sessionController = CaptureSessionController()
    private let previewView = CameraPreviewView()
    private let statusLabel = UILabel()
    private let tryAgainButton = UIButton(type: .system)
    private let manualEntryButton = UIButton(type: .system)
    private var didStartFlow = false
    private var didReportBlocked = false
    private var observers: [NSObjectProtocol] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textColor = .white
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .callout)
        statusLabel.isHidden = true
        view.addSubview(statusLabel)

        configureActionButton(tryAgainButton, title: "Try again")
        tryAgainButton.addTarget(self, action: #selector(tryAgainTapped), for: .touchUpInside)
        view.addSubview(tryAgainButton)

        configureActionButton(manualEntryButton, title: "Enter manually")
        manualEntryButton.addTarget(self, action: #selector(manualEntryTapped), for: .touchUpInside)
        view.addSubview(manualEntryButton)

        let actions = UIStackView(arrangedSubviews: [tryAgainButton, manualEntryButton])
        actions.axis = .vertical
        actions.spacing = 12
        actions.alignment = .fill
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.tag = 9001
        view.addSubview(actions)

        NSLayoutConstraint.activate([
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -48),

            actions.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            actions.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        actions.isHidden = true

        previewView.previewLayer.session = sessionController.session
        sessionController.onCode = { [weak self] code in self?.onCode?(code) }
        sessionController.onStartResult = { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .running:
                    self.hideBlockedUI()
                case .blockedByMultitasking:
                    // Fail onto PairingView: message + scroll/focus to manual entry.
                    self.reportCameraBlockedToHost()
                case .failed(let message):
                    self.onError?(message)
                }
            }
        }
        installSessionObservers()
        requestCameraAccessThenConfigure()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let connection = previewView.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleStartIfReady(delay: 0.4)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            sessionController.stop()
        }
    }

    private func configureActionButton(_ button: UIButton, title: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.18)
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18)
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = .preferredFont(forTextStyle: .headline)
            return attrs
        }
        button.configuration = config
        button.isHidden = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    @objc private func tryAgainTapped() {
        #if DEBUG
        print("[PAI-CAM] Try again — reconfigureSession")
        #endif
        hideBlockedUI()
        didReportBlocked = false
        sessionController.reconfigure { [weak self] errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMessage {
                    self.onError?(errorMessage)
                    return
                }
                self.previewView.previewLayer.session = self.sessionController.session
                self.scheduleStartIfReady(delay: 0.2)
            }
        }
    }

    @objc private func manualEntryTapped() {
        reportCameraBlockedToHost()
    }

    private func actionsStack() -> UIView? {
        view.viewWithTag(9001)
    }

    private func reportCameraBlockedToHost() {
        guard !didReportBlocked else { return }
        didReportBlocked = true
        #if DEBUG
        print("[PAI-CAM] reason-4 → graceful fail to manual entry")
        #endif
        // Keep a brief on-scanner message in case dismiss is slow; host owns UX.
        statusLabel.isHidden = false
        tryAgainButton.isHidden = false
        manualEntryButton.isHidden = false
        actionsStack()?.isHidden = false
        statusLabel.text = CameraScanMessages.iosMultitaskingBug
        sessionController.stop()
        onCameraBlocked?()
    }

    private func showBlockedUI() {
        reportCameraBlockedToHost()
    }

    private func hideBlockedUI() {
        didReportBlocked = false
        statusLabel.isHidden = true
        tryAgainButton.isHidden = true
        manualEntryButton.isHidden = true
        actionsStack()?.isHidden = true
    }

    private func scheduleStartIfReady(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.view.window != nil, self.didStartFlow else { return }
            self.sessionController.start()
        }
    }

    private func installSessionObservers() {
        let center = NotificationCenter.default
        let session = sessionController.session
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            let message = error?.localizedDescription ?? "Camera runtime error"
            #if DEBUG
            print("[PAI-CAM] runtimeError \(message)")
            #endif
            self?.onError?(message)
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            print("[PAI-CAM] wasInterrupted FULL userInfo=\(info)")
            if let raw = info[AVCaptureSessionInterruptionReasonKey] as? Int {
                let reason = AVCaptureSession.InterruptionReason(rawValue: raw)
                print("[PAI-CAM] AVCaptureSessionInterruptionReasonKey raw=\(raw) enum=\(String(describing: reason))")
                if raw == AVCaptureSession.InterruptionReason.videoDeviceNotAvailableWithMultipleForegroundApps.rawValue {
                    self?.showBlockedUI()
                }
            }
            print("[PAI-CAM] appState=\(UIApplication.shared.applicationState.rawValue) (0=active 1=inactive 2=background)")
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            print("[PAI-CAM] interruptionEnded userInfo=\(String(describing: note.userInfo))")
            self?.sessionController.start()
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            print("[PAI-CAM] didStartRunning notification")
            self?.hideBlockedUI()
        })
    }

    private func requestCameraAccessThenConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.onError?("Camera access was denied.")
                    }
                }
            }
        case .denied, .restricted:
            onError?("Camera access is denied. Enable it in Settings > PortableAI > Camera.")
        @unknown default:
            onError?("Couldn't determine camera access status.")
        }
    }

    private func configureSession() {
        guard !didStartFlow else {
            sessionController.start()
            return
        }
        didStartFlow = true
        sessionController.configure { [weak self] errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let errorMessage {
                    self.onError?(errorMessage)
                    return
                }
                self.previewView.previewLayer.session = self.sessionController.session
                if self.view.window != nil {
                    self.scheduleStartIfReady(delay: 0.15)
                }
            }
        }
    }
}
