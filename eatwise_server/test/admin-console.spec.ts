import { readFileSync } from 'fs';
import { resolve } from 'path';
import { createContext, runInContext } from 'vm';

const consoleHtml = readFileSync(resolve(__dirname, '../src/admin/console/index.html'), 'utf8');
const escSection = ['function esc(s) {', 'function fmtTime'] as const;

type Sandbox = Record<string, any>;

function evaluateSections(sandbox: Sandbox, sections: ReadonlyArray<readonly [string, string]>) {
  const source = sections
    .map(([startMarker, endMarker]) => {
      const start = consoleHtml.indexOf(startMarker);
      const end = consoleHtml.indexOf(endMarker, start + startMarker.length);
      if (start < 0 || end < 0) throw new Error(`无法定位管理台函数：${startMarker}`);
      return consoleHtml.slice(start, end);
    })
    .join('\n');
  createContext(sandbox);
  runInContext(source, sandbox);
  return sandbox;
}

function element(tagName: string): Sandbox {
  return {
    tagName,
    children: [],
    attributes: {},
    innerHTML: '',
    className: '',
    textContent: '',
    appendChild(child: Sandbox) {
      this.children.push(child);
      return child;
    },
    setAttribute(name: string, value: string) {
      this.attributes[name] = value;
    },
  };
}

function rowElement(): Sandbox {
  const cells: Record<string, Sandbox> = {
    '.foodActionsCell': element('td'),
    '.roleCell': element('td'),
  };
  return {
    ...element('tr'),
    querySelector(selector: string) {
      return cells[selector] ?? null;
    },
  };
}

function documentFor(id: string, tbody: Sandbox, created: Sandbox[]) {
  return {
    getElementById(requestedId: string) {
      return requestedId === id ? tbody : null;
    },
    createElement(tagName: string) {
      const createdElement = tagName === 'tr' ? rowElement() : element(tagName);
      created.push(createdElement);
      return createdElement;
    },
  };
}

