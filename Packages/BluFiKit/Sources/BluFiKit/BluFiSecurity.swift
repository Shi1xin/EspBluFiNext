import BigInt
import CommonCrypto
import CryptoKit
import Foundation

public enum BluFiSecurityOverride: String, Sendable, CaseIterable {
    case automatic
    case v1
    case v2

    public func resolve(deviceVersion: BluFiDeviceVersion) -> BluFiProtocol.SecurityVersion {
        switch self {
        case .automatic:
            deviceVersion.securityVersion
        case .v1:
            .v1
        case .v2:
            .v2
        }
    }
}

public enum BluFiSecurityError: Error, Sendable, Equatable, LocalizedError {
    case invalidPrivateKey
    case invalidDevicePublicKey
    case invalidSharedSecret
    case invalidSecurityPayload

    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            "BluFi Diffie-Hellman private key falls outside the selected group."
        case .invalidDevicePublicKey:
            "BluFi device public key falls outside the selected group."
        case .invalidSharedSecret:
            "BluFi Diffie-Hellman generated an empty shared secret."
        case .invalidSecurityPayload:
            "BluFi security negotiation payload is malformed."
        }
    }
}

public struct BluFiSecurityNegotiator: Sendable {
    public let version: BluFiProtocol.SecurityVersion

    private let group: BluFiDHGroup
    private let privateValue: BigUInt

    /// `privateKeyMaterial` exists for deterministic golden-vector tests. App
    /// callers pass no value and receive SystemRandomNumberGenerator entropy.
    public init(
        version: BluFiProtocol.SecurityVersion,
        privateKeyMaterial: [UInt8]? = nil
    ) throws {
        self.version = version
        group = BluFiDHGroup(version: version)

        if let privateKeyMaterial {
            privateValue = BigUInt(Data(privateKeyMaterial))
        } else {
            privateValue = BigUInt.randomInteger(lessThan: group.prime - 2) + 2
        }

        guard privateValue > 1, privateValue < group.prime - 1 else {
            throw BluFiSecurityError.invalidPrivateKey
        }
    }

    public var publicKey: [UInt8] {
        group.padded(group.generator.power(privateValue, modulus: group.prime))
    }

    /// First data body sent with `DataSubtype.negotiateSecurity`.
    public var totalLengthPayload: [UInt8] {
        let parameterLength = group.primeLength + group.generatorLength + group.publicKeyLength + 6
        return [0, UInt8(truncatingIfNeeded: parameterLength >> 8), UInt8(truncatingIfNeeded: parameterLength)]
    }

    /// Second data body sent with `DataSubtype.negotiateSecurity`.
    public var parameterPayload: [UInt8] {
        let prime = group.padded(group.prime)
        let generator = group.generator.serializeBytes
        let publicKey = publicKey

        return [1]
            + lengthPrefix(prime.count) + prime
            + lengthPrefix(generator.count) + generator
            + lengthPrefix(publicKey.count) + publicKey
    }

    public func makeSecurityContext(devicePublicKey: [UInt8]) throws -> BluFiSecurityContext {
        let remote = BigUInt(Data(devicePublicKey))
        guard remote > 1, remote < group.prime - 1 else {
            throw BluFiSecurityError.invalidDevicePublicKey
        }

        let sharedSecret = remote.power(privateValue, modulus: group.prime).serializeBytes
        guard !sharedSecret.isEmpty, sharedSecret.contains(where: { $0 != 0 }) else {
            throw BluFiSecurityError.invalidSharedSecret
        }

        return try BluFiSecurityContext(version: version, sharedSecret: sharedSecret)
    }

    private func lengthPrefix(_ length: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: length >> 8), UInt8(truncatingIfNeeded: length)]
    }
}

/// Holds stateful V2 CTR streams for a single active session. The session actor
/// owns this reference and destroys it as part of disconnect/reset handling.
public final class BluFiSecurityContext: @unchecked Sendable {
    public let version: BluFiProtocol.SecurityVersion

    private var key: [UInt8]
    private var outboundV2: BluFiAESStream?
    private var inboundV2: BluFiAESStream?

    public init(version: BluFiProtocol.SecurityVersion, sharedSecret: [UInt8]) throws {
        self.version = version

        switch version {
        case .v1:
            key = BluFiHash.md5(sharedSecret)
        case .v2:
            key = BluFiHash.sha256(sharedSecret)
            outboundV2 = try BluFiAESStream(
                operation: CCOperation(kCCEncrypt),
                mode: CCMode(kCCModeCTR),
                key: key,
                iv: BluFiHash.sha256(Array("blufi_dec".utf8) + sharedSecret).prefix(16),
                options: CCModeOptions(kCCModeOptionCTR_BE)
            )
            inboundV2 = try BluFiAESStream(
                operation: CCOperation(kCCDecrypt),
                mode: CCMode(kCCModeCTR),
                key: key,
                iv: BluFiHash.sha256(Array("blufi_enc".utf8) + sharedSecret).prefix(16),
                options: CCModeOptions(kCCModeOptionCTR_BE)
            )
        }
    }

    deinit {
        key.removeAll(keepingCapacity: false)
    }

    public func encrypt(_ plaintext: [UInt8], sequence: UInt8) throws -> [UInt8] {
        switch version {
        case .v1:
            return try BluFiAESStream.transform(
                operation: CCOperation(kCCEncrypt),
                mode: CCMode(kCCModeCFB),
                key: key,
                iv: v1IV(sequence),
                data: plaintext
            )
        case .v2:
            guard let outboundV2 else {
                throw BluFiProtocolError.securityRequired
            }
            return try outboundV2.update(plaintext)
        }
    }

