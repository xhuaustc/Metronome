import Foundation
import CryptoKit

// 生成 App Store Connect API 的 JWT（ES256）。
//
// 用法：
//   ./asc-token <AuthKey_XXX.p8> <KeyID> <IssuerID> [validSeconds]
//
// 输出一行 token 到 stdout。有效期上限 20 分钟，Apple 会拒绝更长的。

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("asc-token: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 4 else {
    fail("用法：asc-token <privateKey.p8> <keyID> <issuerID> [validSeconds]")
}

let keyPath = (args[1] as NSString).expandingTildeInPath
let keyID = args[2]
let issuerID = args[3]
let validFor = args.count > 4 ? (Int(args[4]) ?? 900) : 900

guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
    fail("读不到密钥文件：\(keyPath)")
}

guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    fail("无法解析 .p8 私钥，确认是 App Store Connect 下载的 AuthKey_*.p8")
}

func b64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
let now = Int(Date().timeIntervalSince1970)
let payload: [String: Any] = [
    "iss": issuerID,
    "iat": now,
    "exp": now + min(validFor, 1200),
    "aud": "appstoreconnect-v1",
]

guard let headerData = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]),
      let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
    fail("JSON 序列化失败")
}

let signingInput = b64url(headerData) + "." + b64url(payloadData)
guard let signature = try? key.signature(for: Data(signingInput.utf8)) else {
    fail("签名失败")
}

// ES256 的 JWT 需要 R||S 原始拼接（64 字节），CryptoKit 的 rawRepresentation 正好是。
print(signingInput + "." + b64url(signature.rawRepresentation))
