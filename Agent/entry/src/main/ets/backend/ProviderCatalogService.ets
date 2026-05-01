import {
  CodexProviderConfig,
  getEmbeddedCodexProviderCatalog,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderCatalog,
  saveEmbeddedCodexProviderConfig
} from './CodexHostNative';
import { ProviderCatalog, ProviderRecord, EndpointEntry, CustomHeadersEntry } from './ConsoleModels';

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

function cloneEndpoints(src: EndpointEntry[]): EndpointEntry[] {
  const result: EndpointEntry[] = [];
  for (let i = 0; i < src.length; i++) {
    const e = src[i];
    result.push(new EndpointEntry(e.url, e.addedAt, e.lastUsed, e.latencyMs, e.isActive));
  }
  return result;
}

function cloneHeaders(src: CustomHeadersEntry[]): CustomHeadersEntry[] {
  const result: CustomHeadersEntry[] = [];
  for (let i = 0; i < src.length; i++) {
    const h = src[i];
    result.push(new CustomHeadersEntry(h.key, h.value));
  }
  return result;
}

function cloneProvider(provider: ProviderRecord): ProviderRecord {
  return new ProviderRecord(
    provider.id, provider.name, provider.appType, provider.mode,
    provider.baseUrl, provider.apiKey, provider.model,
    provider.isActive, provider.syncStatus, provider.updatedAt,
    provider.authMode, cloneHeaders(provider.customHeaders), provider.wireApi,
    provider.category, provider.description, provider.websiteUrl,
    provider.icon, provider.iconColor, cloneEndpoints(provider.endpoints),
    provider.healthStatus, provider.healthLatencyMs, provider.lastValidatedAt,
    provider.usageScript, provider.createdAt
  );
}

function cloneCatalog(catalog: ProviderCatalog): ProviderCatalog {
  const providers: ProviderRecord[] = [];
  for (let i = 0; i < catalog.providers.length; i++) {
    providers.push(cloneProvider(catalog.providers[i]));
  }
  return new ProviderCatalog(catalog.version, catalog.activeProviderId, providers, catalog.updatedAt);
}

function emptyHeaders(): CustomHeadersEntry[] {
  return [];
}

function emptyEndpoints(): EndpointEntry[] {
  return [];
}

