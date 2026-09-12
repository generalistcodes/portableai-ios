import PhotosUI
import SwiftUI
import UIKit

struct PairingView: View {
    private enum Field: Hashable {
        case serverURL
        case pin
        case deviceName
    }

    @EnvironmentObject var appState: AppState
    @State private var serverURL = "http://192.168.1."
    @State private var pin = ""
    @State private var deviceName = UIDevice.current.name
    @State private var showScanner = false
    @State private var scanError: String?
    @State private var cameraBlocked = false
    /// Bumped whenever we should scroll/focus manual fields (even if already blocked).
    @State private var manualFocusToken = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var isDecodingPhoto = false
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        Button {
                            scanError = nil
                            cameraBlocked = false
                            showScanner = true
                        } label: {
                            Label("Scan QR code", systemImage: "qrcode.viewfinder")
                                .frame(minHeight: 44)
                        }

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(
                                isDecodingPhoto ? "Reading QR…" : "Use photo of QR code",
                                systemImage: "photo.on.rectangle"
                            )
                            .frame(minHeight: 44)
                        }
                        .disabled(isDecodingPhoto)

                        Text("Optional. Live camera may fail on some iPhones due to a known iOS bug.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let scanError {
                        Section {
                            Text(scanError)
                                .foregroundStyle(.red)
                                .font(.body)

                            if cameraBlocked || scanError == CameraScanMessages.iosMultitaskingBug {
                                Button {
                                    self.scanError = nil
                                    cameraBlocked = false
                                    showScanner = true
                                } label: {
                                    Label("Try again", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }

                                Button {
                                    focusManualEntry(proxy: proxy)
                                } label: {
                                    Label("Enter server details", systemImage: "keyboard")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }

                            if scanError.contains("Settings") {
                                Button("Open Settings") {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    }

                    Section {
                        Text("Server address")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("http://192.168.1.42:5050", text: $serverURL)
                            .id("manualServer")
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .serverURL)
                            .font(.body)
                            .frame(minHeight: 44)

                        Text("6-digit PIN")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        TextField("123456", text: $pin)
                            .id("manualPin")
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focusedField, equals: .pin)
                            .font(.title2.monospacedDigit())
                            .frame(minHeight: 48)
                            .onChange(of: pin) { _, newValue in
                                let digits = newValue.filter(\.isNumber)
                                if digits != newValue {
                                    pin = String(digits.prefix(6))
                                } else if newValue.count > 6 {
                                    pin = String(newValue.prefix(6))
                                }
                            }
                    } header: {
                        Text("Enter server details")
                    } footer: {
                        Text("From PortableAI Settings → Phone pairing on your laptop: copy the address and PIN.")
                    }

                    Section("This device") {
                        TextField("Device name", text: $deviceName)
                            .focused($focusedField, equals: .deviceName)
                            .frame(minHeight: 44)
                    }

                    if let error = appState.pairingError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            focusedField = nil
                            Task {
                                await appState.pair(serverURL: serverURL, pin: pin, deviceName: deviceName)
                            }
                        } label: {
                            Group {
                                if appState.isPairing {
                                    ProgressView()
                                        .tint(.white)
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                } else {
                                    Text("Pair")
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                        .font(.headline)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .listRowBackground(
                            (serverURL.isEmpty || pin.count != 6 || appState.isPairing)
                                ? Brand.accent.opacity(0.45)
                                : Brand.accent
                        )
                        .disabled(serverURL.isEmpty || pin.count != 6 || appState.isPairing)
                    }
                }
                .navigationTitle("Pair with PortableAI")
                .tint(Brand.accent)
                .onChange(of: photoItem) { _, newItem in
                    guard let newItem else { return }
                    Task { await decodePhotoItem(newItem) }
                }
                .onChange(of: manualFocusToken) { _, _ in
                    focusManualEntry(proxy: proxy)
                }
                .fullScreenCover(isPresented: $showScanner) {
                    ZStack(alignment: .bottom) {
                        Color.black.ignoresSafeArea()
                        QRScannerView(
                            onCode: { code in
                                showScanner = false
                                handleScannedCode(code)
                            },
                            onError: { message in
                                showScanner = false
                                if message == CameraScanMessages.iosMultitaskingBug
                                    || message.localizedCaseInsensitiveContains("multitasking") {
                                    presentCameraBlocked()
                                } else {
                                    cameraBlocked = false
                                    scanError = message
                                }
                            },
                            onCameraBlocked: {
                                showScanner = false
                                presentCameraBlocked()
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()

                        Button("Cancel") {
                            showScanner = false
                        }
                        .font(.headline)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                    }
                }
            }
        }
    }

    private func presentCameraBlocked() {
        cameraBlocked = true
        scanError = CameraScanMessages.iosMultitaskingBug
        manualFocusToken += 1
    }

    private func focusManualEntry(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("manualServer", anchor: .center)
            }
            focusedField = .serverURL
        }
    }

    private func decodePhotoItem(_ item: PhotosPickerItem) async {
        isDecodingPhoto = true
        defer {
            isDecodingPhoto = false
            photoItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                scanError = "Couldn't load that photo."
                cameraBlocked = false
                return
            }
            guard let code = QRCodeDecoder.firstQRPayload(in: image) else {
                scanError = "No QR code found in that photo. Enter the address and PIN manually below."
                cameraBlocked = false
                return
            }
            handleScannedCode(code)
        } catch {
            scanError = "Couldn't read that photo."
            cameraBlocked = false
        }
    }

    /// QR encodes http://host:port/?pair_pin=......
    private func handleScannedCode(_ code: String) {
        guard let components = URLComponents(string: code),
              let host = components.host
        else {
            scanError = "That QR code doesn't look like a PortableAI pairing code."
            cameraBlocked = false
            return
        }
        let port = components.port ?? 5050
        guard let scannedPin = components.queryItems?.first(where: { $0.name == "pair_pin" })?.value,
              scannedPin.count == 6
        else {
            scanError = "That QR code is missing a valid pairing PIN."
            cameraBlocked = false
            return
        }

        scanError = nil
        cameraBlocked = false
        serverURL = "http://\(host):\(port)"
        pin = scannedPin
        let pairedURL = serverURL
        let pairedPin = scannedPin
        let pairedName = deviceName
        Task {
            await appState.pair(serverURL: pairedURL, pin: pairedPin, deviceName: pairedName)
        }
    }
}
