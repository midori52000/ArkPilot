export interface NativeCodexHostStatus {
  code: number;
  running: boolean;
  serverUrl: string;
  message: string;
}

export interface NativeCodexProviderConfig {
  baseUrl?: string;
  base_url?: string;
  apiKey?: string;
  api_key?: string;
  model?: string;
}

export interface NativeCodexProviderRecord {
  id?: string;
  name?: string;
  appType?: string;
  mode?: string;
  baseUrl?: string;
  base_url?: string;
  apiKey?: string;
  api_key?: string;
  model?: string;
  isActive?: boolean;
  syncStatus?: string;
  updatedAt?: string;
}

export interface NativeCodexProviderCatalog {
  version?: number;
  activeProviderId?: string;
  providers?: NativeCodexProviderRecord[];
  updatedAt?: string;
}

export interface NativeWorkspaceAccessStatus {
  rootPath?: string;
  accessKind?: string;
  permissionState?: string;
  writable?: boolean;
  exists?: boolean;
  message?: string;
}

export interface EntryBridgeModule {
  startHost: (codexHome?: string, serverUrl?: string) => NativeCodexHostStatus;
  getStatus: () => NativeCodexHostStatus;
  isHostRunning: () => boolean;
  getLastMessage: () => string;
  getServerUrl: () => string;
  getProviderConfig: (codexHome?: string) => string;
  saveProviderConfig: (codexHome?: string, baseUrl?: string, apiKey?: string, model?: string) => string;
  getProviderCatalog: (codexHome?: string) => string;
  saveProviderCatalog: (codexHome?: string, catalogJson?: string) => string;
  getSkillsRegistry: (codexHome?: string) => string;
  saveSkillsRegistry: (codexHome?: string, registryJson?: string) => number;
  getSkillsRepos: (codexHome?: string) => string;
  saveSkillsRepos: (codexHome?: string, reposJson?: string) => number;
  computeDirHash: (dirPath?: string) => string;
  getSkillsBackups: (codexHome?: string) => string;
  createSkillBackup: (codexHome?: string, skillDir?: string, skillJson?: string) => string;
  deleteSkillBackup: (codexHome?: string, backupId?: string) => number;
  installSkillFromDir: (codexHome?: string, sourceDir?: string, skillJson?: string) => string;
  uninstallSkill: (codexHome?: string, skillId?: string) => string;
  setSkillEnabled: (codexHome?: string, skillId?: string, enabled?: number) => string;
  reconcileSkills: (codexHome?: string) => string;
  getPromptsRegistry: (codexHome?: string) => string;
  savePromptsRegistry: (codexHome?: string, registryJson?: string) => number;
  readAgentsMd: (codexHome?: string) => string;
  writeAgentsMd: (codexHome?: string, content?: string) => number;
  enablePrompt: (codexHome?: string, promptId?: string) => string;
  disableAllPrompts: (codexHome?: string) => number;
  initialize: (configJson?: string) => string;
  threadStart: (paramsJson?: string) => string;
  threadList: (paramsJson?: string) => string;
  threadRead: (paramsJson?: string) => string;
  threadResume: (paramsJson?: string) => string;
  threadNameSet: (paramsJson?: string) => string;
  threadArchive: (paramsJson?: string) => string;
  turnStart: (paramsJson?: string) => string;
  turnEvents: (threadId?: string, turnId?: string) => string;
  turnPoll: (threadId?: string, turnId?: string) => string;
  approvalPoll: () => string;
  approvalApprove: (paramsJson?: string) => number;
  approvalDecline: (paramsJson?: string) => number;
  mcpStatusList: (paramsJson?: string) => string;
  mcpConfigRead: (paramsJson?: string) => string;
  mcpConfigWrite: (paramsJson?: string) => number;
  mcpConfigBatchWrite: (paramsJson?: string) => number;
  mcpConfigAdd: (paramsJson?: string) => number;
  mcpConfigRemove: (paramsJson?: string) => number;
  mcpReload: () => number;
  mcpOauthStart: (paramsJson?: string) => string;
  accountLogin: (paramsJson?: string) => string;
  accountRead: () => string;
  checkWorkspaceAccess: (paramsJson?: string) => string;
}

declare const entry: EntryBridgeModule;

export default entry;