    public func decrypt(_ ciphertext: [UInt8], sequence: UInt8) throws -> [UInt8] {
        switch version {
        case .v1:
            return try BluFiAESStream.transform(
                operation: CCOperation(kCCDecrypt),
                mode: CCMode(kCCModeCFB),
                key: key,
                iv: v1IV(sequence),
                data: ciphertext
            )
        case .v2:
            guard let inboundV2 else {
                throw BluFiProtocolError.securityRequired
            }
            return try inboundV2.update(ciphertext)
        }
    }

    private func v1IV(_ sequence: UInt8) -> [UInt8] {
        [sequence] + Array(repeating: 0, count: 15)
    }
}

private struct BluFiDHGroup: Sendable {
    let prime: BigUInt
    let generator = BigUInt(2)
    let publicKeyLength: Int

    init(version: BluFiProtocol.SecurityVersion) {
        switch version {
        case .v1:
            prime = BigUInt(BluFiDHGroup.v1Prime, radix: 16)!
            publicKeyLength = 128
        case .v2:
            prime = BigUInt(BluFiDHGroup.v2Prime, radix: 16)!
            publicKeyLength = 384
        }
    }

    var primeLength: Int { publicKeyLength }
    var generatorLength: Int { generator.serializeBytes.count }

    func padded(_ value: BigUInt) -> [UInt8] {
        let bytes = value.serializeBytes
        precondition(bytes.count <= publicKeyLength)
        return Array(repeating: 0, count: publicKeyLength - bytes.count) + bytes
    }

    private static let v1Prime = "cf5cf5c38419a724957ff5dd323b9c45c3cdd261eb740f69aa94b8bb1a5c9640" +
        "9153bd76b24222d03274e4725a5406092e9e82e9135c643cae98132b0d95f7d6" +
        "5347c68afc1e677da90e51bbab5f5cf429c291b4ba39c6b2dc5e8c7231e46aa7" +
        "728e87664532cdf547be20c9a3fa8342be6e34371a27c06f7dc0edddd2f86373"

    private static let v2Prime = "FFFFFFFFFFFFFFFFADF85458A2BB4A9AAFDC5620273D3CF1" +
        "D8B9C583CE2D3695A9E13641146433FBCC939DCE249B3EF9" +
        "7D2FE363630C75D8F681B202AEC4617AD3DF1ED5D5FD6561" +
        "2433F51F5F066ED0856365553DED1AF3B557135E7F57C935" +
        "984F0C70E0E68B77E2A689DAF3EFE8721DF158A136ADE735" +
        "30ACCA4F483A797ABC0AB182B324FB61D108A94BB2C8E3FB" +
        "B96ADAB760D7F4681D4F42A3DE394DF4AE56EDE76372BB19" +
        "0B07A7C8EE0A6D709E02FCE1CDF7E2ECC03404CD28342F61" +
        "9172FE9CE98583FF8E4F1232EEF28183C3FE3B1B4C6FAD73" +
        "3BB5FCBC2EC22005C58EF1837D1683B2C6F34A26C1B2EFFA" +
        "886B4238611FCFDCDE355B3B6519035BBC34F4DEF99C0238" +
        "61B46FC9D6E6C9077AD91D2691F7F7EE598CB0FAC186D91C" +
        "AEFE130985139270B4130C93BC437944F4FD4452E2D74DD3" +
        "64F2E21E71F54BFF5CAE82AB9C9DF69EE86D2BC522363A0D" +
        "ABC521979B0DEADA1DBF9A42D5C4484E0ABCD06BFA53DDEF" +
        "3C1B20EE3FD59D7C25E41D2B66C62E37FFFFFFFFFFFFFFFF"
}

private enum BluFiHash {
    static func md5(_ data: [UInt8]) -> [UInt8] {
        Array(Insecure.MD5.hash(data: data))
    }

    static func sha256(_ data: [UInt8]) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}

private final class BluFiAESStream {
    private let cryptor: CCCryptorRef

    init(operation: CCOperation, mode: CCMode, key: [UInt8], iv: some Collection<UInt8>, options: CCModeOptions = 0) throws {
        let iv = Array(iv)
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    operation,
                    mode,
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    options,
                    &cryptor
                )
            }
        }
        guard status == kCCSuccess, let cryptor else {
            throw BluFiProtocolError.cryptographicFailure(status: status)
        }
        self.cryptor = cryptor
    }

    deinit {
        CCCryptorRelease(cryptor)
    }

    static func transform(
        operation: CCOperation,
        mode: CCMode,
        key: [UInt8],
        iv: [UInt8],
        data: [UInt8]
    ) throws -> [UInt8] {
        let stream = try BluFiAESStream(operation: operation, mode: mode, key: key, iv: iv)
        return try stream.update(data)
    }

    func update(_ input: [UInt8]) throws -> [UInt8] {
        guard !input.isEmpty else {
            return []
        }

        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputCount = 0
        let status = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                CCCryptorUpdate(
                    cryptor,
                    inputBytes.baseAddress,
                    input.count,
                    outputBytes.baseAddress,
                    outputCapacity,
                    &outputCount
                )
            }
        }
        guard status == kCCSuccess else {
            throw BluFiProtocolError.cryptographicFailure(status: status)
        }
        return Array(output.prefix(outputCount))
    }
}

private extension BigUInt {
    var serializeBytes: [UInt8] {
        Array(serialize())
    }
}
