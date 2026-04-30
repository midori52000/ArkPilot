import { ApiManagementService, apiManagementService } from './ApiManagementService';
import {
  ProviderRecord, ProviderPreset,
  ApiValidationResult, EndpointSpeedResult, UsageQueryResult,
  BUILTIN_PROVIDER_PRESETS
} from './ApiTypes';

@Observed
export class ApiManagementState {
  providers: ProviderRecord[] = [];
  presets: ProviderPreset[] = BUILTIN_PROVIDER_PRESETS;
  editingProvider: ProviderRecord | null = null;
  validationResult: ApiValidationResult | null = null;
  speedResults: EndpointSpeedResult[] = [];
  discoveredModels: string[] = [];
  usageResult: UsageQueryResult | null = null;
  loading: boolean = false;
  validating: boolean = false;
  speedTesting: boolean = false;
  discoveringModels: boolean = false;
  queryingUsage: boolean = false;
  showAddFromPreset: boolean = false;
  selectedPresetId: string = '';
  newApiKey: string = '';
  statusText: string = '';
  errorText: string = '';
}

export class ApiManagementViewModel {
  private service: ApiManagementService;
  state: ApiManagementState = new ApiManagementState();

  constructor(service: ApiManagementService) {
    this.service = service;
  }

  get activeProvider(): ProviderRecord | null {
    const providers = this.state.providers;
    for (let i = 0; i < providers.length; i++) {
      if (providers[i].isActive) return providers[i];
    }
    return null;
  }

  get activeProviderName(): string {
    const active = this.activeProvider;
    return active !== null ? active.name : 'None';
  }

  loadProviders(): void {
    this.state.loading = true;
    try {
      this.state.providers = this.service.getProviders();
      this.state.errorText = '';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    } finally {
      this.state.loading = false;
    }
  }

  startNewFromPreset(): void {
    this.state.showAddFromPreset = true;
    this.state.selectedPresetId = '';
    this.state.newApiKey = '';
  }

  confirmAddFromPreset(): void {
    if (this.state.selectedPresetId.length === 0) {
      return;
    }

    try {
      const provider = this.service.createFromPreset(
        this.state.selectedPresetId, this.state.newApiKey
      );
      const newProviders: ProviderRecord[] = [];
      for (let i = 0; i < this.state.providers.length; i++) {
        newProviders.push(this.state.providers[i]);
      }
      newProviders.push(provider);
      this.state.providers = newProviders;
      this.state.editingProvider = provider;
      this.state.showAddFromPreset = false;
      this.state.errorText = '';
      this.state.statusText = `已从预设创建 "${provider.name}"`;
    } catch (err) {
      this.state.errorText = this.describeError(err);
    }
  }

  cancelAddFromPreset(): void {
    this.state.showAddFromPreset = false;
    this.state.selectedPresetId = '';
    this.state.newApiKey = '';
  }

