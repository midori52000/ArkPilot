import codexHost, { NativeCodexHostStatus } from 'libcodexhost.so';

export class CodexHostStatus {
  code: number;
  running: boolean;
  serverUrl: string;
  message: string;

  constructor(code: number, running: boolean, serverUrl: string, message: string) {
    this.code = code;
    this.running = running;
    this.serverUrl = serverUrl;
    this.message = message;
  }
}

function normalizeStatus(rawStatus: NativeCodexHostStatus | undefined): CodexHostStatus {
  if (rawStatus === undefined) {
    return new CodexHostStatus(1, false, '', 'native codex host returned no status');
  }

  return new CodexHostStatus(
    rawStatus.code ?? 0,
    rawStatus.running === true,
    rawStatus.serverUrl ?? '',
    rawStatus.message ?? ''
  );
}

export function startEmbeddedCodexHost(codexHome: string, serverUrl: string): CodexHostStatus {
  return normalizeStatus(codexHost.startHost(codexHome, serverUrl));
}

export function getEmbeddedCodexHostStatus(): CodexHostStatus {
  return normalizeStatus(codexHost.getStatus());
}
