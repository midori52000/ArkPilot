import {
  ProviderRecord, ProviderCategory, ApiWireFormat, ProviderSyncStatus,
  EndpointEntry, CustomHeadersEntry, UsageScriptEntry
} from '../backend/ConsoleModels';

export { ProviderRecord, ProviderCategory, ApiWireFormat, ProviderSyncStatus, EndpointEntry, CustomHeadersEntry, UsageScriptEntry } from '../backend/ConsoleModels';

export class ProviderPreset {
  id: string;
  name: string;
  category: ProviderCategory;
  baseUrl: string;
  defaultModel: string;
  models: string[];
  wireApi: ApiWireFormat;
  websiteUrl: string;
  apiKeyUrl: string;
  icon: string;
  iconColor: string;
  description: string;
  authMode: string;
  customHeaders: CustomHeadersEntry[];
  isOfficial: boolean;

  constructor(
    id: string, name: string, category: ProviderCategory,
    baseUrl: string, defaultModel: string, models: string[],
    wireApi: ApiWireFormat, websiteUrl: string, apiKeyUrl: string,
    icon: string, iconColor: string, description: string,
    authMode: string, customHeaders: CustomHeadersEntry[],
    isOfficial: boolean
  ) {
    this.id = id;
    this.name = name;
    this.category = category;
    this.baseUrl = baseUrl;
    this.defaultModel = defaultModel;
    this.models = models;
    this.wireApi = wireApi;
    this.websiteUrl = websiteUrl;
    this.apiKeyUrl = apiKeyUrl;
    this.icon = icon;
    this.iconColor = iconColor;
    this.description = description;
    this.authMode = authMode;
    this.customHeaders = customHeaders;
    this.isOfficial = isOfficial;
  }

