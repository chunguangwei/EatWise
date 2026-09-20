/// AI 润色的纯逻辑层（提示词构造 + 输出清洗），单测直接覆盖。
library;

/// AI 润色提示词（端侧视觉模型）：system 定角色与硬约束。
/// 输出**纯文本**（非 JSON），直接回填输入框。
const String kPostPolishSystemPrompt =
    '你是社交打卡文案润色助手。规则：'
    '1) 保持原意与人称，不编造原文没有的事实；'
    '2) 语气自然口语化，适合打卡社区，不用表情堆砌；'
    '3) 长度不超过 200 字；'
    '4) 只输出润色后的文案本身，不要任何解释、前后缀或引号。';

/// 用户消息（有配图时附带图片字节，模型可结合画面写细节）。
String buildPostPolishPrompt(String text, {bool hasImage = false}) {
  final intro = hasImage ? '请润色下面这段打卡文案，可参考配图内容补充一句画面细节：' : '请润色下面这段打卡文案：';
  return '$intro\n「$text」';
}

/// 模型输出清洗（纯函数）：去首尾空白/整段包裹引号/「润色后：」式前缀，
/// 超长截断到 [maxChars]（发布契约 §3.9 C1 上限 500）。
String cleanPolishResult(String raw, {int maxChars = 500}) {
  var s = raw.trim();
  // 先去「润色后：」「润色结果：」类前缀（去完可能露出包裹引号）。
  s = s.replaceFirst(RegExp(r'^润色(后|结果|之后)[：:]'), '').trim();
  // 去掉整段包裹的中/英文引号（模型常见违规，成对才去）。
  const pairs = <(String, String)>[('"', '"'), ('「', '」'), ('“', '”')];
  for (final (open, close) in pairs) {
    if (s.length > open.length + close.length &&
        s.startsWith(open) &&
        s.endsWith(close)) {
      s = s.substring(open.length, s.length - close.length).trim();
      break;
    }
  }
  if (s.length > maxChars) s = s.substring(0, maxChars);
  return s;
}
