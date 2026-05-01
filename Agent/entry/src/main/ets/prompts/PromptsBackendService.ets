import { getPromptsRegistry, savePromptsRegistry, readAgentsMd, writeAgentsMd } from '../backend/CodexNative';
import { PromptRecord, PromptImportResult } from './PromptTypes';

const MAX_NAME_LEN = 100;
const MAX_CONTENT_PREVIEW_LEN = 500;

export enum PromptErrorCode {
  INVALID_NAME = 'INVALID_NAME',
  NOT_FOUND = 'NOT_FOUND',
  CANNOT_DELETE_ENABLED = 'CANNOT_DELETE_ENABLED',
}

export class PromptError extends Error {
  code: PromptErrorCode;
  context: Record<string, string>;
  suggestion: string;

  constructor(code: PromptErrorCode, context: Record<string, string>, suggestion: string) {
    let ctxStr: string = '';
    const keys: string[] = Object.keys(context);
    for (let i: number = 0; i < keys.length; i++) {
      if (i > 0) {
        ctxStr += ', ';
      }
      ctxStr += keys[i] + '=' + context[keys[i]];
    }
    super(`[${code}] ${ctxStr}`);
    this.name = 'PromptError';
    this.code = code;
    this.context = context;
    this.suggestion = suggestion;
  }
}

export const PROMPT_ERROR_MESSAGES: Record<PromptErrorCode, string> = {
  [PromptErrorCode.INVALID_NAME]: '名称不合法，不能为空且不超过 100 个字符',
  [PromptErrorCode.NOT_FOUND]: '未找到指定的 Prompt',
  [PromptErrorCode.CANNOT_DELETE_ENABLED]: '无法删除当前已启用的 Prompt，请先切换到其他 Prompt',
};

function makeErrorCtx(): Record<string, string> {
  return {} as Record<string, string>;
}

export class PromptsBackendService {
  private codexHome: string;

  constructor(codexHome: string) {
    this.codexHome = codexHome;
  }

  async getPrompts(): Promise<PromptRecord[]> {
    const json: string = getPromptsRegistry(this.codexHome);
    const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
    const promptsArr: Object[] = (parsed['prompts'] as Object[]) ?? [] as Object[];
    const result: PromptRecord[] = [];
    for (let i: number = 0; i < promptsArr.length; i++) {
      result.push(PromptRecord.fromJSON(promptsArr[i] as Record<string, Object>));
    }
    return result;
  }

  private async savePrompts(prompts: PromptRecord[]): Promise<void> {
    const now: string = String(Math.floor(Date.now() / 1000));
    const registry: Record<string, Object> = {} as Record<string, Object>;
    registry['version'] = 1;
    registry['prompts'] = prompts;
    registry['updatedAt'] = now;
    savePromptsRegistry(this.codexHome, JSON.stringify(registry));
  }

  async savePrompt(prompt: PromptRecord): Promise<void> {
    const name: string = prompt.name.trim();
    if (name.length === 0 || name.length > MAX_NAME_LEN) {
      const ctx: Record<string, string> = makeErrorCtx();
      ctx['name'] = prompt.name;
      throw new PromptError(PromptErrorCode.INVALID_NAME, ctx, '名称不能为空且不超过 100 个字符');
    }

    prompt.name = name;
    prompt.description = (prompt.description ?? '').trim();
    prompt.updatedAt = Date.now();

    const prompts: PromptRecord[] = await this.getPrompts();
    const index: number = prompts.findIndex((p: PromptRecord) => p.id === prompt.id);

    if (index >= 0) {
      prompts[index] = prompt;
    } else {
      prompts.push(prompt);
    }

    await this.savePrompts(prompts);
  }

  async deletePrompt(id: string): Promise<void> {
    const prompts: PromptRecord[] = await this.getPrompts();
    const prompt: PromptRecord | undefined = prompts.find((p: PromptRecord) => p.id === id);

    if (!prompt) {
      const ctx: Record<string, string> = makeErrorCtx();
      ctx['id'] = id;
      throw new PromptError(PromptErrorCode.NOT_FOUND, ctx, 'Prompt 不存在');
    }
    if (prompt.enabled) {
      const ctx: Record<string, string> = makeErrorCtx();
      ctx['id'] = id;
      ctx['name'] = prompt.name;
      throw new PromptError(PromptErrorCode.CANNOT_DELETE_ENABLED, ctx,
        '无法删除已启用的 Prompt，请先启用其他 Prompt 或全部禁用');
    }

    const filtered: PromptRecord[] = prompts.filter((p: PromptRecord) => p.id !== id);
    await this.savePrompts(filtered);
  }

