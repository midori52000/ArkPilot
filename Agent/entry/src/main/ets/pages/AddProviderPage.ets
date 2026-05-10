import router from '@ohos.router';
import { ProviderPreset, BUILTIN_PROVIDER_PRESETS } from '../apim/ApiTypes';
import { ApiWireFormat, CustomHeadersEntry, ProviderCategory, ProviderRecord } from '../backend/ConsoleModels';
import { configManagerFacade } from '../backend/CodexBackend';

type ToastTone = 'info' | 'success' | 'warning' | 'error';

class UiToastItem {
  id: number;
  tone: ToastTone;
  message: string;

  constructor(id: number, tone: ToastTone, message: string) {
    this.id = id;
    this.tone = tone;
    this.message = message;
  }
}

@Entry
@Component
struct AddProviderPage {
  @State private sparkSeed: number = 0;
  @State private toasts: UiToastItem[] = [];
  @State private toastIdSeed: number = 1;
  @State private selectedPresetId: string = 'custom';
  @State private providerName: string = '';
  @State private providerNote: string = '';
  @State private websiteUrl: string = '';
  @State private apiKey: string = '';
  @State private baseUrl: string = '';
  @State private wireApi: ApiWireFormat = 'anthropic';
  @State private requestFullUrl: boolean = false;
  @State private defaultModel: string = '';
  @State private advancedExpanded: boolean = false;
  @State private editId: string = '';
  @State private contextWindowStr: string = '';

  aboutToAppear(): void {
    const rawParams: Object = router.getParams();
    if (rawParams !== undefined && rawParams !== null) {
      const params = rawParams as Record<string, string>;
      if (params['editId'] !== undefined && params['editId'].length > 0) {
        this.editId = params['editId'];
        this.loadProviderForEdit(this.editId);
        return;
      }
    }
    this.applyPreset(this.selectedPresetId, false);
  }

  private loadProviderForEdit(providerId: string): void {
    const result = configManagerFacade.listProviders();
    if (!result.ok || result.data === null) {
      this.triggerFeedback('加载 Provider 失败。', 'error');
      return;
    }
    const provider = result.data.find((p: ProviderRecord) => p.id === providerId);
    if (provider === undefined) {
      this.triggerFeedback('未找到该 Provider。', 'error');
      return;
    }
    this.providerName = provider.name;
    this.providerNote = provider.description;
    this.websiteUrl = provider.websiteUrl;
    this.apiKey = provider.apiKey;
    this.baseUrl = provider.baseUrl;
    this.wireApi = provider.wireApi;
    this.defaultModel = provider.model;
    this.contextWindowStr = provider.contextWindow > 0 ? String(provider.contextWindow) : '';
    this.selectedPresetId = 'custom';
    this.triggerFeedback('已加载 Provider 数据。', 'success');
  }

  private triggerFeedback(message: string, tone: ToastTone = 'info'): void {
    this.sparkSeed += 1;
    this.showToast(message, tone);
  }

  private showToast(message: string, tone: ToastTone = 'info', duration: number = 1800): void {
    const toastId = this.toastIdSeed;
    this.toastIdSeed += 1;
    this.toasts = [...this.toasts, new UiToastItem(toastId, tone, message)];
    setTimeout(() => {
      this.dismissToast(toastId);
    }, duration);
  }

  private dismissToast(toastId: number): void {
    this.toasts = this.toasts.filter((toast: UiToastItem) => toast.id !== toastId);
  }

