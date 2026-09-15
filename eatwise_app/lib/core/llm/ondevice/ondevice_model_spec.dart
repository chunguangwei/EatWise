/// 端侧小模型（Gemma4-E2B-it, .litertlm）静态规格与选源纯函数。
///
/// 数值锚点（端侧推理 spike 报告 §1，与 imagepilot vlmModels 对齐）：
/// - 字节数 2,588,147,712（2.41 GiB），下载完成必须精确匹配；
/// - 文件头 8 字节 ASCII `LITERTLM`（4C 49 54 45 52 54 4C 4D），
///   用于拦截「下到 HTML 错误页但大小碰巧够」的脏文件；
/// - 物理内存门槛：iOS ≥3000MB（4GB iPhone 纯 CPU 可跑，imagepilot 实证），
///   Android ≥3800MB（仅 4GB+ 机型放行，低配机加载途中易被 OOM-kill）。
library;

/// 端侧模型静态描述（当前只有一档 gemma_e2b，结构对齐 imagepilot 以便后续扩档）。
final class OnDeviceModelSpec {
  const OnDeviceModelSpec();

  /// 模型文件名（单文件 .litertlm，无 mmproj）。
  static const String fileName = 'gemma-4-E2B-it.litertlm';

  /// 应用文档目录下的存放子目录。
  static const String modelsDirName = 'models';

  /// 完整文件字节数（下载完整性校验，必须精确相等才放行）。
  static const int expectedBytes = 2588147712;

  /// 文件头魔数（ASCII `LITERTLM`）。
  static const List<int> magicBytes = [
    0x4C,
    0x49,
    0x54,
    0x45,
    0x52,
    0x54,
    0x4C,
    0x4D,
  ];

  /// ModelScope 直链（国内优先；litert-community 官方仓库，免 token）。
  static const String modelScopeUrl =
      'https://modelscope.cn/models/litert-community/gemma-4-E2B-it-litert-lm/resolve/master/gemma-4-E2B-it.litertlm';

  /// 海外兜底源：HuggingFace litert-community 官方仓直链（海外可达）。
  /// 不用 GitHub Release 托管——模型 2.41GiB 超 GitHub 单资产 2GB 上限；
  /// 该域名国内被墙，仅作海外源（选源逻辑已把国内用户导向 ModelScope）。
  static const String huggingFaceUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm';

  /// iOS 物理内存门槛（MB）。
  static const int minDeviceMemMBIos = 3000;

  /// Android 物理内存门槛（MB）。
  static const int minDeviceMemMBAndroid = 3800;

  /// 下载前要求的可用存储下限：模型 2.41GiB + XNNPACK cache ~0.75GiB +
  /// 下载期 .part/.tail 双写峰值 ≈ 6GiB（spike §7-5）。
  static final int requiredFreeStorageBytes = (expectedBytes * 2.5).ceil();
}

/// 是否偏好国内源（ModelScope）。
///
/// 口径对齐 imagepilot modelRegion：中国大陆（zh / zh_CN / zh-Hans*）→ 国内源；
/// 港台繁体（zh_TW/zh_HK/zh_Hant）与其余 locale 一律海外源（GitHub 全球可达，作安全默认）。
bool prefersChinaModelSource(String locale) {
  final lc = locale.toLowerCase().replaceAll('-', '_');
  return lc == 'zh' || lc.startsWith('zh_cn') || lc.startsWith('zh_hans');
}

/// 下载候选 URL 列表（主源在前、兜底在后；管理器按序尝试，一源失败自动换源）。
List<String> onDeviceModelUrlCandidates({required bool preferChina}) {
  const ms = OnDeviceModelSpec.modelScopeUrl;
  const hf = OnDeviceModelSpec.huggingFaceUrl;
  return preferChina ? const [ms, hf] : const [hf, ms];
}

/// 平台物理内存门槛（MB）。platform 取 io.Platform.operatingSystem。
int minDeviceMemMBForPlatform(String operatingSystem) {
  return operatingSystem == 'ios'
      ? OnDeviceModelSpec.minDeviceMemMBIos
      : OnDeviceModelSpec.minDeviceMemMBAndroid;
}
