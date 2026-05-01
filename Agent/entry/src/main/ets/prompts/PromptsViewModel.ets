import { PromptsBackendService, PromptError } from './PromptsBackendService';
import { PromptRecord, PromptImportResult } from './PromptTypes';

@Observed
export class PromptsState {
  prompts: PromptRecord[] = [];
  liveContent: string = '';
  editingPrompt: PromptRecord | null = null;
  loading: boolean = false;
  saving: boolean = false;
}

@Observed
export class PromptsViewModel {
  private service: PromptsBackendService;
  state: PromptsState = new PromptsState();

  constructor(service: PromptsBackendService) {
    this.service = service;
  }

  get activePrompt(): PromptRecord | null {
    for (let i: number = 0; i < this.state.prompts.length; i++) {
      if (this.state.prompts[i].enabled) {
        return this.state.prompts[i];
      }
    }
    return null;
  }

  get activePromptName(): string {
    const active: PromptRecord | null = this.activePrompt;
    if (active !== null) {
      return active.name;
    }
    return 'None';
  }

  async loadAll(): Promise<void> {
    this.state.loading = true;
    try {
      this.state.prompts = await this.service.getPrompts();
      this.state.liveContent = await this.service.getLiveContent();
    } finally {
      this.state.loading = false;
    }
  }

  async reloadLiveContent(): Promise<void> {
    this.state.liveContent = await this.service.getLiveContent();
  }

  async savePrompt(prompt: PromptRecord): Promise<void> {
    this.state.saving = true;
    try {
      await this.service.savePrompt(prompt);

      let foundIndex: number = -1;
      for (let i: number = 0; i < this.state.prompts.length; i++) {
        if (this.state.prompts[i].id === prompt.id) {
          foundIndex = i;
          break;
        }
      }
      if (foundIndex >= 0) {
        this.state.prompts[foundIndex] = prompt;
      } else {
        const newPrompts: PromptRecord[] = [];
        for (let i: number = 0; i < this.state.prompts.length; i++) {
          newPrompts.push(this.state.prompts[i]);
        }
        newPrompts.push(prompt);
        this.state.prompts = newPrompts;
      }

      this.state.editingPrompt = null;
    } finally {
      this.state.saving = false;
    }
  }

  async deletePrompt(id: string): Promise<void> {
    await this.service.deletePrompt(id);
    const filtered: PromptRecord[] = [];
    for (let i: number = 0; i < this.state.prompts.length; i++) {
      if (this.state.prompts[i].id !== id) {
        filtered.push(this.state.prompts[i]);
      }
    }
    this.state.prompts = filtered;
  }

  async enablePrompt(id: string): Promise<void> {
    await this.service.enablePrompt(id);

    for (let i: number = 0; i < this.state.prompts.length; i++) {
      this.state.prompts[i].enabled = this.state.prompts[i].id === id;
    }

    this.state.liveContent = await this.service.getLiveContent();
  }

  async disableAll(): Promise<void> {
    await this.service.disableAll();

    for (let i: number = 0; i < this.state.prompts.length; i++) {
      this.state.prompts[i].enabled = false;
    }

    this.state.liveContent = '';
  }

  async importFromFile(): Promise<PromptImportResult | null> {
    return this.service.importFromFile();
  }

  startEditing(prompt: PromptRecord | null): void {
    if (prompt) {
      this.state.editingPrompt = new PromptRecord(
        prompt.id, prompt.name, prompt.content,
        prompt.description, prompt.enabled,
        prompt.createdAt, prompt.updatedAt
      );
    } else {
      this.state.editingPrompt = new PromptRecord(
        `prompt-${Date.now()}`, '', '',
        '', false, Date.now(), 0
      );
    }
  }

  cancelEditing(): void {
    this.state.editingPrompt = null;
  }
}
