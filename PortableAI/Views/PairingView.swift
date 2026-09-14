import PhotosUI
import SwiftUI
import UIKit

struct PairingView: View {
    private enum Field: Hashable {
        case serverURL
        case secret
        case deviceName
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.themeColors) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = "http://192.168.1."
    /// Rotating 6-digit PIN **or** family password (same field; see claim routing).
    @State private var pairingSecret = ""
    @State private var deviceName = UIDevice.current.name
    @State private var showScanner = false
    @State private var scanError: String?
    @State private var cameraBlocked = false
    /// Bumped whenever we should scroll/focus manual fields (even if already blocked).
    @State private var manualFocusToken = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var isDecodingPhoto = false
    @FocusState private var focusedField: Field?
    @StateObject private var discovery = PortableAIDiscovery()
    /// Identity for the server currently being PIN-paired (from discovery or URL host).
    @State private var pendingServerID: ServerID?
    @State private var pendingDisplayName: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        if discovery.servers.isEmpty {
                            if discovery.isInitialSearch {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Looking for PortableAI servers…")
                                        .foregroundStyle(theme.textMuted)
                                }
                                .frame(minHeight: 44)
                            } else {
                                Text("No PortableAI servers found on this network")
                                    .foregroundStyle(theme.textMuted)
                                    .frame(minHeight: 44)

                                Button {
                                    discovery.refresh()
                                } label: {
                                    Label("Discover again", systemImage: "arrow.clockwise")
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        } else {
                            ForEach(discovery.servers) { server in
                                Button {
                                    Task { await selectDiscoveredServer(server) }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "desktopcomputer")
                                            .foregroundStyle(theme.accent)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 8) {
                                                Text(server.displayName)
                                                    .foregroundStyle(theme.textPrimary)
                                                    .font(.body.weight(.medium))
                                                if appState.isRemembered(
                                                    serverID: server.serverID,
                                                    displayName: server.displayName,
                                                    baseURL: server.baseURL
                                                ) {
                                                    Text("Paired")
                                                        .font(.caption2.weight(.semibold))
                                                        .foregroundStyle(theme.accent)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(theme.accent.opacity(0.15))
                                                        .clipShape(Capsule())
                                                }
                                            }
                                            Text(server.baseURL)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(theme.textMuted)
                                        }
                                        Spacer(minLength: 0)
                                        if appState.isPairing {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(theme.textMuted)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(appState.isPairing)
                            }

                            Button {
                                discovery.refresh()
                            } label: {
                                Label(
                                    discovery.isInitialSearch ? "Searching…" : "Discover again",
                                    systemImage: "arrow.clockwise"
                                )
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .disabled(discovery.isInitialSearch)
                        }
                    } header: {
                        HStack {
                            Text("Found on your network")
                            Spacer()
                            if discovery.isInitialSearch {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Button {
                                    discovery.refresh()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption.weight(.semibold))
                                }
                                .accessibilityLabel("Discover again")
                            }
                        }
                    } footer: {
                        Text("Tap a paired server to reconnect instantly. New servers need the PIN from that machine. Pull down or tap Discover again to rescan.")
                    }

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
                            .foregroundStyle(theme.textMuted)
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
                            .foregroundStyle(theme.textMuted)
                        TextField("http://192.168.1.42:5050", text: $serverURL)
                            .id("manualServer")
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .serverURL)
                            .font(.body)
                            .frame(minHeight: 44)

                        Text("PIN or password")
                            .font(.subheadline)
                            .foregroundStyle(theme.textMuted)
                            .padding(.top, 4)
                        TextField("PIN or password", text: $pairingSecret)
                            .id("manualPin")
                            .keyboardType(.asciiCapable)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .secret)
                            .font(.body.monospaced())
                            .frame(minHeight: 48)
                    } header: {
                        Text("Enter server details")
                    } footer: {
                        Text("Use the 6-digit PIN from Phone pairing, or the family password from Settings on the laptop. QR codes still use the rotating PIN only.")
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
                            let id = pendingServerID
                                ?? PairingKeychain.serverID(fromBaseURL: serverURL)
                            let name = pendingDisplayName ?? id
                            let secret = pairingSecret.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                await appState.pair(
                                    serverURL: serverURL,
                                    pin: secret,
                                    deviceName: deviceName,
                                    serverID: id,
                                    displayName: name
                                )
                                if appState.isPaired {
                                    dismiss()
                                }
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
                            (serverURL.isEmpty || pairingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.isPairing)
                                ? theme.accent.opacity(0.45)
                                : theme.accent
                        )
                        .disabled(
                            serverURL.isEmpty
                                || pairingSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || appState.isPairing
                        )
                    }
                }
                .refreshable {
                    discovery.refresh()
                    // Keep the pull-to-refresh spinner up through the search window.
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                }
                .navigationTitle("Pair with PortableAI")
                .tint(theme.accent)
                .onAppear {
                    discovery.start()
                }
                .onDisappear {
                    discovery.stop()
                }
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

    private func selectDiscoveredServer(_ server: DiscoveredPortableAIServer) async {
        scanError = nil
        cameraBlocked = false
        serverURL = server.baseURL
        pendingServerID = server.serverID
        pendingDisplayName = server.displayName

        if appState.isRemembered(
            serverID: server.serverID,
            displayName: server.displayName,
            baseURL: server.baseURL
        ) {
            pairingSecret = ""
            focusedField = nil
            let ok = await appState.connectWithStoredCredential(
                serverID: server.serverID,
                baseURL: server.baseURL,
                displayName: server.displayName
            )
            if ok {
                dismiss()
                return
            }
            // Revoked or failed — fall through to PIN/password entry.
        }

        focusedField = .secret
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
        // QR encodes rotating PIN only — never the family password.
        pairingSecret = scannedPin
        pendingServerID = PairingKeychain.normalizeID(host)
        pendingDisplayName = host
        let pairedURL = serverURL
        let pairedPin = scannedPin
        let pairedName = deviceName
        let pairedID = pendingServerID
        Task {
            await appState.pair(
                serverURL: pairedURL,
                pin: pairedPin,
                deviceName: pairedName,
                serverID: pairedID,
                displayName: host
            )
            if appState.isPaired {
                dismiss()
            }
        }
    }
}