describe('Admin console rendering regressions', () => {
  it('候选非空列表可渲染，不创建用户角色控件', () => {
    const tbody = element('tbody');
    const created: Sandbox[] = [];
    const sandbox = evaluateSections(
      {
        document: documentFor('candidateRows', tbody, created),
        STATUS_LABEL: { pending: '待审核' },
        fmtNameCell: () => '候选食物',
        fmtNutritionCell: () => '-',
        fmtEvidence: () => '-',
        fmtTime: () => '-',
      },
      [escSection, ['function renderRows(items, append) {', 'async function review(id, action)']],
    );

    sandbox.renderRows(
      [{ id: 'candidate-1', status: 'pending', userId: 'user-1', createdAt: null }],
      false,
    );

    expect(tbody.children).toHaveLength(1);
    expect(tbody.children[0].innerHTML).toContain('候选食物');
    expect(created.filter((item) => item.tagName === 'select')).toHaveLength(0);
  });

  it('帖子非空列表可渲染，不创建用户角色控件', () => {
    const tbody = element('tbody');
    const created: Sandbox[] = [];
    const sandbox = evaluateSections(
      {
        document: documentFor('postRows', tbody, created),
        POST_STATUS_LABEL: { pending: '待审核' },
        fmtTime: () => '-',
      },
      [
        escSection,
        ['function renderPostRows(items, append) {', 'async function reviewPost(id, action)'],
      ],
    );

    sandbox.renderPostRows(
      [
        {
          id: 'post-1',
          auditStatus: 'pending',
          auditReason: null,
          author: { id: 'user-1', nickname: '小林' },
          createdAt: null,
          text: '完成打卡',
          imageUrls: [],
          reportCount: 0,
          reportedAt: null,
        },
      ],
      false,
    );

    expect(tbody.children).toHaveLength(1);
    expect(tbody.children[0].innerHTML).toContain('完成打卡');
    expect(created.filter((item) => item.tagName === 'select')).toHaveLength(0);
  });

  it('举报待复核提供恢复和确认下架；结案历史举报显示已拒绝', () => {
    const tbody = element('tbody');
    const sandbox = evaluateSections(
      {
        document: documentFor('postRows', tbody, []),
        POST_STATUS_LABEL: { rejected: '已拒绝' },
        fmtTime: () => '-',
      },
      [
        escSection,
        ['function renderPostRows(items, append) {', 'async function reviewPost(id, action)'],
      ],
    );
    const post = {
      id: 'reported',
      auditStatus: 'rejected',
      author: { id: 'author' },
      text: 'test',
      imageUrls: [],
      reportCount: 1,
    };
    sandbox.renderPostRows([{ ...post, reportPending: true }], false);
    expect(tbody.children[0].innerHTML).toContain('恢复上架');
    expect(tbody.children[0].innerHTML).toContain('确认下架');
    sandbox.renderPostRows([{ ...post, reportPending: false }], false);
    expect(tbody.children[1].innerHTML).toContain('已拒绝');
    expect(tbody.children[1].innerHTML).not.toContain('确认下架');
    expect(tbody.children[1].innerHTML).not.toContain('badge reported');
  });

  it('角色控件仅保留在用户列表', () => {
    expect(consoleHtml.match(/var roleCell = tr\.querySelector\('\.roleCell'\);/g)).toHaveLength(1);
    const tbody = element('tbody');
    const created: Sandbox[] = [];
    const sandbox = evaluateSections(
      {
        document: documentFor('userRows', tbody, created),
        GOAL_LABEL: {},
        ONBOARDING_LABEL: { completed: '已完成' },
        USER_ROLE_LABEL: { user: '一般用户', admin: '管理员' },
        canSetUserRole: () => true,
        setUserRole: () => undefined,
        fmtTime: () => '-',
      },
      [escSection, ['function renderUserRows(items) {', '/* ===== 食物库']],
    );

    sandbox.renderUserRows([
      {
        id: 'user-1',
        role: 'admin',
        deletionStatus: null,
        username: 'tester',
        nickname: '测试员',
        phone: null,
        goal: null,
        onboardingStatus: 'completed',
        createdAt: null,
      },
    ]);

    const selects = created.filter((item) => item.tagName === 'select');
    expect(tbody.children).toHaveLength(1);
    expect(selects).toHaveLength(1);
    expect(selects[0].value).toBe('admin');
    expect(selects[0].children.map((option: Sandbox) => option.value)).toEqual(['user', 'admin']);
  });

  it('食物名不进入内联脚本，确认文案与 DELETE 流程保持原样', async () => {
    const tbody = element('tbody');
    const created: Sandbox[] = [];
    const apiCalls: Array<{ path: string; options: Sandbox }> = [];
    const flashes: Sandbox[] = [];
    const reloads: boolean[] = [];
    const confirmations: string[] = [];
    const maliciousName = "早餐');globalThis.__eatwiseXss = true;//<img src=x>";
    const sandbox = evaluateSections(
      {
        document: documentFor('foodRows', tbody, created),
        canSetUserRole: () => true,
        window: {
          confirm(message: string) {
            confirmations.push(message);
            return true;
          },
        },
        api(path: string, options: Sandbox) {
          apiCalls.push({ path, options });
          return Promise.resolve({ deletedEntries: 2 });
        },
        flash(...args: Sandbox[]) {
          flashes.push(args);
        },
        loadFoods(append: boolean) {
          reloads.push(append);
        },
      },
      [escSection, ['function renderFoodRows(items, append) {', 'refreshMe().then']],
    );

    sandbox.renderFoodRows(
      [
        {
          id: 'food-1',
          nameZh: maliciousName,
          nameEn: null,
          kcalPer100g: 100,
          source: 'custom',
          isCustom: true,
        },
      ],
      false,
    );

    const row = tbody.children[0];
    const button = created.find((item) => item.tagName === 'button');
    if (!button) throw new Error('删除按钮未创建');
    expect(row.innerHTML).toContain('&lt;img src=x&gt;');
    expect(row.innerHTML).not.toContain('onclick=');
    expect(row.innerHTML).not.toContain('deleteFood(');
    expect(button.textContent).toBe('删除');

    await button.onclick();

    expect(confirmations).toEqual([
      `删除食物「${maliciousName}」（food-1）？\n软删该条目，并级联删除所有用户引用它的饮食记录。不可恢复。`,
    ]);
    expect(apiCalls).toEqual([{ path: '/admin/foods/food-1', options: { method: 'DELETE' } }]);
    expect(flashes).toEqual([['foodsMsg', '已删除，级联清理饮食记录 2 条', true]]);
    expect(reloads).toEqual([false]);
    expect(sandbox.__eatwiseXss).toBeUndefined();
  });
});
