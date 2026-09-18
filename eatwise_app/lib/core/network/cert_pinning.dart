import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;

/// 生产自签名证书锁定（cert pinning）：服务端 https://wcg.polin.tech:8443
/// 使用 50 年自签名证书（CN/SAN=wcg.polin.tech），系统 CA 不信任，握手时
/// 在 badCertificateCallback 里逐字节比对证书 DER 放行。证书源文件
/// eatwise_server/deploy/certs/cert.pem，轮换时同步替换资产。
const String pinnedCertAsset = 'assets/certs/wcg.polin.tech.pem';

/// 仅该 host 启用锁定（将来换域名走系统 CA 默认校验）。
const String pinnedCertHost = 'wcg.polin.tech';

/// 锁定启用判定（纯函数）：仅 API Base URL 为 https 且 host 为生产域名时
/// 启用；http 开发地址（局域网联调）与其它域名保持默认行为。
bool shouldPinCert(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  return uri != null && uri.scheme == 'https' && uri.host == pinnedCertHost;
}

/// DER 字节逐字节相等判定（纯函数）。
bool derEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// PEM 文本 → DER 字节（纯函数）：去头尾行与空白后 base64 解码。
Uint8List pemToDer(String pem) {
  final base64Body = pem
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return Uint8List.fromList(base64Decode(base64Body));
}

/// 从资产加载 PEM 并解码出钉死的 DER 字节。
///
/// 不用 SecurityContext(withTrustedRoots: false) + setTrustedCertificatesBytes
/// 的原因：dart:io 在 Apple 平台走系统 Security 框架做证书验证，自签名
/// 证书即使塞进 SecurityContext 仍被判 application verification failure
/// （Android 的 BoringSSL 路径却能通过）；badCertificateCallback 钩子 +
/// DER 字节比对在双端行为一致。
Future<Uint8List> loadPinnedCertDer({
  Future<ByteData> Function(String)? assetReader,
}) async {
  final data = await (assetReader ?? rootBundle.load)(pinnedCertAsset);
  return pemToDer(utf8.decode(data.buffer.asUint8List()));
}

/// badCertificateCallback 放行判定（纯函数）：仅锁定 host 且对端证书
/// DER 与钉死字节一致才放行。
bool allowPinnedCert(Uint8List certDer, String host, Uint8List pinnedDer) {
  return host == pinnedCertHost && derEquals(certDer, pinnedDer);
}

/// 把锁定挂到 dio 底层 HttpClient 上（dart:io 平台，Android/iOS）：
/// badCertificateCallback 只在系统验证失败时被调用（系统 CA 正常的站点
/// 不受影响），且仅对锁定 host 比对 DER，相等才放行，其余一律拒绝。
void applyCertPinning(Dio dio, Uint8List pinnedDer) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback = (cert, host, port) {
        return allowPinnedCert(Uint8List.fromList(cert.der), host, pinnedDer);
      };
      return client;
    },
  );
}
