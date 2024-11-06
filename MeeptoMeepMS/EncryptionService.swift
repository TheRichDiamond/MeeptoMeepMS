import Foundation
import CryptoKit

class EncryptionService {
    private var privateKey: P256.KeyAgreement.PrivateKey
    public var publicKey: P256.KeyAgreement.PublicKey
    private var sharedSymmetricKey: SymmetricKey?
    
    init() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.publicKey = privateKey.publicKey
    }
    
    func createSharedKey(peerPublicKey: P256.KeyAgreement.PublicKey) {
        let sharedSecret = try? privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        self.sharedSymmetricKey = sharedSecret?.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: "MeeptoMeep".data(using: .utf8)!,
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }
    
    func encrypt(_ message: String) -> Data? {
        guard let symmetricKey = sharedSymmetricKey,
              let messageData = message.data(using: .utf8) else { return nil }
        
        return try? ChaChaPoly.seal(messageData, using: symmetricKey).combined
    }
    
    func decrypt(_ encryptedData: Data) -> String? {
        guard let symmetricKey = sharedSymmetricKey else { return nil }
        
        guard let sealedBox = try? ChaChaPoly.SealedBox(combined: encryptedData),
              let decryptedData = try? ChaChaPoly.open(sealedBox, using: symmetricKey),
              let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            return nil
        }
        
        return decryptedString
    }
    
    func clearKeys() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.publicKey = privateKey.publicKey
        self.sharedSymmetricKey = nil
    }
    
    func reset() {
        self.privateKey = P256.KeyAgreement.PrivateKey()
        self.publicKey = privateKey.publicKey
        self.sharedSymmetricKey = nil
    }
}
