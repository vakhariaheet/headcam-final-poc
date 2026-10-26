import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Wire details of the hat's ownership protocol v1, shared by
/// [RealHatConnectionService] and its tests. Mirrors the firmware's
/// `hat_secure.h`:
///
/// * claim: owner key = HKDF-SHA256(salt `umpirehat-claim-v1`, ikm P-256
///   ECDH shared X, info app public || hat public). Neither side sends it.
/// * session: session key = HKDF-SHA256(salt `umpirehat-session-v1`, ikm
///   owner key, info AUTH nonce).
/// * sealed parameters: base64(iv(12) || AES-256-GCM(session key, aad =
///   command name, JSON params) || tag(16)).

/// Service-data UUID in the hat's scan response carrying its pairing flags.
const hatStatusServiceUuid = 'aa8aeb53-18b8-4df7-9c9b-4c579d9a9576';

const _pairingFlag = 0x01;
const _ownedFlag = 0x02;
final _claimSalt = utf8.encode('umpirehat-claim-v1');
final _sessionSalt = utf8.encode('umpirehat-session-v1');

/// Pairing state carried in the hat's scan response.
class HatAdvertisementFlags {
  const HatAdvertisementFlags({required this.pairingMode, required this.owned});

  /// Reads flags from the hat's status service data. Firmware older than
  /// the ownership protocol sends none, which reads as neither flag set.
  factory HatAdvertisementFlags.fromServiceData(List<int>? payload) {
    final flags = payload == null || payload.isEmpty ? 0 : payload.first;
    return HatAdvertisementFlags(
      pairingMode: flags & _pairingFlag != 0,
      owned: flags & _ownedFlag != 0,
    );
  }

  final bool pairingMode;
  final bool owned;
}

/// The phone's ephemeral P-256 key pair for one claim.
class HatClaimKeyPair {
  HatClaimKeyPair._(this._private, this.publicKey);

  /// A fresh key pair from the platform's secure random source.
  factory HatClaimKeyPair.generate() {
    final seed = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => seed.nextInt(256))),
        ),
      );
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(_curve), random));
    final pair = generator.generateKeyPair();
    return HatClaimKeyPair.fromPrivate(pair.privateKey.d!);
  }

  /// Rebuilds a key pair from a known scalar (test vectors).
  factory HatClaimKeyPair.fromPrivate(BigInt d) {
    final public = (_curve.G * d)!.getEncoded(false);
    return HatClaimKeyPair._(ECPrivateKey(d, _curve), public);
  }

  static final _curve = ECCurve_secp256r1();

  final ECPrivateKey _private;

  /// Uncompressed SEC1 point (65 bytes), sent base64 in `CLAIM`.
  final Uint8List publicKey;

  /// Derives the owner key from the hat's public key in the `CLAIM` reply.
  /// Throws [ArgumentError] if the point is malformed or off the curve.
  Uint8List deriveOwnerKey(List<int> hatPublicKey) {
    if (hatPublicKey.length != 65) {
      throw ArgumentError('hat public key must be 65 bytes');
    }
    final point = _curve.curve.decodePoint(hatPublicKey);
    if (point == null || point.isInfinity) {
      throw ArgumentError('invalid hat public key');
    }
    final agreement = ECDHBasicAgreement()..init(_private);
    final shared = agreement.calculateAgreement(ECPublicKey(point, _curve));
    return hkdfSha256(
      salt: _claimSalt,
      ikm: _fixedLength(shared, 32),
      info: [...publicKey, ...hatPublicKey],
    );
  }
}

/// HKDF-SHA256 (RFC 5869) producing one 32-byte block.
Uint8List hkdfSha256({
  required List<int> salt,
  required List<int> ikm,
  required List<int> info,
}) {
  final prk = Hmac(sha256, salt).convert(ikm).bytes;
  return Uint8List.fromList(Hmac(sha256, prk).convert([...info, 1]).bytes);
}

/// Session key for a link that answered the challenge [nonceHex].
Uint8List hatSessionKey({
  required String ownerKeyHex,
  required String nonceHex,
}) => hkdfSha256(
  salt: _sessionSalt,
  ikm: hexDecode(ownerKeyHex),
  info: hexDecode(nonceHex),
);

/// Answer to an `AUTH_START` challenge: hex HMAC-SHA256(owner key, nonce),
/// both given as hex strings exactly as stored and received.
String hatOwnerProof({required String ownerKeyHex, required String nonceHex}) {
  final hmac = Hmac(sha256, hexDecode(ownerKeyHex));
  return hmac.convert(hexDecode(nonceHex)).toString();
}

/// Seals [params] for [command] under [sessionKey]. [iv] is for test
/// vectors only; production calls get a fresh random IV.
String hatSeal({
  required List<int> sessionKey,
  required String command,
  required Map<String, Object?> params,
  List<int>? iv,
}) {
  final nonce = Uint8List.fromList(
    iv ?? List.generate(12, (_) => Random.secure().nextInt(256)),
  );
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(Uint8List.fromList(sessionKey)),
        128,
        nonce,
        Uint8List.fromList(utf8.encode(command)),
      ),
    );
  final sealed = cipher.process(
    Uint8List.fromList(utf8.encode(jsonEncode(params))),
  );
  return base64.encode([...nonce, ...sealed]);
}

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd-length hex');
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List _fixedLength(BigInt value, int length) {
  final hex = value.toRadixString(16).padLeft(length * 2, '0');
  return hexDecode(hex);
}

/// Encodes an FFE1 command.
List<int> hatCommand(Map<String, Object?> command) =>
    utf8.encode(jsonEncode(command));