  toProviderRecord(apiKey: string): ProviderRecord {
    const headers: CustomHeadersEntry[] = [];
    for (let i = 0; i < this.customHeaders.length; i++) {
      const h = this.customHeaders[i];
      headers.push(new CustomHeadersEntry(h.key, h.value));
    }
    return new ProviderRecord(
      `provider-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
      this.name, 'codex', 'exclusive',
      this.baseUrl, apiKey, this.defaultModel,
      false, 'dirty', '',
      this.authMode, headers,
      this.wireApi, this.category,
      '', this.websiteUrl,
      this.icon, this.iconColor,
      [], 'unknown', 0, 0,
      null, Date.now()
    );
  }
}

export const BUILTIN_PROVIDER_PRESETS: ProviderPreset[] = [
  new ProviderPreset(
    'openai-official', 'OpenAI Official', 'official',
    'https://api.openai.com/v1', 'gpt-5.1',
    ['gpt-5.1', 'gpt-5', 'gpt-4.1', 'gpt-4o', 'gpt-4.1-mini', 'o4-mini'],
    'responses', 'https://platform.openai.com', 'https://platform.openai.com/api-keys',
    'openai', '#00A67E', 'OpenAI 官方 API，支持 Responses/Chat API',
    'apiKey', [], true
  ),
  new ProviderPreset(
    'anthropic-official', 'Anthropic Official', 'official',
    'https://api.anthropic.com/v1', 'claude-sonnet-4-6',
    ['claude-opus-4-7', 'claude-sonnet-4-6', 'claude-haiku-4-5'],
    'anthropic', 'https://console.anthropic.com', 'https://console.anthropic.com/settings/keys',
    'anthropic', '#D97757', 'Anthropic 官方 API，Claude 系列模型',
    'apiKey', [], true
  ),
  new ProviderPreset(
    'google-official', 'Google AI Official', 'official',
    'https://generativelanguage.googleapis.com/v1beta', 'gemini-2.5-pro',
    ['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-2.0-flash'],
    'chat', 'https://aistudio.google.com', 'https://aistudio.google.com/apikey',
    'google', '#4285F4', 'Google AI 官方 API，Gemini 系列模型',
    'apiKey', [], true
  ),
  new ProviderPreset(
    'aws-bedrock', 'AWS Bedrock', 'cloud_provider',
    'https://bedrock-runtime.us-east-1.amazonaws.com', 'claude-sonnet-4-6',
    ['claude-sonnet-4-6', 'claude-haiku-4-5', 'claude-opus-4-7'],
    'anthropic', 'https://aws.amazon.com/bedrock/', 'https://console.aws.amazon.com/bedrock',
    'aws', '#FF9900', 'AWS Bedrock 托管服务，需配置 IAM 认证',
    'apiKey', [], true
  ),
  new ProviderPreset(
    'openrouter', 'OpenRouter', 'aggregator',
    'https://openrouter.ai/api/v1', 'openai/gpt-5.1',
    ['openai/gpt-5.1', 'anthropic/claude-sonnet-4-6', 'google/gemini-2.5-pro',
     'meta-llama/llama-4-maverick', 'deepseek/deepseek-v3'],
    'chat', 'https://openrouter.ai', 'https://openrouter.ai/keys',
    'openrouter', '#6366F1', 'OpenRouter 多模型聚合，统一 API 接入',
    'apiKey', [new CustomHeadersEntry('HTTP-Referer', 'https://github.com/ArkPilot'),
              new CustomHeadersEntry('X-Title', 'ArkPilot')], false
  ),
  new ProviderPreset(
    'siliconflow', 'SiliconFlow (硅基流动)', 'third_party',
    'https://api.siliconflow.cn/v1', 'deepseek-ai/DeepSeek-V3',
    ['deepseek-ai/DeepSeek-V3', 'deepseek-ai/DeepSeek-R1',
     'Qwen/Qwen3-235B-A22B', 'Pro/zai-org/GLM-4.7'],
    'chat', 'https://siliconflow.cn', 'https://cloud.siliconflow.cn/account/ak',
    'siliconflow', '#5B21B6', '硅基流动，国产模型聚合平台',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'deepseek', 'DeepSeek Official', 'third_party',
    'https://api.deepseek.com/v1', 'deepseek-chat',
    ['deepseek-chat', 'deepseek-reasoner'],
    'chat', 'https://platform.deepseek.com', 'https://platform.deepseek.com/api_keys',
    'deepseek', '#4D6BFE', 'DeepSeek 官方 API',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'zhipu', 'ZhipuAI (智谱)', 'third_party',
    'https://open.bigmodel.cn/api/paas/v4', 'glm-4.7',
    ['glm-4.7', 'glm-4.5', 'glm-4-flash'],
    'chat', 'https://open.bigmodel.cn', 'https://open.bigmodel.cn/usercenter/apikeys',
    'zhipu', '#1677FF', '智谱 AI 开放平台，GLM 系列模型',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'moonshot', 'Moonshot (月之暗面)', 'third_party',
    'https://api.moonshot.cn/v1', 'moonshot-v1-8k',
    ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    'chat', 'https://platform.moonshot.cn', 'https://platform.moonshot.cn/console/api-keys',
    'moonshot', '#000000', 'Moonshot AI / Kimi 开放平台',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'dashscope', 'DashScope (阿里百炼)', 'third_party',
    'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen3-235b-a22b',
    ['qwen3-235b-a22b', 'qwen3-32b', 'qwen-max', 'qwen-plus'],
    'chat', 'https://bailian.console.aliyun.com', 'https://bailian.console.aliyun.com/?apiKey=1',
    'alibaba', '#FF6A00', '阿里云百炼平台，通义千问系列模型',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'volcengine', 'Volcengine (火山引擎)', 'third_party',
    'https://ark.cn-beijing.volces.com/api/v3', 'deepseek-v3-250324',
    ['deepseek-v3-250324', 'deepseek-r1-250528', 'doubao-1.5-pro-256k'],
    'chat', 'https://console.volcengine.com/ark', 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey',
    'bytedance', '#325AB4', '火山引擎 Ark，豆包/DeepSeek 等模型',
    'apiKey', [], false
  ),
  new ProviderPreset(
    'newapi', 'NewAPI (通用中转)', 'aggregator',
    'https://your-newapi-instance.com/v1', 'gpt-4o',
    ['gpt-4o', 'claude-sonnet-4-6', 'gemini-2.5-pro'],
    'chat', 'https://github.com/Calcium-Ion/new-api', '',
    'newapi', '#10B981', 'NewAPI 自建中转站，支持多模型接入',
    'apiKey', [], false
  ),
];

export function findPresetById(id: string): ProviderPreset | undefined {
  const presets = BUILTIN_PROVIDER_PRESETS;
  for (let i = 0; i < presets.length; i++) {
    if (presets[i].id === id) {
      return presets[i];
    }
  }
  return undefined;
}

export function getPresetsByCategory(category: ProviderCategory): ProviderPreset[] {
  const result: ProviderPreset[] = [];
  const presets = BUILTIN_PROVIDER_PRESETS;
  for (let i = 0; i < presets.length; i++) {
    if (presets[i].category === category) {
      result.push(presets[i]);
    }
  }
  return result;
}

export class ApiValidationResult {
  success: boolean;
  statusCode: number;
  latencyMs: number;
  errorMessage: string;
  modelsCount: number;
  accountInfo: string;

  constructor(
    success: boolean, statusCode: number, latencyMs: number,
    errorMessage: string, modelsCount: number, accountInfo: string
  ) {
    this.success = success;
    this.statusCode = statusCode;
    this.latencyMs = latencyMs;
    this.errorMessage = errorMessage;
    this.modelsCount = modelsCount;
    this.accountInfo = accountInfo;
  }
}

export class ChatProbeResult {
  success: boolean;
  latencyMs: number;
  statusCode: number;
  errorMessage: string;

  constructor(success: boolean, latencyMs: number, statusCode: number, errorMessage: string) {
    this.success = success;
    this.latencyMs = latencyMs;
    this.statusCode = statusCode;
    this.errorMessage = errorMessage;
  }
}

export class EndpointSpeedResult {
  endpointUrl: string;
  latencyMs: number;
  statusCode: number;
  success: boolean;
  errorMessage: string;
  timestamp: number;
  chatProbe: ChatProbeResult | null;

  constructor(
    endpointUrl: string, latencyMs: number,
    statusCode: number, success: boolean,
    errorMessage: string, timestamp: number,
    chatProbe: ChatProbeResult | null = null
  ) {
    this.endpointUrl = endpointUrl;
    this.latencyMs = latencyMs;
    this.statusCode = statusCode;
    this.success = success;
    this.errorMessage = errorMessage;
    this.timestamp = timestamp;
    this.chatProbe = chatProbe;
  }
}

export class UsageQueryResult {
  success: boolean;
  providerName: string;
  planName: string;
  totalAmount: number;
  usedAmount: number;
  remainingAmount: number;
  unit: string;
  extraInfo: string;
  queriedAt: number;
  errorMessage: string;

  constructor(
    success: boolean, providerName: string, planName: string,
    totalAmount: number, usedAmount: number, remainingAmount: number,
    unit: string, extraInfo: string, queriedAt: number, errorMessage: string
  ) {
    this.success = success;
    this.providerName = providerName;
    this.planName = planName;
    this.totalAmount = totalAmount;
    this.usedAmount = usedAmount;
    this.remainingAmount = remainingAmount;
    this.unit = unit;
    this.extraInfo = extraInfo;
    this.queriedAt = queriedAt;
    this.errorMessage = errorMessage;
  }
}

export enum ApiErrorCode {
  PRESET_NOT_FOUND = 'PRESET_NOT_FOUND',
  INVALID_NAME = 'INVALID_NAME',
  INVALID_URL = 'INVALID_URL',
  PROVIDER_NOT_FOUND = 'PROVIDER_NOT_FOUND',
  CANNOT_DELETE_ACTIVE = 'CANNOT_DELETE_ACTIVE',
  VALIDATION_FAILED = 'VALIDATION_FAILED',
  SYNC_FAILED = 'SYNC_FAILED',
  MODEL_FETCH_FAILED = 'MODEL_FETCH_FAILED',
  USAGE_NOT_CONFIGURED = 'USAGE_NOT_CONFIGURED',
  USAGE_UNSUPPORTED = 'USAGE_UNSUPPORTED',
  CUSTOM_SCRIPT_NOT_IMPLEMENTED = 'CUSTOM_SCRIPT_NOT_IMPLEMENTED',
  TOO_MANY_ENDPOINTS = 'TOO_MANY_ENDPOINTS',
}

export class ApiError extends Error {
  code: ApiErrorCode;
  context: string;
  suggestion: string;

  constructor(code: ApiErrorCode, context: string, suggestion: string) {
    super(`[${code}] ${context}`);
    this.name = 'ApiError';
    this.code = code;
    this.context = context;
    this.suggestion = suggestion;
  }
}

const ERROR_MESSAGES: string[] = [];
ERROR_MESSAGES[0] = '预设不存在，请刷新预设列表';
ERROR_MESSAGES[1] = '名称不合法，不能为空且不超过 100 个字符';
ERROR_MESSAGES[2] = 'URL 格式不合法，请输入完整地址（含 http:// 或 https://）';
ERROR_MESSAGES[3] = '未找到指定的 Provider';
ERROR_MESSAGES[4] = '无法删除当前已激活的 Provider，请先切换到其他 Provider';
ERROR_MESSAGES[5] = 'API Key 连通性验证失败';
ERROR_MESSAGES[6] = '写入配置文件失败，Provider 切换可能未生效';
ERROR_MESSAGES[7] = '获取模型列表失败，请检查 Base URL 和 API Key 是否正确';
ERROR_MESSAGES[8] = '未配置用量查询';
ERROR_MESSAGES[9] = '不支持的用量查询类型';
ERROR_MESSAGES[10] = '自定义用量脚本暂不支持';
ERROR_MESSAGES[11] = '端点数量超过上限';

export function getApiErrorMessage(code: ApiErrorCode): string {
  switch (code) {
    case ApiErrorCode.PRESET_NOT_FOUND: return ERROR_MESSAGES[0];
    case ApiErrorCode.INVALID_NAME: return ERROR_MESSAGES[1];
    case ApiErrorCode.INVALID_URL: return ERROR_MESSAGES[2];
    case ApiErrorCode.PROVIDER_NOT_FOUND: return ERROR_MESSAGES[3];
    case ApiErrorCode.CANNOT_DELETE_ACTIVE: return ERROR_MESSAGES[4];
    case ApiErrorCode.VALIDATION_FAILED: return ERROR_MESSAGES[5];
    case ApiErrorCode.SYNC_FAILED: return ERROR_MESSAGES[6];
    case ApiErrorCode.MODEL_FETCH_FAILED: return ERROR_MESSAGES[7];
    case ApiErrorCode.USAGE_NOT_CONFIGURED: return ERROR_MESSAGES[8];
    case ApiErrorCode.USAGE_UNSUPPORTED: return ERROR_MESSAGES[9];
    case ApiErrorCode.CUSTOM_SCRIPT_NOT_IMPLEMENTED: return ERROR_MESSAGES[10];
    case ApiErrorCode.TOO_MANY_ENDPOINTS: return ERROR_MESSAGES[11];
  }
}
