// WeChatCDNService.swift
// DevBar

import CommonCrypto
import Foundation

enum WeChatCDNService {
    static func encrypt(data: Data, key: Data) -> Data? {
        guard key.count == kCCKeySizeAES128 else { return nil }
        return crypt(data: data, key: key, operation: CCOperation(kCCEncrypt))
    }

    static func decrypt(data: Data, key: Data) -> Data? {
        guard key.count == kCCKeySizeAES128 else { return nil }
        return crypt(data: data, key: key, operation: CCOperation(kCCDecrypt))
    }

    static func generateAESKey() -> Data {
        var key = Data(count: kCCKeySizeAES128)
        _ = key.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, kCCKeySizeAES128, ptr.baseAddress!)
        }
        return key
    }

    // MARK: - Private

    private static func crypt(data: Data, key: Data, operation: CCOperation) -> Data? {
        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesProcessed: Int = 0

        let status = buffer.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode + kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        kCCKeySizeAES128,
                        nil,
                        inBytes.baseAddress,
                        data.count,
                        outBytes.baseAddress,
                        bufferSize,
                        &numBytesProcessed
                    )
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        buffer.count = numBytesProcessed
        return buffer
    }
}