  startEditing(provider: ProviderRecord | null): void {
    if (provider !== null) {
      this.state.editingProvider = this.cloneProvider(provider);
    } else {
      this.state.editingProvider = new ProviderRecord(
        `provider-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
        '', 'codex', 'exclusive',
        '', '', '',
        false, 'dirty', '',
        'apiKey', [], 'responses',
        'custom', '', '', '', '',
        [], 'unknown', 0, 0,
        null, Date.now()
      );
    }
  }

  cancelEditing(): void {
    this.state.editingProvider = null;
  }

  saveEditing(): void {
    const editing = this.state.editingProvider;
    if (editing === null) return;

    try {
      this.service.saveProvider(editing);
      this.state.providers = this.service.getProviders();
      this.state.editingProvider = null;
      this.state.errorText = '';
      this.state.statusText = `Provider "${editing.name}" 已保存`;
    } catch (err) {
      this.state.errorText = this.describeError(err);
    }
  }

  activateProvider(id: string): void {
    try {
      const activated = this.service.activateProvider(id);
      this.state.providers = this.service.getProviders();
      this.state.errorText = '';
      this.state.statusText = `已激活 Provider "${activated.name}"`;
    } catch (err) {
      this.state.errorText = this.describeError(err);
    }
  }

  deleteProvider(id: string): void {
    try {
      const providers = this.state.providers;
      let target: ProviderRecord | null = null;
      for (let i = 0; i < providers.length; i++) {
        if (providers[i].id === id) {
          target = providers[i];
          break;
        }
      }
      this.service.deleteProvider(id);
      this.state.providers = this.service.getProviders();
      if (this.state.editingProvider !== null && this.state.editingProvider.id === id) {
        this.state.editingProvider = null;
      }
      this.state.errorText = '';
      this.state.statusText = target !== null
        ? `Provider "${target.name}" 已删除`
        : 'Provider 已删除';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    }
  }

  async validateProvider(provider: ProviderRecord): Promise<void> {
    this.state.validating = true;
    this.state.validationResult = null;
    try {
      this.state.validationResult = await this.service.validateApiKey(
        provider.baseUrl, provider.apiKey
      );
      if (this.state.validationResult.success) {
        provider.healthStatus = 'healthy';
        provider.healthLatencyMs = this.state.validationResult.latencyMs;
        provider.lastValidatedAt = Date.now();
        this.service.saveProvider(provider);
        this.state.providers = this.service.getProviders();
      }
      this.state.errorText = '';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    } finally {
      this.state.validating = false;
    }
  }

  async testSpeed(provider: ProviderRecord, autoSelect: boolean): Promise<void> {
    this.state.speedTesting = true;
    this.state.speedResults = [];
    try {
      this.state.speedResults = await this.service.testEndpointSpeed(provider, autoSelect);
      if (autoSelect) {
        this.state.providers = this.service.getProviders();
      }
      this.state.errorText = '';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    } finally {
      this.state.speedTesting = false;
    }
  }

  async discoverModels(provider: ProviderRecord): Promise<void> {
    this.state.discoveringModels = true;
    this.state.discoveredModels = [];
    try {
      this.state.discoveredModels = await this.service.discoverModels(
        provider.baseUrl, provider.apiKey
      );
      this.state.errorText = '';
      this.state.statusText = `发现 ${this.state.discoveredModels.length} 个模型`;
    } catch (err) {
      this.state.errorText = this.describeError(err);
    } finally {
      this.state.discoveringModels = false;
    }
  }

  async queryUsage(provider: ProviderRecord): Promise<void> {
    this.state.queryingUsage = true;
    this.state.usageResult = null;
    try {
      this.state.usageResult = await this.service.queryUsage(provider);
      this.state.errorText = '';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    } finally {
      this.state.queryingUsage = false;
    }
  }

  exportProviders(): string {
    try {
      return this.service.exportProviders();
    } catch (err) {
      this.state.errorText = this.describeError(err);
      return '';
    }
  }

  importProviders(json: string): void {
    try {
      const count = this.service.importProviders(json);
      this.state.providers = this.service.getProviders();
      this.state.statusText = `已导入 ${count} 个 Provider`;
      this.state.errorText = '';
    } catch (err) {
      this.state.errorText = this.describeError(err);
    }
  }

  private cloneProvider(src: ProviderRecord): ProviderRecord {
    return new ProviderRecord(
      src.id, src.name, src.appType, src.mode,
      src.baseUrl, src.apiKey, src.model,
      src.isActive, src.syncStatus, src.updatedAt,
      src.authMode,
      src.copyHeaders(),
      src.wireApi,
      src.category, src.description, src.websiteUrl,
      src.icon, src.iconColor,
      src.endpoints,
      src.healthStatus, src.healthLatencyMs, src.lastValidatedAt,
      src.usageScript, src.createdAt
    );
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }
}

export const apiManagementVM: ApiManagementViewModel =
  new ApiManagementViewModel(apiManagementService);
