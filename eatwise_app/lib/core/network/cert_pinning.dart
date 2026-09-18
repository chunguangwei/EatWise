import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;

/// 生产自签名证书锁定（cert pinning）：服务端 https://wcg.polin.tech:8443
/// 使用 50 年自签名证书（CN/SAN=wcg.polin.tech），系统 CA 不信任，客户端
/// 须显式信任该证书否则 TLS 握手失败。证书源文件
/// eatwise_server/deploy/certs/cert.pem，轮换时同步替换资产。
const String pinnedCertAsset = 'assets/certs/wcg.polin.tech.pem';

/// 仅该host 启用锁定（将来换域名走系统 CA 默认校验）。
const String pinnedCertHost = 'wcg.polin.tech';

/// 锁定启用判定（纯函数）：仅 API Base URL 为 https 且 host 为生产域名时
/// 启用；http 开发地址（局域网联调）与其它域名保持默认行为。
bool shouldPinCert(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  return uri != null && uri.scheme == 'https' && uri.host == pinnedCertHost;
}

/// 从资产加载 PEM，构造只信任该证书的 [SecurityContext]
/// （withTrustedRoots: false，不再叠加系统 CA）。
Future<SecurityContext> loadPinnedSecurityContext({
  Future<ByteData> Function(String)? assetReader,
}) async {
  final data = await (assetReader ?? rootBundle.load)(pinnedCertAsset);
  final context = SecurityContext(withTrustedRoots: false);
  context.setTrustedCertificatesBytes(data.buffer.asUint8List());
  return context;
}

/// 把锁定挂到 dio 底层 HttpClient 上（dart:io 平台，Android/iOS）。
void applyCertPinning(Dio dio, SecurityContext context) {
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient(context: context),
  );
}
