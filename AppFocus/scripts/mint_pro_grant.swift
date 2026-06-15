#!/usr/bin/env swift
import Foundation
import CryptoKit

// Pro grant-token minting tool.
//
//   swift scripts/mint_pro_grant.swift keygen
//       Generate an Ed25519 keypair. Prints the PUBLIC key (paste into
//       EntitlementStore.grantPublicKeyBase64) and writes the PRIVATE key
//       to ~/.terracognita/pro_signing_key — outside the repo, mode 0600.
//
//   swift scripts/mint_pro_grant.swift mint <id> [days]
//       Mint a signed grant for <id>. Omit days for a permanent grant;
//       pass a positive integer N for one that expires N days from now.
//       Prints the bare token and a terracognita://redeem?token=… URL.
//
// The private key is the only secret — keep it out of git. The public key
// embedded in the app can VERIFY tokens but never forge or extend them, so
// a leaked grant can't be tampered into a longer or different one.

let keyPath: URL = {
    if let override = ProcessInfo.processInfo.environment["PRO_SIGNING_KEY"] {
        return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".terracognita/pro_signing_key")
}()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Base64url without padding — matches `EntitlementStore.base64urlDecode`.
func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Hand-roll a JSON string literal so the signed payload bytes are exactly
/// what we transmit (the app verifies the signature over the received
/// bytes, then decodes). Avoids any encoder-fragment quirks.
func jsonString(_ s: String) -> String {
    var out = "\""
    for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if scalar.value < 0x20 {
                out += String(format: "\\u%04x", scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out + "\""
}

let args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else {
    fail("usage: mint_pro_grant.swift keygen | mint <id> [days]")
}

switch mode {
case "keygen":
    if FileManager.default.fileExists(atPath: keyPath.path) {
        fail("Refusing to overwrite the existing key at \(keyPath.path). Move it aside first.")
    }
    let key = Curve25519.Signing.PrivateKey()
    try? FileManager.default.createDirectory(
        at: keyPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try key.rawRepresentation.base64EncodedString()
            .write(to: keyPath, atomically: true, encoding: .utf8)
    } catch {
        fail("Couldn't write the private key: \(error.localizedDescription)")
    }
    try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: keyPath.path)
    print("Private key written to \(keyPath.path)")
    print("  → keep this secret; do NOT commit it.\n")
    print("Paste this PUBLIC key into EntitlementStore.grantPublicKeyBase64:")
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "mint":
    guard args.count >= 2 else { fail("usage: mint_pro_grant.swift mint <id> [days]") }
    let id = args[1]

    guard let b64 = try? String(contentsOf: keyPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
          let keyData = Data(base64Encoded: b64),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
        fail("No usable private key at \(keyPath.path). Run `keygen` first (or set PRO_SIGNING_KEY).")
    }

    var json = "{\"id\":\(jsonString(id))"
    if args.count >= 3 {
        guard let days = Int(args[2]), days > 0 else {
            fail("days must be a positive integer")
        }
        let exp = Int(Date().timeIntervalSince1970) + days * 86_400
        json += ",\"exp\":\(exp)"
    }
    json += "}"

    let payload = Data(json.utf8)
    guard let signature = try? key.signature(for: payload) else {
        fail("Signing failed.")
    }
    let token = base64url(payload) + "." + base64url(signature)
    print(token)
    print("terracognita://redeem?token=\(token)")

default:
    fail("unknown mode '\(mode)'. usage: mint_pro_grant.swift keygen | mint <id> [days]")
}