  async enablePrompt(id: string): Promise<void> {
    const prompts: PromptRecord[] = await this.getPrompts();
    const target: PromptRecord | undefined = prompts.find((p: PromptRecord) => p.id === id);

    if (!target) {
      const ctx: Record<string, string> = makeErrorCtx();
      ctx['id'] = id;
      throw new PromptError(PromptErrorCode.NOT_FOUND, ctx, 'Prompt 不存在');
    }
    if (target.enabled) {
      return;
    }

    const currentEnabled: PromptRecord | undefined = prompts.find((p: PromptRecord) => p.enabled);
    if (currentEnabled) {
      const liveContent: string = readAgentsMd(this.codexHome);
      if (liveContent.length > 0 && liveContent !== currentEnabled.content) {
        currentEnabled.content = liveContent;
        currentEnabled.updatedAt = Date.now();
      }
    } else {
      const liveContent: string = readAgentsMd(this.codexHome);
      if (liveContent.length > 0) {
        const backupId: string = `auto-backup-${Date.now()}`;
        const backup: PromptRecord = new PromptRecord(
          backupId, 'Auto Backup', liveContent,
          'AGENTS.md 自动备份', false, Date.now(), 0
        );
        prompts.push(backup);
      }
    }

    for (let i: number = 0; i < prompts.length; i++) {
      prompts[i].enabled = prompts[i].id === id;
    }

    writeAgentsMd(this.codexHome, target.content);
    await this.savePrompts(prompts);
  }

  async disableAll(): Promise<void> {
    const prompts: PromptRecord[] = await this.getPrompts();

    const currentEnabled: PromptRecord | undefined = prompts.find((p: PromptRecord) => p.enabled);
    if (currentEnabled) {
      const liveContent: string = readAgentsMd(this.codexHome);
      if (liveContent.length > 0) {
        currentEnabled.content = liveContent;
        currentEnabled.updatedAt = Date.now();
      }
    }

    for (let i: number = 0; i < prompts.length; i++) {
      prompts[i].enabled = false;
    }

    writeAgentsMd(this.codexHome, '');
    await this.savePrompts(prompts);
  }

  async getLiveContent(): Promise<string> {
    return readAgentsMd(this.codexHome);
  }

  async importFromFile(): Promise<PromptImportResult | null> {
    const content: string = readAgentsMd(this.codexHome);

    if (content.trim().length === 0) {
      return null;
    }

    const id: string = `imported-${Date.now()}`;
    const firstLine: string = content.trimStart().split('\n')[0].replace(/^#\s*/, '');
    const name: string = firstLine.length > 0 ? `Imported: ${firstLine.substring(0, 50)}` : 'Imported';

    const prompt: PromptRecord = new PromptRecord(
      id, name, content,
      '从 AGENTS.md 导入', false, Date.now(), 0
    );

    const preview: string = content.length > MAX_CONTENT_PREVIEW_LEN
      ? content.substring(0, MAX_CONTENT_PREVIEW_LEN) + '...'
      : content;

    return new PromptImportResult(prompt, preview);
  }

  async autoImportOnFirstLaunch(): Promise<void> {
    const prompts: PromptRecord[] = await this.getPrompts();
    if (prompts.length > 0) {
      return;
    }

    const content: string = readAgentsMd(this.codexHome);
    if (content.trim().length === 0) {
      return;
    }

    const id: string = `auto-imported-${Date.now()}`;
    const firstLine: string = content.trimStart().split('\n')[0].replace(/^#\s*/, '');
    const name: string = firstLine.length > 0 ? firstLine.substring(0, 80) : 'Auto Imported';

    const prompt: PromptRecord = new PromptRecord(
      id, name, content,
      '首次启动自动导入', true, Date.now(), 0
    );

    prompts.push(prompt);
    await this.savePrompts(prompts);
    writeAgentsMd(this.codexHome, content);
  }
}
