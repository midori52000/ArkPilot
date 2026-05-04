import { PromptsViewModel } from '../prompts/PromptsViewModel';
import { PromptsBackendService } from '../prompts/PromptsBackendService';
import { PromptRecord } from '../prompts/PromptTypes';

@Component
export struct PromptsPage {
  @Prop codexHome: string = '';
  @State private promptsViewModel: PromptsViewModel = new PromptsViewModel(new PromptsBackendService(''));
  @State private showDeleteConfirm: boolean = false;
  @State private deleteTarget: PromptRecord | null = null;

  aboutToAppear(): void {
    if (this.codexHome.length > 0) {
      this.promptsViewModel = new PromptsViewModel(new PromptsBackendService(this.codexHome));
    }
    this.promptsViewModel.loadAll();
  }

  private formatTimestamp(ts: number): string {
    if (ts <= 0) {
      return '-';
    }
    return new Date(ts).toISOString().replace('T', ' ').substring(0, 19);
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(10)
  }

  build() {
    Row() {
      // Left: Prompt list
      Column() {
        Row() {
          Text('Prompts')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')
          Blank()
          Button('刷新')
            .fontSize(12)
            .height(28)
            .backgroundColor('#FFFFFF')
            .fontColor('#334155')
            .borderRadius(14)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => this.promptsViewModel.loadAll())
            .margin({ right: 8 })
          Button('新建')
            .fontSize(12)
            .height(28)
            .backgroundColor('#111827')
            .fontColor('#FFFFFF')
            .borderRadius(14)
            .onClick(() => this.promptsViewModel.startEditing(null))
        }
        .width('100%')
        .padding(12)

        Row() {
          Text('共 ' + this.promptsViewModel.state.prompts.length + ' 个 · 已启用: ' + this.promptsViewModel.activePromptName)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#888')
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 8 })

        Divider().color('#E5E7EB')

        if (this.promptsViewModel.state.loading) {
          Column() {
            LoadingProgress().width(40).height(40)
            Text('加载中...')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor('#999')
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.promptsViewModel.state.prompts.length === 0) {
          Column() {
            Text('还没有 Prompt')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(14)
              .fontColor('#333')
            Text('创建一个自定义指令，启用后将写入 AGENTS.md')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor('#999')
              .margin({ top: 4 })
            Row() {
              Button('+ 创建第一个 Prompt')
                .fontSize(13)
                .backgroundColor('#111827')
                .fontColor('#FFFFFF')
                .borderRadius(14)
                .onClick(() => this.promptsViewModel.startEditing(null))
              Button('从 AGENTS.md 导入')
                .fontSize(13)
                .backgroundColor('#FFFFFF')
                .fontColor('#334155')
                .borderRadius(14)
                .border({ width: 1, color: '#CBD5E1' })
                .margin({ left: 8 })
                .onClick(() => this.promptsViewModel.importFromFile())
            }
            .margin({ top: 16 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.promptsViewModel.state.prompts, (prompt: PromptRecord) => {
              ListItem() {
                Column() {
                  Row() {
                    Column() {
                      Row() {
                        Text(prompt.enabled ? '●' : '○')
                          .copyOption(CopyOptions.LocalDevice)
                          .fontSize(14)
                          .fontColor(prompt.enabled ? '#4ADE80' : '#ccc')
                          .margin({ right: 6 })

                        Text(prompt.name)
                          .copyOption(CopyOptions.LocalDevice)
                          .fontSize(14)
                          .fontColor('#0F172A')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')

                      if (prompt.description.length > 0) {
                        Text(prompt.description)
                          .copyOption(CopyOptions.LocalDevice)
                          .fontSize(11)
                          .fontColor('#999')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .margin({ top: 2 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Row() {
                      Button('✎')
                        .fontSize(12)
                        .width(28)
                        .height(28)
                        .backgroundColor('#00000000')
                        .onClick(() => this.promptsViewModel.startEditing(prompt))

                      Button('✕')
                        .fontSize(12)
                        .width(28)
                        .height(28)
                        .backgroundColor('#00000000')
                        .onClick(() => {
                          this.deleteTarget = prompt;
                          this.showDeleteConfirm = true;
                        })
                    }
                  }
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding(12)
                .backgroundColor(prompt.enabled ? '#F0FDF4' : '#FFFFFF')
                .border({ width: 1, color: prompt.enabled ? '#BBF7D0' : '#E5E7EB' })
                .borderRadius(14)
                .margin({ bottom: 8 })
                .opacity(this.promptsViewModel.state.operating ? 0.6 : 1.0)
                .onClick(() => {
                  if (!prompt.enabled && !this.promptsViewModel.state.operating) {
                    this.promptsViewModel.enablePrompt(prompt.id);
                  }
                })
              }
            }, (prompt: PromptRecord) => prompt.id)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }

        if (this.promptsViewModel.state.statusMessage.length > 0) {
          Row() {
            Text(this.promptsViewModel.state.statusMessage)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor(this.promptsViewModel.state.statusType === 'error' ? '#B91C1C' :
                this.promptsViewModel.state.statusType === 'success' ? '#15803D' : '#334155')
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .backgroundColor(this.promptsViewModel.state.statusType === 'error' ? '#FEF2F2' :
            this.promptsViewModel.state.statusType === 'success' ? '#F0FDF4' : '#F8FAFC')
          .borderRadius(8)
          .margin({ top: 4 })
        }

        Row() {
          Button('从 AGENTS.md 导入')
            .fontSize(12)
            .height(32)
            .backgroundColor('#FFFFFF')
            .fontColor('#334155')
            .borderRadius(14)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => this.promptsViewModel.importFromFile())
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 4 })

        if (this.promptsViewModel.activePrompt !== null) {
          Button('禁用全部 Prompt')
            .fontSize(12)
            .width('100%')
            .height(36)
            .backgroundColor('#FFF3F3')
            .fontColor('#B91C1C')
            .borderRadius(14)
            .margin({ top: 4 })
            .enabled(!this.promptsViewModel.state.operating)
            .onClick(() => this.promptsViewModel.disableAll())
        }

        if (this.promptsViewModel.state.operating) {
          Row() {
            LoadingProgress().width(20).height(20)
            Text('操作中...')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor('#999')
              .margin({ left: 8 })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 4 })
        }
      }
      .width(280)
      .height('100%')
      .backgroundColor('#FAFAFA')
      .padding(8)

      Divider().vertical(true).color('#E5E7EB')

      // Right: Editor or Preview
      if (this.promptsViewModel.state.editingPrompt !== null) {
        Column() {
          Row() {
            Text(this.promptsViewModel.state.editingPrompt.id.startsWith('prompt-') && this.promptsViewModel.state.editingPrompt.description.length === 0
              ? '新建 Prompt'
              : '编辑 Prompt')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
            Blank()
            Button(this.promptsViewModel.state.saving ? '保存中...' : '保存')
              .fontSize(13)
              .height(34)
              .backgroundColor('#111827')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .enabled(!this.promptsViewModel.state.saving)
              .onClick(() => {
                const editing = this.promptsViewModel.state.editingPrompt;
                if (editing) {
                  if (!this.promptsViewModel.activePrompt) {
                    editing.enabled = true;
                  }
                  this.promptsViewModel.savePrompt(editing);
                }
              })
              .margin({ right: 8 })
            Button('取消')
              .fontSize(13)
              .height(34)
              .backgroundColor('#FFFFFF')
              .fontColor('#334155')
              .borderRadius(14)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => this.promptsViewModel.cancelEditing())
          }
          .width('100%')
          .padding(12)

          Divider().color('#E5E7EB')

          Row() {
            Text('名称')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(13)
              .fontColor('#334155')
              .width(60)
            TextInput({ text: this.promptsViewModel.state.editingPrompt?.name ?? '' })
              .layoutWeight(1)
              .height(38)
              .fontSize(13)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .padding({ left: 10, right: 10 })
              .onChange((value: string) => {
                if (this.promptsViewModel.state.editingPrompt) {
                  this.promptsViewModel.state.editingPrompt.name = value;
                }
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          Row() {
            Text('描述')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(13)
              .fontColor('#334155')
              .width(60)
            TextInput({ text: this.promptsViewModel.state.editingPrompt?.description ?? '' })
              .layoutWeight(1)
              .height(38)
              .fontSize(13)
              .backgroundColor('#FFFFFF')
              .borderRadius(12)
              .padding({ left: 10, right: 10 })
              .onChange((value: string) => {
                if (this.promptsViewModel.state.editingPrompt) {
                  this.promptsViewModel.state.editingPrompt.description = value;
                }
              })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          Row() {
            Text('此 Prompt 启用后将写入 AGENTS.md，Agent 启动时自动加载。切换后请新建会话以生效。')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(11)
              .fontColor('#94A3B8')
              .lineHeight(16)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8 })

          TextArea({ text: this.promptsViewModel.state.editingPrompt?.content ?? '' })
            .layoutWeight(1)
            .fontFamily('monospace')
            .fontSize(13)
            .onChange((value: string) => {
              if (this.promptsViewModel.state.editingPrompt) {
                this.promptsViewModel.state.editingPrompt.content = value;
              }
            })
            .padding(12)
        }
        .layoutWeight(1)
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('AGENTS.md 实时预览')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
            Blank()
            Button('刷新')
              .fontSize(12)
              .height(32)
              .backgroundColor('#FFFFFF')
              .fontColor('#334155')
              .borderRadius(14)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => this.promptsViewModel.reloadLiveContent())
          }
          .width('100%')
          .padding(12)

          Divider().color('#E5E7EB')

          if (this.promptsViewModel.activePrompt) {
            Row() {
              Text('当前启用: ' + this.promptsViewModel.activePrompt.name)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(12)
                .fontColor('#4ADE80')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })
          } else {
            Row() {
              Text('未启用任何 Prompt，AGENTS.md 为空')
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(12)
                .fontColor('#FF9800')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })
          }

          Scroll() {
            if (this.promptsViewModel.state.liveContent.length > 0) {
              Text(this.promptsViewModel.state.liveContent)
                .copyOption(CopyOptions.LocalDevice)
                .fontFamily('monospace')
                .fontSize(12)
                .fontColor('#334155')
                .lineHeight(20)
                .padding(12)
            } else {
              Column() {
                Text('暂无内容')
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(24)
                  .fontColor('#ddd')
                Text('启用一个 Prompt 后，其内容将显示在此处')
                  .copyOption(CopyOptions.LocalDevice)
                  .fontSize(12)
                  .fontColor('#aaa')
                  .margin({ top: 8 })
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
            }
          }
          .layoutWeight(1)
        }
        .layoutWeight(1)
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
    .width('100%')
    .height('100%')

    // Delete confirmation dialog
    if (this.showDeleteConfirm && this.deleteTarget !== null) {
      Column() {
        Column() {
          Text('确认删除')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#0F172A')
          Text('确定要删除 Prompt "' + (this.deleteTarget?.name ?? '') + '" 吗？')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(14)
            .fontColor('#334155')
            .margin({ top: 12 })
          Row() {
            Button('取消')
              .fontSize(13)
              .height(34)
              .backgroundColor('#FFFFFF')
              .fontColor('#334155')
              .borderRadius(14)
              .border({ width: 1, color: '#CBD5E1' })
              .onClick(() => {
                this.showDeleteConfirm = false;
                this.deleteTarget = null;
              })
            Button('删除')
              .fontSize(13)
              .height(34)
              .backgroundColor('#DC2626')
              .fontColor('#FFFFFF')
              .borderRadius(14)
              .margin({ left: 12 })
              .onClick(() => {
                if (this.deleteTarget !== null) {
                  this.promptsViewModel.deletePrompt(this.deleteTarget.id);
                }
                this.showDeleteConfirm = false;
                this.deleteTarget = null;
              })
          }
          .margin({ top: 20 })
          .width('100%')
          .justifyContent(FlexAlign.End)
        }
        .width(320)
        .padding(24)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
        .shadow({ radius: 20, color: '#1A000000', offsetX: 0, offsetY: 4 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#4D000000')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showDeleteConfirm = false;
        this.deleteTarget = null;
      })
    }
  }
}