function buildRecordFromConfig(id: string, name: string, config: CodexProviderConfig, isActive: boolean): ProviderRecord {
  return new ProviderRecord(
    id, name, 'codex', 'exclusive',
    config.baseUrl.trim(), config.apiKey, config.model.trim(),
    isActive, 'synced', currentTimestamp(),
    'apiKey', emptyHeaders(), 'responses', 'custom', '', '', '', '',
    emptyEndpoints(), 'unknown', 0, 0, null, Date.now()
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
      createProviderId(), providerName, 'codex', 'exclusive',
      baseUrl.trim(), apiKey, model.trim(),
      false, 'dirty', currentTimestamp(),
      'apiKey', emptyHeaders(), 'responses', 'custom', '', '', '', '',
      emptyEndpoints(), 'unknown', 0, 0, null, Date.now()
    );
    this.catalog.providers = [...catalog.providers, provider];
    return this.persistCatalog();
  }

  updateProvider(id: string, name: string, baseUrl: string, apiKey: string, model: string): ProviderCatalog {
    this.load();
    const newProviders: ProviderRecord[] = [];
    for (let i = 0; i < this.catalog.providers.length; i++) {
      const provider = this.catalog.providers[i];
      if (provider.id !== id) {
        newProviders.push(provider);
        continue;
      }
      newProviders.push(new ProviderRecord(
        provider.id,
        name.trim().length > 0 ? name.trim() : provider.name,
        provider.appType, provider.mode,
        baseUrl.trim(), apiKey, model.trim(),
        provider.isActive, provider.isActive ? 'dirty' : provider.syncStatus, currentTimestamp(),
        provider.authMode, cloneHeaders(provider.customHeaders), provider.wireApi,
        provider.category, provider.description, provider.websiteUrl,
        provider.icon, provider.iconColor, cloneEndpoints(provider.endpoints),
        provider.healthStatus, provider.healthLatencyMs, provider.lastValidatedAt,
        provider.usageScript, provider.createdAt
      ));
    }
    this.catalog.providers = newProviders;
    return this.persistCatalog();
  }

  removeProvider(id: string): ProviderCatalog {
    this.load();
    const filtered: ProviderRecord[] = [];
    for (let i = 0; i < this.catalog.providers.length; i++) {
      if (this.catalog.providers[i].id !== id) {
        filtered.push(this.catalog.providers[i]);
      }
    }
    this.catalog.providers = filtered;
    if (this.catalog.activeProviderId === id) {
      this.catalog.activeProviderId = this.catalog.providers.length > 0 ? this.catalog.providers[0].id : '';
      const fixed: ProviderRecord[] = [];
      for (let i = 0; i < this.catalog.providers.length; i++) {
        const provider = this.catalog.providers[i];
        const isFirst = i === 0;
        fixed.push(new ProviderRecord(
          provider.id, provider.name, provider.appType, provider.mode,
          provider.baseUrl, provider.apiKey, provider.model,
          isFirst, isFirst ? 'dirty' : provider.syncStatus, provider.updatedAt,
          provider.authMode, cloneHeaders(provider.customHeaders), provider.wireApi,
          provider.category, provider.description, provider.websiteUrl,
          provider.icon, provider.iconColor, cloneEndpoints(provider.endpoints),
          provider.healthStatus, provider.healthLatencyMs, provider.lastValidatedAt,
          provider.usageScript, provider.createdAt
        ));
      }
      this.catalog.providers = fixed;
    }
    return this.persistCatalog();
  }

  activateProvider(id: string): ProviderCatalog {
    this.load();
    let activatedId: string = '';
    let activatedBaseUrl: string = '';
    let activatedApiKey: string = '';
    let activatedModel: string = '';
    const newProviders: ProviderRecord[] = [];
    for (let i = 0; i < this.catalog.providers.length; i++) {
      const provider = this.catalog.providers[i];
      const isActive: boolean = provider.id === id;
      const next: ProviderRecord = new ProviderRecord(
        provider.id, provider.name, provider.appType, provider.mode,
        provider.baseUrl, provider.apiKey, provider.model,
        isActive, isActive ? 'dirty' : provider.syncStatus,
        isActive ? currentTimestamp() : provider.updatedAt,
        provider.authMode, cloneHeaders(provider.customHeaders), provider.wireApi,
        provider.category, provider.description, provider.websiteUrl,
        provider.icon, provider.iconColor, cloneEndpoints(provider.endpoints),
        provider.healthStatus, provider.healthLatencyMs, provider.lastValidatedAt,
        provider.usageScript, provider.createdAt
      );
      if (isActive) {
        activatedId = next.id;
        activatedBaseUrl = next.baseUrl;
        activatedApiKey = next.apiKey;
        activatedModel = next.model;
      }
      newProviders.push(next);
    }
    this.catalog.providers = newProviders;
    this.catalog.activeProviderId = activatedId;
    if (activatedId.length > 0) {
      const saved: CodexProviderConfig = saveEmbeddedCodexProviderConfig(
        activatedBaseUrl,
        activatedApiKey,
        activatedModel
      );
      const afterActivate: ProviderRecord[] = [];
      for (let i = 0; i < this.catalog.providers.length; i++) {
        const provider = this.catalog.providers[i];
        if (provider.id !== activatedId) {
          afterActivate.push(provider);
          continue;
        }
        afterActivate.push(buildRecordFromConfig(provider.id, provider.name, saved, true));
      }
      this.catalog.providers = afterActivate;
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
    const providers: ProviderRecord[] = [];
    for (let i = 0; i < catalog.providers.length; i++) {
      const provider = catalog.providers[i];
      providers.push(new ProviderRecord(
        provider.id, provider.name, provider.appType, provider.mode,
        provider.baseUrl, provider.apiKey, provider.model,
        provider.id === activeId, provider.syncStatus, provider.updatedAt,
        provider.authMode, cloneHeaders(provider.customHeaders), provider.wireApi,
        provider.category, provider.description, provider.websiteUrl,
        provider.icon, provider.iconColor, cloneEndpoints(provider.endpoints),
        provider.healthStatus, provider.healthLatencyMs, provider.lastValidatedAt,
        provider.usageScript, provider.createdAt
      ));
    }
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
