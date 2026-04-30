import {
  CodexProviderConfig,
  getEmbeddedCodexProviderCatalog,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderCatalog,
  saveEmbeddedCodexProviderConfig
} from './CodexHostNative';
import { ProviderCatalog, ProviderRecord } from './ConsoleModels';

function currentTimestamp(): string {
  const now: Date = new Date();
  const year: string = now.getFullYear().toString();
  const month: string = (now.getMonth() + 1).toString().padStart(2, '0');
  const day: string = now.getDate().toString().padStart(2, '0');
  const hours: string = now.getHours().toString().padStart(2, '0');
  const minutes: string = now.getMinutes().toString().padStart(2, '0');
  return `${year}-${month}-${day} ${hours}:${minutes}`;
}

function createProviderId(): string {
  return `provider-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
}

function defaultProviderName(index: number): string {
  return `Codex Provider ${index}`;
}

function cloneProvider(provider: ProviderRecord): ProviderRecord {
  return new ProviderRecord(
    provider.id,
    provider.name,
    provider.appType,
    provider.mode,
    provider.baseUrl,
    provider.apiKey,
    provider.model,
    provider.isActive,
    provider.syncStatus,
    provider.updatedAt
  );
}

function cloneCatalog(catalog: ProviderCatalog): ProviderCatalog {
  return new ProviderCatalog(
    catalog.version,
    catalog.activeProviderId,
    catalog.providers.map((provider: ProviderRecord) => cloneProvider(provider)),
    catalog.updatedAt
  );
}

function buildRecordFromConfig(id: string, name: string, config: CodexProviderConfig, isActive: boolean): ProviderRecord {
  return new ProviderRecord(
    id,
    name,
    'codex',
    'exclusive',
    config.baseUrl.trim(),
    config.apiKey,
    config.model.trim(),
    isActive,
    'synced',
    currentTimestamp()
  );
}

export class ProviderCatalogService {
  private catalog: ProviderCatalog = new ProviderCatalog(1, '', [], currentTimestamp());

  load(): ProviderCatalog {
    const catalog: ProviderCatalog = getEmbeddedCodexProviderCatalog();
    this.catalog = this.ensureUsableCatalog(catalog);
    return cloneCatalog(this.catalog);
  }

  importCurrentProvider(): ProviderCatalog {
    const catalog: ProviderCatalog = this.load();
    const config: CodexProviderConfig = getEmbeddedCodexProviderConfig();
    if (catalog.providers.length > 0) {
      const activeProvider: ProviderRecord | null = this.activeProvider();
      if (activeProvider !== null) {
        activeProvider.baseUrl = config.baseUrl.trim();
        activeProvider.apiKey = config.apiKey;
        activeProvider.model = config.model.trim();
        activeProvider.syncStatus = 'synced';
        activeProvider.updatedAt = currentTimestamp();
        return this.persistCatalog();
      }
    }

    const imported: ProviderRecord = buildRecordFromConfig(
      createProviderId(),
      '当前 Live Provider',
      config,
      true
    );
    this.catalog.providers = [imported];
    this.catalog.activeProviderId = imported.id;
    return this.persistCatalog();
  }

  addProvider(name: string, baseUrl: string, apiKey: string, model: string): ProviderCatalog {
    const catalog: ProviderCatalog = this.load();
    const providerName: string = name.trim().length > 0 ? name.trim() : defaultProviderName(catalog.providers.length + 1);
    const provider: ProviderRecord = new ProviderRecord(
      createProviderId(),
      providerName,
      'codex',
      'exclusive',
      baseUrl.trim(),
      apiKey,
      model.trim(),
      false,
      'dirty',
      currentTimestamp()
    );
    this.catalog.providers = [...catalog.providers, provider];
    return this.persistCatalog();
  }

  updateProvider(id: string, name: string, baseUrl: string, apiKey: string, model: string): ProviderCatalog {
    this.load();
    this.catalog.providers = this.catalog.providers.map((provider: ProviderRecord) => {
      if (provider.id !== id) {
        return provider;
      }
      return new ProviderRecord(
        provider.id,
        name.trim().length > 0 ? name.trim() : provider.name,
        provider.appType,
        provider.mode,
        baseUrl.trim(),
        apiKey,
        model.trim(),
        provider.isActive,
        provider.isActive ? 'dirty' : provider.syncStatus,
        currentTimestamp()
      );
    });
    return this.persistCatalog();
  }

  removeProvider(id: string): ProviderCatalog {
    this.load();
    this.catalog.providers = this.catalog.providers.filter((provider: ProviderRecord) => provider.id !== id);
    if (this.catalog.activeProviderId === id) {
      this.catalog.activeProviderId = this.catalog.providers.length > 0 ? this.catalog.providers[0].id : '';
      this.catalog.providers = this.catalog.providers.map((provider: ProviderRecord, index: number) => {
        return new ProviderRecord(
          provider.id,
          provider.name,
          provider.appType,
          provider.mode,
          provider.baseUrl,
          provider.apiKey,
          provider.model,
          index === 0,
          index === 0 ? 'dirty' : provider.syncStatus,
          provider.updatedAt
        );
      });
    }
    return this.persistCatalog();
  }

  activateProvider(id: string): ProviderCatalog {
    this.load();
    let activatedId: string = '';
    let activatedBaseUrl: string = '';
    let activatedApiKey: string = '';
    let activatedModel: string = '';
    this.catalog.providers = this.catalog.providers.map((provider: ProviderRecord) => {
      const isActive: boolean = provider.id === id;
      const next: ProviderRecord = new ProviderRecord(
        provider.id,
        provider.name,
        provider.appType,
        provider.mode,
        provider.baseUrl,
        provider.apiKey,
        provider.model,
        isActive,
        isActive ? 'dirty' : provider.syncStatus,
        isActive ? currentTimestamp() : provider.updatedAt
      );
      if (isActive) {
        activatedId = next.id;
        activatedBaseUrl = next.baseUrl;
        activatedApiKey = next.apiKey;
        activatedModel = next.model;
      }
      return next;
    });
    this.catalog.activeProviderId = activatedId;
    if (activatedId.length > 0) {
      const saved: CodexProviderConfig = saveEmbeddedCodexProviderConfig(
        activatedBaseUrl,
        activatedApiKey,
        activatedModel
      );
      this.catalog.providers = this.catalog.providers.map((provider: ProviderRecord) => {
        if (provider.id !== activatedId) {
          return provider;
        }
        return buildRecordFromConfig(provider.id, provider.name, saved, true);
      });
    }
    return this.persistCatalog();
  }

  activeProvider(): ProviderRecord | null {
    for (let index: number = 0; index < this.catalog.providers.length; index += 1) {
      const provider: ProviderRecord = this.catalog.providers[index];
      if (provider.id === this.catalog.activeProviderId || provider.isActive) {
        return provider;
      }
    }
    return null;
  }

  private ensureUsableCatalog(catalog: ProviderCatalog): ProviderCatalog {
    if (catalog.providers.length === 0) {
      return new ProviderCatalog(1, '', [], currentTimestamp());
    }
    let activeId: string = catalog.activeProviderId;
    if (activeId.length === 0) {
      activeId = catalog.providers[0].id;
    }
    const providers: ProviderRecord[] = catalog.providers.map((provider: ProviderRecord) => {
      return new ProviderRecord(
        provider.id,
        provider.name,
        provider.appType,
        provider.mode,
        provider.baseUrl,
        provider.apiKey,
        provider.model,
        provider.id === activeId,
        provider.syncStatus,
        provider.updatedAt
      );
    });
    return new ProviderCatalog(catalog.version, activeId, providers, catalog.updatedAt);
  }

  private persistCatalog(): ProviderCatalog {
    this.catalog.updatedAt = currentTimestamp();
    const saved: ProviderCatalog = saveEmbeddedCodexProviderCatalog(this.catalog);
    this.catalog = this.ensureUsableCatalog(saved);
    return cloneCatalog(this.catalog);
  }
}

export const providerCatalogService: ProviderCatalogService = new ProviderCatalogService();
