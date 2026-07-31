/// 条码格式（EAN-8/13、UPC-A 等）：8–14 位纯数字，与服务端口径一致。
final RegExp barcodePattern = RegExp(r'^\d{8,14}$');

/// 条码是否合法（trim 后判定）。
bool isValidBarcode(String code) => barcodePattern.hasMatch(code.trim());