  private toneBackground(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#DCFCE7';
      case 'warning':
        return '#FEF3C7';
      case 'error':
        return '#FEE2E2';
      default:
        return '#E0F2FE';
    }
  }

  private toneColor(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#166534';
      case 'warning':
        return '#92400E';
      case 'error':
        return '#B91C1C';
      default:
        return '#0C4A6E';
    }
  }

  private categoryLabel(category: ProviderCategory): string {
    switch (category) {
      case 'official':
        return '官方';
      case 'third_party':
        return '第三方';
      case 'cloud_provider':
        return '云服务商';
      case 'aggregator':
        return '聚合';
      case 'custom':
        return '自定义';
      default:
        return category;
    }
  }

  private presetAccent(presetId: string): string {
    const preset = this.findPreset(presetId);
    if (preset !== null && preset.iconColor.trim().length > 0) {
      return preset.iconColor;
    }
    return '#8B5CF6';
  }

  private presetIconText(): string {
    if (this.selectedPresetId === 'custom') {
      return 'P';
    }
    const preset = this.findPreset(this.selectedPresetId);
    if (preset === null) {
      return 'P';
    }
    const name = preset.name.trim();
    if (name.length > 0) {
      return name.substring(0, 1).toUpperCase();
    }
    return 'P';
  }

  private selectedPreset(): ProviderPreset | null {
    return this.findPreset(this.selectedPresetId);
  }

  private selectedPresetCategoryLabel(): string {
    const preset = this.selectedPreset();
    if (preset === null) {
      return '';
    }
    return this.categoryLabel(preset.category);
  }

  private selectedPresetWireApiLabel(): string {
    const preset = this.selectedPreset();
    if (preset === null) {
      return '';
    }
    return preset.wireApi;
  }

  private findPreset(presetId: string): ProviderPreset | null {
    for (let index = 0; index < BUILTIN_PROVIDER_PRESETS.length; index += 1) {
      if (BUILTIN_PROVIDER_PRESETS[index].id === presetId) {
        return BUILTIN_PROVIDER_PRESETS[index];
      }
    }
    return null;
  }

  private visiblePresets(): ProviderPreset[] {
    const result: ProviderPreset[] = [];
    for (let index = 0; index < BUILTIN_PROVIDER_PRESETS.length; index += 1) {
      result.push(BUILTIN_PROVIDER_PRESETS[index]);
    }
    return result;
  }

  private currentPresetModels(): string[] {
    const preset = this.findPreset(this.selectedPresetId);
    if (preset === null) {
      return [];
    }
    return preset.models;
  }

  private applyPreset(presetId: string, withToast: boolean = true): void {
    this.selectedPresetId = presetId;
    if (presetId === 'custom') {
      this.providerName = '';
      this.providerNote = '';
      this.websiteUrl = '';
      this.apiKey = '';
      this.baseUrl = '';
      this.defaultModel = '';
      this.wireApi = 'anthropic';
      if (withToast) {
        this.triggerFeedback('已切换到自定义配置。', 'info');
      }
      return;
    }

    const preset = this.findPreset(presetId);
    if (preset === null) {
      return;
    }

    this.providerName = preset.name;
    this.providerNote = preset.description;
    this.websiteUrl = preset.websiteUrl;
    this.baseUrl = preset.baseUrl;
    this.defaultModel = preset.defaultModel;
    this.wireApi = preset.wireApi;
    if (withToast) {
      this.triggerFeedback(`已载入 ${preset.name} 预设。`, 'success');
    }
  }

  private submitAddProvider(): void {
    if (this.providerName.trim().length === 0) {
      this.triggerFeedback('请先填写供应商名称。', 'error');
      return;
    }
    if (this.apiKey.trim().length === 0) {
      this.triggerFeedback('请先填写 API Key。', 'error');
      return;
    }
    if (this.baseUrl.trim().length === 0) {
      this.triggerFeedback('请先填写请求地址。', 'error');
      return;
    }

    try {
      const preset: ProviderPreset | null = this.findPreset(this.selectedPresetId);
      const category: ProviderCategory = preset !== null ? preset.category : 'custom';
      const icon: string = preset !== null ? preset.icon : '';
      const iconColor: string = preset !== null ? preset.iconColor : '';
      const defaultModel: string = this.defaultModel.trim().length > 0
        ? this.defaultModel
        : (preset !== null ? preset.defaultModel : '');
      const authMode: string = preset !== null ? preset.authMode : 'apiKey';
      const headers: CustomHeadersEntry[] = [];
      if (preset !== null) {
        for (let hi: number = 0; hi < preset.customHeaders.length; hi += 1) {
          const h = preset.customHeaders[hi];
          headers.push(new CustomHeadersEntry(h.key, h.value));
        }
      }

      const providerId: string = this.editId.length > 0
        ? this.editId
        : `provider-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
      const contextWindow: number = this.contextWindowStr.trim().length > 0
        ? parseInt(this.contextWindowStr.trim()) || 0
        : 0;
      const provider = new ProviderRecord(
        providerId,
        this.providerName,
        'codex',
        'exclusive',
        this.baseUrl,
        this.apiKey,
        defaultModel,
        false,
        'dirty',
        '',
        authMode,
        headers,
        this.wireApi,
        category,
        this.providerNote,
        this.websiteUrl,
        icon,
        iconColor,
        [],
        'unknown',
        0,
        0,
        null,
        Date.now(),
        contextWindow
      );
      const result = configManagerFacade.saveProvider(provider);
      if (!result.ok || result.data === null) {
        const msg = result.error !== null ? result.error.message : '保存 Provider 失败。';
        this.triggerFeedback(msg, 'error');
        return;
      }
      const actionLabel: string = this.editId.length > 0 ? '已更新' : '已添加';
      this.triggerFeedback(`${actionLabel} "${result.data.name}"。`, 'success');
      setTimeout(() => {
        router.back();
      }, 600);
    } catch (err) {
      this.triggerFeedback('保存失败：' + JSON.stringify(err), 'error');
    }
  }

  @Builder
  private backdropLayer() {
    Stack() {
      Column()
        .width(320)
        .height(320)
        .backgroundColor('#D7E8FF')
        .opacity(0.34)
        .borderRadius(180)
        .position({ x: -72, y: -36 })

      Column()
        .width(240)
        .height(240)
        .backgroundColor('#FFF3D6')
        .opacity(0.28)
        .borderRadius(160)
        .position({ x: 760, y: 116 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private particleCluster() {
    Row() {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Column()
          .width(index % 2 === 0 ? 8 : 5)
          .height(index % 2 === 0 ? 8 : 5)
          .backgroundColor(index % 3 === 0 ? '#60A5FA' : (index % 3 === 1 ? '#34D399' : '#FBBF24'))
          .borderRadius(12)
          .opacity((this.sparkSeed + index) % 2 === 0 ? 0.95 : 0.35)
          .scale({ x: (this.sparkSeed + index) % 2 === 0 ? 1.18 : 0.82, y: (this.sparkSeed + index) % 2 === 0 ? 1.18 : 0.82 })
          .margin({ left: index === 0 ? 0 : 8, top: index % 2 === 0 ? 0 : 10 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      })
    }
  }

  @Builder
  private topBar() {
    Row() {
      Button() {
        Row() {
          Text('←')
            .fontSize(16)
            .fontColor('#0F172A')
          Text('返回')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .margin({ left: 8 })
        }
      }
      .height(42)
      .padding({ left: 14, right: 14 })
      .backgroundColor('#FFFFFF')
      .borderRadius(18)
      .border({ width: 1, color: '#D8E1EE' })
      .onClick(() => { router.back(); })

      Column() {
        Text(this.editId.length > 0 ? '编辑供应商' : '添加新供应商')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Text(this.editId.length > 0 ? '修改供应商配置后点击保存' : '独立添加页 · 预设先选 · 前端模拟提交')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 18 })

      Blank()
        .layoutWeight(1)

      this.particleCluster()
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 24, bottom: 16 })
  }

  @Builder
  private formLabel(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor('#0F172A')
      .margin({ top: 16 })
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(10)
  }

  @Builder
  private ghostSwitch(enabled: boolean, key: string, onClick: () => void) {
    Row() {
      Row() {
        Column()
          .width(18)
          .height(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(9)
          .margin({ left: enabled ? 18 : 2 })
          .animation({ duration: 140, curve: Curve.EaseOut })
      }
      .width(40)
      .height(22)
      .backgroundColor(enabled ? '#D946EF' : '#E5E7EB')
      .borderRadius(11)
    }
    .onClick(onClick)
  }

  @Builder
  private sectionCard(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .lineHeight(18)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private presetSection() {
    Column() {
      this.sectionCard('预设供应商', '先选预设，再补齐名称、API Key 和请求地址。')

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('自定义配置')
          .height(36)
          .fontSize(11)
          .fontWeight(this.selectedPresetId === 'custom' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selectedPresetId === 'custom' ? '#FFFFFF' : '#64748B')
          .backgroundColor(this.selectedPresetId === 'custom' ? '#2284F6' : '#F5F7FB')
          .borderRadius(12)
          .border({ width: this.selectedPresetId === 'custom' ? 0 : 1, color: '#E1E7F0' })
          .padding({ left: 14, right: 14 })
          .margin({ right: 10, bottom: 10 })
          .onClick(() => { this.applyPreset('custom'); })

        ForEach(this.visiblePresets(), (preset: ProviderPreset) => {
          Button(preset.name)
            .height(36)
            .fontSize(11)
            .fontWeight(this.selectedPresetId === preset.id ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.selectedPresetId === preset.id ? '#FFFFFF' : '#64748B')
            .backgroundColor(this.selectedPresetId === preset.id ? '#2284F6' : '#F5F7FB')
            .borderRadius(12)
            .border({ width: this.selectedPresetId === preset.id ? 0 : 1, color: '#E1E7F0' })
            .padding({ left: 14, right: 14 })
            .margin({ right: 10, bottom: 10 })
            .onClick(() => { this.applyPreset(preset.id); })
        }, (preset: ProviderPreset) => preset.id)
      }
      .width('100%')
      .margin({ top: 14 })
      
      Row() {
        Text('💡')
          .fontSize(11)
        Text('自定义配置需手动填写所有必要字段')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#64748B')
          .margin({ left: 6 })
      }
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(24)
  }

  @Builder
  private previewBadge() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(78)
          .height(78)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E3E8F2' })
          .borderRadius(22)

        Text(this.presetIconText())
          .copyOption(CopyOptions.None)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.presetAccent(this.selectedPresetId))
      }

      if (this.selectedPresetId !== 'custom' && this.selectedPreset() !== null) {
        Row() {
          this.chip(this.selectedPresetCategoryLabel(), '#EEF4FF', '#3563C8')
          this.chip(this.selectedPresetWireApiLabel(), '#F8FAFC', '#64748B')
        }
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 14, bottom: 8 })
  }

  @Builder
  private requestHint() {
    Row() {
      Text('💡')
        .fontSize(11)
      Text('填写兼容 Claude API 的服务端点地址，不要以斜杠结尾')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#D97706')
        .margin({ left: 6 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#FFF9E9')
    .border({ width: 1, color: '#FACC15' })
    .borderRadius(14)
    .margin({ top: 10 })
  }

  @Builder
  private advancedSection() {
    Column() {
      Row() {
        Text(this.advancedExpanded ? '⌄' : '›')
          .fontSize(14)
          .fontColor('#334155')
        Text('高级选项')
          .copyOption(CopyOptions.None)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.advancedExpanded = !this.advancedExpanded; })

      Text('包含 API 格式、认证字段、模型映射等配置。大多数场景下保持默认即可。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#94A3B8')
        .lineHeight(18)
        .margin({ top: 8 })

      if (this.advancedExpanded) {
        Column() {
          this.formLabel('Wire API')
          Row() {
            ForEach(['responses', 'chat', 'anthropic'], (api: string) => {
              Button(api)
                .height(36)
                .fontSize(11)
                .fontWeight(this.wireApi === api ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.wireApi === api ? '#FFFFFF' : '#64748B')
                .backgroundColor(this.wireApi === api ? '#2284F6' : '#F5F7FB')
                .borderRadius(12)
                .border({ width: this.wireApi === api ? 0 : 1, color: '#E1E7F0' })
                .padding({ left: 14, right: 14 })
                .margin({ right: 10 })
                .onClick(() => {
                  this.wireApi = api as ApiWireFormat;
                  this.triggerFeedback(`已切换为 ${api} 格式。`, 'info');
                })
            }, (api: string) => api)
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private contentPanel() {
    Column() {
      this.presetSection()

      this.previewBadge()

      Row() {
        Column() {
          this.formLabel('供应商名称')
          TextInput({ text: $$this.providerName, placeholder: '例如：Claude 官方' })
            .width('100%').height(42).backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
            .padding({ left: 14, right: 14 }).margin({ top: 8 })
        }
        .layoutWeight(1)

        Column() {
          this.formLabel('备注')
          TextInput({ text: $$this.providerNote, placeholder: '例如：公司专用账号' })
            .width('100%').height(42).backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
            .padding({ left: 14, right: 14 }).margin({ top: 8 })
        }
        .layoutWeight(1)
        .margin({ left: 14 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.formLabel('官网链接')
      TextInput({ text: $$this.websiteUrl, placeholder: 'https://example.com（可选）' })
        .width('100%').height(42).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
        .padding({ left: 14, right: 14 }).margin({ top: 8 })

      this.formLabel('API Key')
      TextInput({ text: $$this.apiKey, placeholder: '只需要填这里，下方配置会自动填充' })
        .width('100%').height(42).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
        .padding({ left: 14, right: 14 }).margin({ top: 8 })

      this.formLabel('默认模型')
      TextInput({ text: $$this.defaultModel, placeholder: '例如：claude-sonnet-4-6' })
        .width('100%').height(42).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
        .padding({ left: 14, right: 14 }).margin({ top: 8 })

      if (this.currentPresetModels().length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.currentPresetModels(), (model: string) => {
            Button(model)
              .height(28)
              .fontSize(10)
              .fontWeight(this.defaultModel === model ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.defaultModel === model ? '#FFFFFF' : '#64748B')
              .backgroundColor(this.defaultModel === model ? '#2284F6' : '#F5F7FB')
              .borderRadius(10)
              .border({ width: this.defaultModel === model ? 0 : 1, color: '#E1E7F0' })
              .padding({ left: 10, right: 10 })
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.defaultModel = model;
                this.triggerFeedback(`已选择模型 ${model}`, 'success');
              })
          }, (model: string) => model)
        }
        .width('100%')
        .margin({ top: 10 })
      }

      this.formLabel('上下文窗口大小（可选）')
      TextInput({ text: $$this.contextWindowStr, placeholder: '例如：1000000（留空使用模型默认值）' })
        .width('100%').height(42).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
        .padding({ left: 14, right: 14 }).margin({ top: 8 })
        .type(InputType.Number)

      Row() {
        Text('请求地址')
          .copyOption(CopyOptions.None)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Row() {
          Text('完整 URL')
            .copyOption(CopyOptions.None)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ right: 8 })
          this.ghostSwitch(this.requestFullUrl, 'request-full-url', () => {
            this.requestFullUrl = !this.requestFullUrl;
            this.triggerFeedback(this.requestFullUrl ? '已开启完整 URL 模式。' : '已关闭完整 URL 模式。', 'info');
          })
        }
        .margin({ left: 14 })
        Blank()
          .layoutWeight(1)
        Row() {
          Text('⚡')
            .fontSize(11)
            .fontColor('#64748B')
          Text('管理与测速')
            .copyOption(CopyOptions.None)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ left: 6 })
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(8)
        .backgroundColor('#F8FAFC')
        .border({ width: 1, color: '#E2E8F0' })
        .onClick(() => { this.triggerFeedback('测速功能将在后端接入后可用。', 'info'); })
      }
      .width('100%')
      .margin({ top: 16 })

      TextInput({ text: $$this.baseUrl, placeholder: 'https://your-api-endpoint.com' })
        .width('100%').height(42).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#DEE6F2' }).borderRadius(14)
        .padding({ left: 14, right: 14 }).margin({ top: 8 })
      this.requestHint()
      this.advancedSection()
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(24)
  }

  @Builder
  private bottomBar() {
    Row() {
      Blank()
        .layoutWeight(1)

      Button('取消')
        .height(40)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#64748B')
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
        .border({ width: 1, color: '#D5E0ED' })
        .padding({ left: 18, right: 18 })
        .onClick(() => { router.back(); })

      Button(this.editId.length > 0 ? '保存' : '+ 添加')
        .height(40)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor('#2284F6')
        .borderRadius(14)
        .padding({ left: 20, right: 20 })
        .margin({ left: 12 })
        .onClick(() => { this.submitAddProvider(); })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E3EAF4' })
    .borderRadius(22)
    .margin({ top: 16 })
  }

  @Builder
  private toastHost() {
    Column() {
      ForEach(this.toasts, (toast: UiToastItem) => {
        Row() {
          Column()
            .width(8)
            .height(8)
            .backgroundColor(this.toneColor(toast.tone))
            .borderRadius(8)

          Text(toast.message)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#0F172A')
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .constraintSize({ maxWidth: 360 })
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(this.toneBackground(toast.tone))
        .border({ width: 1, color: '#FFFFFF' })
        .borderRadius(18)
        .margin({ top: 10 })
      }, (toast: UiToastItem) => `${toast.id}`)
    }
    .alignItems(HorizontalAlign.End)
    .position({ x: 0, y: 28 })
    .width('100%')
    .padding({ right: 28 })
  }

  build() {
    Stack() {
      this.backdropLayer()

      Column() {
        this.topBar()

        Scroll() {
          Column() {
            this.contentPanel()
            this.bottomBar()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 28, right: 28, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      this.toastHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E9EEF6')
  }
}
