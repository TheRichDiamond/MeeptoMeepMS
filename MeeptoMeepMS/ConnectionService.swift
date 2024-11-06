import MultipeerConnectivity
import SwiftUI
import CryptoKit

class ConnectionService: NSObject, ObservableObject {
    private let serviceType = "meep-chat"
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let encryptionService = EncryptionService()
    private var hasExchangedKeys = false
    private var connectionRetryCount = 0
    private let maxRetries = 3
    private let maxConnectionAttempts = 5
    private let connectionTimeout: TimeInterval = 10.0
    private var connectionTimer: Timer?
    private let reconnectionDelay: TimeInterval = 2.0
    private var isReconnecting = false
    
    @Published var availablePeers: [MCPeerID] = []
    @Published var receivedMessages: [(String, String, Bool)] = []
    @Published var connectionStatus: String = "Disconnected"
    
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    private var reconnectionWorkItem: DispatchWorkItem?
    
    private let queue = DispatchQueue(label: "com.meeptomeep.connectionService", qos: .userInitiated)
    
    override init() {
        session = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)
        
        super.init()
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.session.delegate = self
            self.advertiser.delegate = self
            self.browser.delegate = self
            self.startServices()
        }
    }
    
    private func setupDelegates() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.session.delegate = self
            self.advertiser.delegate = self
            self.browser.delegate = self
            self.startServices()
        }
    }
    
    deinit {
        stopServices()
    }
    
    private func startServices() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopServices()
            
            // Create new session only if needed
            if self.session.connectedPeers.isEmpty {
                self.session = MCSession(peer: self.myPeerId, securityIdentity: nil, encryptionPreference: .required)
                self.session.delegate = self
            }
            
            self.advertiser.startAdvertisingPeer()
            self.browser.startBrowsingForPeers()
            
            DispatchQueue.main.async {
                self.setupConnectionTimer()
            }
        }
    }
    
    private func setupConnectionTimer() {
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: connectionTimeout, repeats: false) { [weak self] _ in
            self?.handleConnectionTimeout()
        }
    }
    
    private func handleConnectionTimeout() {
        if connectionRetryCount < maxRetries {
            connectionRetryCount += 1
            DispatchQueue.main.async {
                self.connectionStatus = "Connection timed out. Retrying... (\(self.connectionRetryCount)/\(self.maxRetries))"
                self.restartServices()
            }
        } else {
            DispatchQueue.main.async {
                self.connectionStatus = "Connection failed after \(self.maxRetries) attempts"
                self.availablePeers.removeAll()
            }
        }
    }
    
    private func restartServices() {
        stopServices()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startServices()
        }
    }
    
    private func stopServices() {
        reconnectionWorkItem?.cancel()
        connectionTimer?.invalidate()
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        // Don't disconnect session here to prevent EXC_BAD_ACCESS
    }
    
    private func handleConnectionFailure() {
        guard !isReconnecting else { return }
        
        reconnectionWorkItem?.cancel()
        
        if connectionRetryCount < maxRetries {
            isReconnecting = true
            connectionRetryCount += 1
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.connectionStatus = "Connection failed. Retrying... (\(self.connectionRetryCount)/\(self.maxRetries))"
            }
            
            let workItem = DispatchWorkItem { [weak self] in
                self?.isReconnecting = false
                self?.startServices()
            }
            
            reconnectionWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + reconnectionDelay, execute: workItem)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.connectionStatus = "Connection failed after \(self.maxRetries) attempts"
                self.availablePeers.removeAll()
            }
        }
    }
    
    func send(message: String) {
        guard !session.connectedPeers.isEmpty else {
            print("No connected peers")
            return
        }
        
        guard let encryptedData = encryptionService.encrypt(message) else {
            print("Failed to encrypt message")
            exchangePublicKey() // Try to re-establish encryption
            return
        }
        
        let messageDict: [String: Any] = [
            "type": "message",
            "data": [UInt8](encryptedData),
            "deviceName": myPeerId.displayName,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        do {
            let messageData = try JSONSerialization.data(withJSONObject: messageDict)
            try session.send(messageData, toPeers: session.connectedPeers, with: .reliable)
            DispatchQueue.main.async {
                self.receivedMessages.append((message, self.myPeerId.displayName, true))
            }
            print("Message sent successfully")
        } catch {
            print("Failed to send message: \(error.localizedDescription)")
        }
    }
    
    private func exchangePublicKey() {
        guard !session.connectedPeers.isEmpty else { return }
        
        // Add a flag to prevent repeated exchanges
        guard !hasExchangedKeys else { return }
        
        do {
            let publicKeyData = encryptionService.publicKey.rawRepresentation
            let keyDict: [String: Any] = [
                "type": "key",
                "data": [UInt8](publicKeyData)
            ]
            
            if let keyData = try? JSONSerialization.data(withJSONObject: keyDict) {
                try session.send(keyData, toPeers: session.connectedPeers, with: .reliable)
                hasExchangedKeys = true
            }
        } catch {
            print("Failed to send public key: \(error)")
        }
    }
}

extension ConnectionService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Ensure all session state changes happen on the same queue
        queue.async { [weak self] in
            guard let self = self else { return }
            
            switch state {
            case .connected:
                // Reset connection state
                self.hasExchangedKeys = false
                self.encryptionService.reset()
                
                DispatchQueue.main.async {
                    self.connectionTimer?.invalidate()
                    self.connectionStatus = "Connected to \(peerID.displayName)"
                    self.connectionRetryCount = 0
                    self.isReconnecting = false
                    
                    if !self.availablePeers.contains(peerID) {
                        self.availablePeers.append(peerID)
                    }
                }
                
                // Delay key exchange
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.exchangePublicKey()
                }
                
            case .notConnected:
                DispatchQueue.main.async {
                    self.availablePeers.removeAll { $0 == peerID }
                    self.handleConnectionFailure()
                }
                
            case .connecting:
                DispatchQueue.main.async {
                    self.connectionStatus = "Connecting to \(peerID.displayName)..."
                }
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = dict["type"] as? String,
                      let byteArray = dict["data"] as? [UInt8] else {
                    return
                }
                
                let receivedData = Data(byteArray)
                
                switch type {
                case "key":
                    if let peerPublicKey = try? P256.KeyAgreement.PublicKey(rawRepresentation: receivedData) {
                        self.encryptionService.createSharedKey(peerPublicKey: peerPublicKey)
                        if !self.hasExchangedKeys {
                            self.exchangePublicKey()
                        }
                    }
                case "message":
                    if let decryptedMessage = self.encryptionService.decrypt(receivedData),
                       let deviceName = dict["deviceName"] as? String {
                        DispatchQueue.main.async {
                            self.receivedMessages.append((decryptedMessage, deviceName, false))
                        }
                    } else {
                        self.exchangePublicKey()
                    }
                default:
                    break
                }
            } catch {
                print("Error processing received data: \(error.localizedDescription)")
            }
        }
    }
    
    // Required protocol stubs
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension ConnectionService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer: \(peerID.displayName)")
        DispatchQueue.main.async {
            // Don't accept invitations from self or already connected peers
            if peerID != self.myPeerId && !self.session.connectedPeers.contains(peerID) {
                invitationHandler(true, self.session)
            } else {
                invitationHandler(false, nil)
            }
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }
}

extension ConnectionService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("Found peer: \(peerID.displayName)")
        // Don't connect to self or already connected peers
        if peerID != self.myPeerId && !self.session.connectedPeers.contains(peerID) && !self.availablePeers.contains(peerID) {
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 30)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost peer: \(peerID.displayName)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }
}
