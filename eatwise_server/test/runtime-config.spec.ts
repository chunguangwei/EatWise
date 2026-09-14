import { ConfigService } from '@nestjs/config';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'fs';
import { tmpdir } from 'os';
import { join } from 'path';
import { RuntimeConfigService, maskApiKey } from '../src/admin/runtime-config.service';

/** RuntimeConfigService：覆盖优先级（runtime > env > stub）、持久化、apiKey 脱敏与降级 */
describe('RuntimeConfigService', () => {
  let dir: string;
  let file: string;

  const make = (env: Record<string, string> = {}) =>
    new RuntimeConfigService(new ConfigService(env));

  beforeEach(() => {
    dir = mkdtempSync(join(tmpdir(), 'eatwise-cfg-'));
    file = join(dir, 'admin-config.json');
    process.env.ADMIN_CONFIG_PATH = file;
  });

  afterEach(() => {
    delete process.env.ADMIN_CONFIG_PATH;
    rmSync(dir, { recursive: true, force: true });
  });

  it('无覆盖无 env → stub 降级（source=stub）', () => {
    const svc = make();
    expect(svc.resolveLlm()).toEqual({ provider: 'stub', source: 'stub' });
  });

  it('env LLM_PROVIDER=deepseek → source=env，补 preset baseUrl/model', () => {
    const svc = make({ LLM_PROVIDER: 'deepseek', LLM_API_KEY: 'sk-env-key-9999' });
    const eff = svc.resolveLlm();
    expect(eff.source).toBe('env');
    expect(eff.provider).toBe('deepseek');
    expect(eff.baseUrl).toBe('https://api.deepseek.com/v1');
    expect(eff.model).toBe('deepseek-chat');
    expect(eff.apiKey).toBe('sk-env-key-9999');
  });

  it('运行时覆盖优先于 env（source=runtime，逐字段合并）', () => {
    const svc = make({ LLM_PROVIDER: 'deepseek', LLM_API_KEY: 'sk-env-key-9999' });
    svc.setLlmOverride({
      provider: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:4b',
    });
    const eff = svc.resolveLlm();
    expect(eff.source).toBe('runtime');
    expect(eff.provider).toBe('custom');
    expect(eff.baseUrl).toBe('http://localhost:11434/v1');
    expect(eff.model).toBe('qwen3:4b');
    // 覆盖未给 apiKey → 回退 env
    expect(eff.apiKey).toBe('sk-env-key-9999');
  });

  it('覆盖项持久化到 JSON 文件，新实例（模拟重启）读回生效', () => {
    const svc = make();
    svc.setLlmOverride({
      provider: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:4b',
      apiKey: 'sk-persist-123456',
    });
    const onDisk = JSON.parse(readFileSync(file, 'utf8')) as { llm: Record<string, string> };
    expect(onDisk.llm).toMatchObject({
      provider: 'custom',
      model: 'qwen3:4b',
      apiKey: 'sk-persist-123456',
    });

    const reloaded = make();
    const eff = reloaded.resolveLlm();
    expect(eff.source).toBe('runtime');
    expect(eff.provider).toBe('custom');
    expect(eff.apiKey).toBe('sk-persist-123456');
  });

  it('provider 变更时重置 baseUrl/model/apiKey 覆盖项（custom 切回 preset 不串味）', () => {
    const svc = make();
    svc.setLlmOverride({
      provider: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:4b',
      apiKey: 'sk-custom-9999',
    });
    svc.setLlmOverride({ provider: 'deepseek' });
    expect(svc.getLlmOverride()).toEqual({ provider: 'deepseek' });
    const eff = svc.resolveLlm();
    expect(eff.baseUrl).toBe('https://api.deepseek.com/v1'); // preset 默认值生效，不被旧 custom 值压过
    expect(eff.model).toBe('deepseek-chat');
    expect(eff.apiKey).toBeUndefined();
  });

  it('provider 未变更时保留既有覆盖项（同 provider 更新部分字段）', () => {
    const svc = make();
    svc.setLlmOverride({
      provider: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:4b',
      apiKey: 'sk-custom-9999',
    });
    svc.setLlmOverride({ provider: 'custom', model: 'qwen3:8b' });
    expect(svc.getLlmOverride()).toEqual({
      provider: 'custom',
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen3:8b',
      apiKey: 'sk-custom-9999',
    });
  });

  it('apiKey 留空 = 保持不变；目录不存在时自动创建', () => {
    process.env.ADMIN_CONFIG_PATH = join(dir, 'nested', 'deep', 'admin-config.json');
    const svc = make();
    svc.setLlmOverride({
      provider: 'custom',
      baseUrl: 'http://x/v1',
      model: 'm',
      apiKey: 'sk-first-0000',
    });
    svc.setLlmOverride({ provider: 'custom', baseUrl: 'http://x/v1', model: 'm', apiKey: '' });
    svc.setLlmOverride({ provider: 'custom', baseUrl: 'http://x/v1', model: 'm' });
    expect(svc.getLlmOverride().apiKey).toBe('sk-first-0000');
    expect(readFileSync(join(dir, 'nested', 'deep', 'admin-config.json'), 'utf8')).toContain(
      'sk-first-0000',
    );
  });

  it('持久化失败 → 降级仅内存并标记 persisted=false，读写不抛错', () => {
    // 让一个普通文件占据目录位置 → mkdir 必失败
    writeFileSync(file, 'not-a-dir');
    process.env.ADMIN_CONFIG_PATH = join(file, 'sub', 'admin-config.json');
    const svc = make();
    svc.setLlmOverride({ provider: 'custom', baseUrl: 'http://x/v1', model: 'm' });
    expect(svc.isPersisted()).toBe(false);
    expect(svc.resolveLlm().provider).toBe('custom'); // 进程内仍生效
  });

  it('配置文件损坏（非法 JSON）→ 告警并按空覆盖处理', () => {
    writeFileSync(file, '{broken');
    const svc = make({ LLM_PROVIDER: 'deepseek' });
    expect(svc.resolveLlm().source).toBe('env');
    expect(svc.getLlmOverride()).toEqual({});
  });
});

describe('maskApiKey（apiKey 脱敏）', () => {
  it('正常 key → sk-*** + 后 4 位', () => {
    expect(maskApiKey('sk-abcdef123456')).toBe('sk-***3456');
  });
  it('短 key（≤4 位）→ 全遮；空/缺省 → null', () => {
    expect(maskApiKey('abcd')).toBe('***');
    expect(maskApiKey('')).toBeNull();
    expect(maskApiKey(undefined)).toBeNull();
  });
});
