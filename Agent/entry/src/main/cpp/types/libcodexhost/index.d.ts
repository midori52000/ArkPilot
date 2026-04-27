export interface NativeCodexHostStatus {
  code: number;
  running: boolean;
  serverUrl: string;
  message: string;
}

interface NativeCodexHostModule {
  startHost: (codexHome?: string, serverUrl?: string) => NativeCodexHostStatus;
  getStatus: () => NativeCodexHostStatus;
  isHostRunning: () => boolean;
  getLastMessage: () => string;
  getServerUrl: () => string;
}

declare const codexHost: NativeCodexHostModule;

export default codexHost;
