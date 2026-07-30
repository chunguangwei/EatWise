/**
 * 语义化版本工具（应用内更新检查用）：
 * 解析/比较 `x.y.z[+build]`，容忍前导 `v` 与缺省的 minor/patch。
 * 按 semver 规范，build 元数据（+ 后缀）不参与优先级比较。
 */

export interface SemverParts {
  major: number;
  minor: number;
  patch: number;
  /** build 元数据（不含 `+`）；缺省为 null。 */
  build: string | null;
}

/** 解析版本号；非法输入抛 TypeError。 */
export function parseSemver(version: string): SemverParts {
  const text = version.trim().replace(/^v/i, '');
  const match = /^(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+([0-9A-Za-z.-]+))?$/.exec(text);
  if (!match) {
    throw new TypeError(`非法语义化版本号: ${version}`);
  }
  return {
    major: Number(match[1]),
    minor: match[2] === undefined ? 0 : Number(match[2]),
    patch: match[3] === undefined ? 0 : Number(match[3]),
    build: match[4] ?? null,
  };
}

/**
 * 比较两个版本号：a < b 返回 -1，相等返回 0，a > b 返回 1。
 * build 元数据不参与比较（semver §10）。
 */
export function compareSemver(a: string, b: string): number {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  for (const key of ['major', 'minor', 'patch'] as const) {
    if (pa[key] !== pb[key]) return pa[key] < pb[key] ? -1 : 1;
  }
  return 0;
}
