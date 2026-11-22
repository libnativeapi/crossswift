import { LengthMetrics, PathShape } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import nativeApp from 'lib{{NATIVE_LIB_NAME}}.so';

interface AlertActionNode {
  title: string;
  role: string;
  enabled: boolean;
}

interface GalleryNode {
  id: number;
  kind: string;
  x: number;
  y: number;
  width: number;
  height: number;
  text: string;
  label: string;
  placeholder: string;
  secure?: boolean;
  multiline?: boolean;
  image: string;
  fontSize: number;
  fontWeight: number;
  fontFamily: string;
  textAlignment: string;
  lineSpacing: number;
  tracking: number;
  underline: boolean;
  lineLimit: number;
  path: string;
  clipPath?: string;
  rotation: number;
  scaleX: number;
  scaleY: number;
  dash: number[];
  foreground?: number;
  background?: number;
  border?: number;
  borderWidth: number;
  radius: number;
  opacity: number;
  blurRadius?: number;
  clip: boolean;
  scrollIndicators: boolean;
  scrollDirection: string;
  selected: boolean;
  enabled: boolean;
  hitTesting: boolean;
  gradientKind?: string;
  gradientColors?: number[];
  boolValue?: boolean;
  doubleValue?: number;
  minValue?: number;
  maxValue?: number;
  stepValue?: number;
  intValue?: number;
  items?: string[];
  title?: string;
  subtitle?: string;
  styleName?: string;
  canGoBack?: boolean;
  tint?: number;
  alertActions?: AlertActionNode[];
  children: GalleryNode[];
}

@Observed
class GalleryModel {
  snapshot: GalleryNode;
  children: GalleryModel[];

  constructor(snapshot: GalleryNode) {
    this.snapshot = snapshot;
    this.children = snapshot.children.map((child: GalleryNode) => new GalleryModel(child));
  }

  update(snapshot: GalleryNode): void {
    const previous = new Map<number, GalleryModel>();
    this.children.forEach((child: GalleryModel) => previous.set(child.snapshot.id, child));
    this.snapshot = snapshot;
    const next = snapshot.children.map((child: GalleryNode) => {
      const retained = previous.get(child.id);
      if (!retained) return new GalleryModel(child);
      retained.update(child);
      return retained;
    });
    if (next.length !== this.children.length ||
      next.some((child: GalleryModel, index: number) => child !== this.children[index])) {
      this.children = next;
    }
  }
}

@Component
struct GalleryElement {
  @ObjectLink model: GalleryModel;
  @Prop parentX: number = 0;
  @Prop parentY: number = 0;
  @Prop parentOpacity: number = 1;
  @Consume('uiStyle') uiStyle: string;

  private scroller: Scroller = new Scroller();

  private isIOS(): boolean {
    return this.uiStyle === 'ios';
  }

  private color(value: number | undefined, fallback: string): string {
    return value === undefined ? fallback : '#' + value.toString(16).padStart(8, '0');
  }

  private action(event: number): void {
    if (this.model.snapshot.enabled && this.model.snapshot.hitTesting) {
      nativeApp.appEvent(this.model.snapshot.id, event, '');
    }
  }

  private makeClipShape(path: string | undefined): PathShape | undefined {
    return path ? new PathShape({ commands: path }) : undefined;
  }

  private resolvedBackground(): string {
    const snap = this.model.snapshot;
    if (snap.kind === 'path' || snap.kind === 'navBar' || snap.kind === 'tabBar' || snap.kind === 'alert') {
      return '#00000000';
    }
    return this.color(snap.background, '#00000000');
  }

  private resolvedRadius(): number {
    const snap = this.model.snapshot;
    if (!this.isIOS() && snap.background === 0xffffffff && snap.radius >= 22) {
      return 16;
    }
    return snap.radius;
  }

  @Builder
  private children() {
    ForEach(this.model.children, (child: GalleryModel) => {
      GalleryElement({
        model: child,
        parentX: this.model.snapshot.x, parentY: this.model.snapshot.y, parentOpacity: this.model.snapshot.opacity
      })
    }, (child: GalleryModel) => String(child.snapshot.id))
  }

  @Builder
  private renderNavBar() {
    if (this.isIOS()) {
      // iOS 27 Liquid Glass navigation bar: floating circular < back button + centered title + style pill
      Stack() {
        if (this.model.snapshot.canGoBack) {
          Row() {
            Button({ type: ButtonType.Circle }) {
              Text('‹')
                .fontSize(24)
                .fontWeight(FontWeight.Medium)
                .fontColor('#ff000000')
                .offset({ y: -1 })
            }
            .width(40)
            .height(40)
            .backgroundColor('#e8ffffff')
            .border({ width: 0.8, color: '#ccffffff' })
            .shadow({ radius: 10, color: '#22000000', offsetY: 3 })
            .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 14, ''))
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
          .padding({ left: 16 })
        }

        Text(this.model.snapshot.title ?? '')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ff000000')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 68, right: 86 })
          .hitTestBehavior(HitTestMode.None)

        Row() {
          Button('iOS 27', { type: ButtonType.Capsule })
            .height(32)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#ff007aff')
            .backgroundColor('#e8ffffff')
            .border({ width: 0.8, color: '#ccffffff' })
            .shadow({ radius: 8, color: '#20000000', offsetY: 2 })
            .onClick(() => {
              this.uiStyle = 'harmony';
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ right: 16 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height('100%')
    } else {
      // HarmonyOS Native navigation header
      Row({ space: 10 }) {
        if (this.model.snapshot.canGoBack) {
          Button({ type: ButtonType.Circle }) {
            Text('←')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#ff182431')
          }
          .width(38)
          .height(38)
          .backgroundColor('#0d000000')
          .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 14, ''))
        }
        Text(this.model.snapshot.title ?? '')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ff182431')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Button('HarmonyOS', { type: ButtonType.Capsule })
          .height(32)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#ff0a59f7')
          .backgroundColor('#180a59f7')
          .onClick(() => {
            this.uiStyle = 'ios';
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor('#fff1f3f5')
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private renderSwitch() {
    if (this.isIOS()) {
      // iOS 27 elongated capsule switch (62x28 track, 36x24 pill thumb)
      Row() {
        Stack({ alignContent: (this.model.snapshot.boolValue ?? false) ? Alignment.End : Alignment.Start }) {
          Row()
            .width(36)
            .height(24)
            .borderRadius(12)
            .backgroundColor('#ffffffff')
            .shadow({ radius: 4, color: '#2e000000', offsetY: 1 })
        }
        .width(62)
        .height(28)
        .padding(2)
        .borderRadius(14)
        .backgroundColor((this.model.snapshot.boolValue ?? false)
          ? this.color(this.model.snapshot.tint, '#ff34c759')
          : '#33787880')
        .opacity(this.model.snapshot.enabled ? 1 : 0.45)
        .onClick(() => {
          if (this.model.snapshot.enabled) {
            const next = !(this.model.snapshot.boolValue ?? false);
            nativeApp.appEvent(this.model.snapshot.id, 10, next ? '1' : '0');
          }
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    } else {
      // HarmonyOS Native ArkUI Switch
      Row() {
        Toggle({ type: ToggleType.Switch, isOn: this.model.snapshot.boolValue ?? false })
          .selectedColor(this.color(this.model.snapshot.tint, '#ff007dff'))
          .enabled(this.model.snapshot.enabled)
          .onChange((isOn: boolean) => {
            if (isOn !== (this.model.snapshot.boolValue ?? false)) {
              nativeApp.appEvent(this.model.snapshot.id, 10, isOn ? '1' : '0');
            }
          })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private renderSlider() {
    if (this.isIOS()) {
      // iOS 27 6vp capsule track + elongated 36x22 white pill thumb
      Stack({ alignContent: Alignment.Start }) {
        Row()
          .width('100%')
          .height(6)
          .borderRadius(3)
          .backgroundColor('#22787880')
        Row()
          .width(`${Math.max(0, Math.min(100, (((this.model.snapshot.doubleValue ?? 0) - (this.model.snapshot.minValue ?? 0)) / Math.max(0.0001, (this.model.snapshot.maxValue ?? 1) - (this.model.snapshot.minValue ?? 0))) * 100))}%`)
          .height(6)
          .borderRadius(3)
          .backgroundColor(this.model.snapshot.enabled ? this.color(this.model.snapshot.tint, '#ff007aff') : '#738e8e93')
        Row()
          .width(36)
          .height(22)
          .borderRadius(11)
          .backgroundColor('#ffffffff')
          .border({ width: 0.6, color: '#14000000' })
          .shadow({ radius: 6, color: '#2b000000', offsetY: 2 })
          .position({
            x: Math.max(0, Math.min(
              Math.max(0, this.model.snapshot.width - 36),
              (((this.model.snapshot.doubleValue ?? 0) - (this.model.snapshot.minValue ?? 0)) / Math.max(0.0001, (this.model.snapshot.maxValue ?? 1) - (this.model.snapshot.minValue ?? 0))) * Math.max(0, this.model.snapshot.width - 36)
            )),
            y: Math.max(0, (this.model.snapshot.height - 22) / 2)
          })
      }
      .width('100%')
      .height('100%')
      .onTouch((event: TouchEvent) => {
        if (!this.model.snapshot.enabled || event.touches.length === 0) return;
        if (event.type === TouchType.Down || event.type === TouchType.Move || event.type === TouchType.Up) {
          const w = Math.max(1, this.model.snapshot.width);
          const frac = Math.max(0, Math.min(1, event.touches[0].x / w));
          const minV = this.model.snapshot.minValue ?? 0;
          const maxV = this.model.snapshot.maxValue ?? 1;
          const val = minV + frac * (maxV - minV);
          nativeApp.appEvent(this.model.snapshot.id, 11, String(val));
        }
      })
    } else {
      // HarmonyOS Native ArkUI Slider
      Slider({
        value: this.model.snapshot.doubleValue ?? 0,
        min: this.model.snapshot.minValue ?? 0,
        max: this.model.snapshot.maxValue ?? 1,
        step: (this.model.snapshot.stepValue ?? 0) > 0 ? this.model.snapshot.stepValue : 0.01
      })
        .selectedColor(this.color(this.model.snapshot.tint, '#ff007dff'))
        .enabled(this.model.snapshot.enabled)
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Moving || mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            nativeApp.appEvent(this.model.snapshot.id, 11, String(value));
          }
        })
    }
  }

  @Builder
  private renderSegmented() {
    Row() {
      ForEach(this.model.snapshot.items ?? [], (item: string, idx: number) => {
        Text(item)
          .fontSize(13)
          .fontWeight(idx === (this.model.snapshot.intValue ?? 0) ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(idx === (this.model.snapshot.intValue ?? 0)
            ? (this.isIOS() ? '#ff000000' : '#ff0a59f7')
            : '#ff3c3c43')
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .layoutWeight(1)
          .height('100%')
          .borderRadius(999)
          .backgroundColor(idx === (this.model.snapshot.intValue ?? 0)
            ? (this.isIOS() ? '#ffffffff' : '#ffffffff')
            : '#00000000')
          .shadow(idx === (this.model.snapshot.intValue ?? 0) ? { radius: 4, color: '#1c000000', offsetY: 1 } : undefined)
          .onClick(() => {
            if (this.model.snapshot.enabled) {
              nativeApp.appEvent(this.model.snapshot.id, 12, String(idx));
            }
          })
      }, (item: string, idx: number) => `${idx}_${item}`)
    }
    .width('100%')
    .height('100%')
    .padding(3)
    .borderRadius(999)
    .backgroundColor(this.isIOS() ? '#1f767680' : '#14000000')
  }

  @Builder
  private renderStepper() {
    if (this.isIOS()) {
      Row() {
        Row() {
          Text('−')
            .fontSize(20)
            .fontColor('#ff000000')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              if (this.model.snapshot.enabled) nativeApp.appEvent(this.model.snapshot.id, 13, '-1');
            })
          Divider().vertical(true).height(18).color('#24000000')
          Text('+')
            .fontSize(20)
            .fontColor('#ff000000')
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              if (this.model.snapshot.enabled) nativeApp.appEvent(this.model.snapshot.id, 13, '1');
            })
        }
        .width(96)
        .height(34)
        .borderRadius(17)
        .backgroundColor('#1f767680')
        .opacity(this.model.snapshot.enabled ? 1 : 0.4)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    } else {
      Row({ space: 6 }) {
        Button('−', { type: ButtonType.Capsule })
          .width(42)
          .height(32)
          .fontSize(16)
          .fontColor('#ff0a59f7')
          .backgroundColor('#180a59f7')
          .enabled(this.model.snapshot.enabled)
          .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 13, '-1'))
        Button('+', { type: ButtonType.Capsule })
          .width(42)
          .height(32)
          .fontSize(16)
          .fontColor('#ff0a59f7')
          .backgroundColor('#180a59f7')
          .enabled(this.model.snapshot.enabled)
          .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 13, '1'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private renderSemanticButton() {
    Button(this.model.snapshot.title ?? this.model.snapshot.text, { type: ButtonType.Capsule })
      .width('100%')
      .height('100%')
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.resolveButtonFg())
      .backgroundColor(this.resolveButtonBg())
      .enabled(this.model.snapshot.enabled)
      .opacity(this.model.snapshot.enabled ? 1 : 0.45)
      .onClick(() => this.action(1))
  }

  private resolveButtonBg(): string {
    const snap = this.model.snapshot;
    const isDestructive = snap.subtitle === 'destructive';
    const style = snap.styleName ?? 'bordered';
    const accent = isDestructive
      ? (this.isIOS() ? '#ffff3b30' : '#ffe84026')
      : this.color(snap.tint, this.isIOS() ? '#ff007aff' : '#ff0a59f7');
    if (style === 'borderedProminent' || style === 'filled') return accent;
    if (style === 'borderless' || style === 'link' || style === 'plain') return '#00000000';
    if (snap.tint !== undefined && !isDestructive) {
      return '#' + ((snap.tint & 0x00ffffff) | 0x26000000).toString(16).padStart(8, '0');
    }
    return this.isIOS() ? '#1f767680' : '#0f000000';
  }

  private resolveButtonFg(): string {
    const snap = this.model.snapshot;
    const isDestructive = snap.subtitle === 'destructive';
    const style = snap.styleName ?? 'bordered';
    if (style === 'borderedProminent' || style === 'filled') return '#ffffffff';
    if (isDestructive) return this.isIOS() ? '#ffff3b30' : '#ffe84026';
    return this.color(snap.tint, this.isIOS() ? '#ff007aff' : '#ff0a59f7');
  }

  @Builder
  private renderTabBar() {
    Row() {
      Row() {
        ForEach(this.model.snapshot.items ?? [], (label: string, idx: number) => {
          Column({ space: 2 }) {
            Text(label)
              .fontSize(13)
              .fontWeight(idx === (this.model.snapshot.intValue ?? 0) ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(idx === (this.model.snapshot.intValue ?? 0)
                ? (this.isIOS() ? '#ff007aff' : '#ff0a59f7')
                : '#ff6e6e73')
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .borderRadius(999)
          .backgroundColor(idx === (this.model.snapshot.intValue ?? 0) && this.isIOS() ? '#18007aff' : '#00000000')
          .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 12, String(idx)))
        }, (label: string, idx: number) => `${idx}_${label}`)
      }
      .width('100%')
      .height(this.isIOS() ? 56 : '100%')
      .padding(this.isIOS() ? 4 : 0)
      .borderRadius(this.isIOS() ? 28 : 0)
      .backgroundColor(this.isIOS() ? '#ecffffff' : '#fff7f8fa')
      .border(this.isIOS() ? { width: 0.8, color: '#ccffffff' } : { width: { top: 0.5 }, color: '#1a000000' })
      .shadow(this.isIOS() ? { radius: 14, color: '#26000000', offsetY: 4 } : undefined)
    }
    .width('100%')
    .height('100%')
    .padding(this.isIOS() ? { left: 16, right: 16, top: 6, bottom: 6 } : 0)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private renderAlert() {
    Column({ space: 12 }) {
      if ((this.model.snapshot.title ?? '').length > 0) {
        Text(this.model.snapshot.title ?? '')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ff000000')
          .width('100%')
      }
      if ((this.model.snapshot.subtitle ?? '').length > 0) {
        Text(this.model.snapshot.subtitle ?? '')
          .fontSize(14)
          .fontColor('#b83c3c43')
          .width('100%')
      }
      Row({ space: 10 }) {
        ForEach(this.model.snapshot.alertActions ?? [], (act: AlertActionNode, idx: number) => {
          Button(act.title, { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(42)
            .fontSize(15)
            .fontWeight(act.role === 'cancel' ? FontWeight.Medium : FontWeight.Bold)
            .fontColor(act.role === 'destructive'
              ? (this.isIOS() ? '#ffff3b30' : '#ffe84026')
              : (this.isIOS() ? '#ff000000' : '#ff0a59f7'))
            .backgroundColor(this.isIOS() ? '#14000000' : '#120a59f7')
            .enabled(act.enabled)
            .onClick(() => nativeApp.appEvent(this.model.snapshot.id, 12, String(idx)))
        }, (act: AlertActionNode, idx: number) => `${idx}_${act.title}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .borderRadius(this.isIOS() ? 28 : 24)
    .backgroundColor(this.isIOS() ? '#f5f7f7fa' : '#ffffffff')
    .border({ width: 0.8, color: '#ccffffff' })
    .shadow({ radius: 28, color: '#38000000', offsetY: 10 })
  }

  @Builder
  private content() {
    if (this.model.snapshot.kind === 'navStack') {
      NavStackHost({ model: this.model })
    } else if (this.model.snapshot.kind === 'navBar') {
      this.renderNavBar()
    } else if (this.model.snapshot.kind === 'tabBar') {
      this.renderTabBar()
    } else if (this.model.snapshot.kind === 'alert') {
      this.renderAlert()
    } else if (this.model.snapshot.kind === 'switch') {
      this.renderSwitch()
    } else if (this.model.snapshot.kind === 'slider') {
      this.renderSlider()
    } else if (this.model.snapshot.kind === 'segmented') {
      this.renderSegmented()
    } else if (this.model.snapshot.kind === 'stepper') {
      this.renderStepper()
    } else if (this.model.snapshot.kind === 'semanticButton') {
      this.renderSemanticButton()
    } else if (this.model.snapshot.kind === 'divider') {
      Divider().color(this.isIOS() ? '#1e3c3c43' : '#14000000').strokeWidth(0.5)
    } else if (this.model.snapshot.kind === 'checkbox') {
      Toggle({ type: ToggleType.Checkbox, isOn: this.model.snapshot.boolValue ?? false })
        .selectedColor(this.color(this.model.snapshot.tint, this.isIOS() ? '#ff007aff' : '#ff007dff'))
        .enabled(this.model.snapshot.enabled)
        .onChange((isOn: boolean) => {
          if (isOn !== (this.model.snapshot.boolValue ?? false)) {
            nativeApp.appEvent(this.model.snapshot.id, 10, isOn ? '1' : '0');
          }
        })
    } else if (this.model.snapshot.kind === 'menu') {
      Button((this.model.snapshot.title ?? '') + ' ⌄', { type: ButtonType.Capsule })
        .width('100%')
        .height('100%')
        .fontSize(14)
        .fontColor(this.isIOS() ? '#ff007aff' : '#ff0a59f7')
        .backgroundColor(this.isIOS() ? '#1f767680' : '#120a59f7')
        .bindMenu((this.model.snapshot.items ?? []).map((label: string, idx: number): MenuElement => ({
          value: idx === (this.model.snapshot.intValue ?? 0) ? '✓ ' + label : label,
          action: () => nativeApp.appEvent(this.model.snapshot.id, 12, String(idx))
        })))
    } else if (this.model.snapshot.kind === 'progressLinear') {
      Progress({ value: (this.model.snapshot.doubleValue ?? 0) * 100, total: 100, type: ProgressType.Linear })
        .color(this.color(this.model.snapshot.tint, this.isIOS() ? '#ff007aff' : '#ff007dff'))
        .width('100%')
    } else if (this.model.snapshot.kind === 'progressCircular') {
      LoadingProgress()
        .color(this.color(this.model.snapshot.tint, this.isIOS() ? '#ff3c3c43' : '#ff007dff'))
        .width('100%')
        .height('100%')
    } else if (this.model.snapshot.kind === 'gradient' && this.model.snapshot.gradientColors && this.model.snapshot.gradientColors.length >= 2) {
      if (this.model.snapshot.gradientKind === 'radial') {
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(this.model.snapshot.radius)
          .radialGradient({
            center: ['50%', '50%'],
            radius: Math.max(this.model.snapshot.width, this.model.snapshot.height) * 0.5,
            colors: this.model.snapshot.gradientColors.map((c: number, i: number): [ResourceColor, number] => [
              this.color(c, '#ff007aff'),
              i / Math.max(1, (this.model.snapshot.gradientColors?.length ?? 2) - 1)
            ])
          })
          .hitTestBehavior(HitTestMode.None)
      } else if (this.model.snapshot.gradientKind === 'angular') {
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(this.model.snapshot.radius)
          .sweepGradient({
            center: ['50%', '50%'],
            start: 0,
            end: 360,
            colors: this.model.snapshot.gradientColors.map((c: number, i: number): [ResourceColor, number] => [
              this.color(c, '#ff007aff'),
              i / Math.max(1, (this.model.snapshot.gradientColors?.length ?? 2) - 1)
            ])
          })
          .hitTestBehavior(HitTestMode.None)
      } else {
        Row()
          .width('100%')
          .height('100%')
          .borderRadius(this.model.snapshot.radius)
          .linearGradient({
            angle: 135,
            colors: this.model.snapshot.gradientColors.map((c: number, i: number): [ResourceColor, number] => [
              this.color(c, '#ff007aff'),
              i / Math.max(1, (this.model.snapshot.gradientColors?.length ?? 2) - 1)
            ])
          })
          .hitTestBehavior(HitTestMode.None)
      }
    } else if (this.model.snapshot.kind === 'text') {
      Text(this.model.snapshot.text)
        .fontSize(this.model.snapshot.fontSize + 'vp')
        .fontWeight(this.model.snapshot.fontWeight)
        .fontFamily(this.model.snapshot.fontFamily)
        .fontColor(this.color(this.model.snapshot.foreground, '#ff000000'))
        .textAlign(this.model.snapshot.textAlignment === 'center' ? TextAlign.Center :
          this.model.snapshot.textAlignment === 'end' ? TextAlign.End : TextAlign.Start)
        .lineSpacing(LengthMetrics.vp(this.model.snapshot.lineSpacing))
        .letterSpacing(this.model.snapshot.tracking + 'vp')
        .decoration({ type: this.model.snapshot.underline ? TextDecorationType.Underline : TextDecorationType.None })
        .maxLines(this.model.snapshot.lineLimit > 0 ? this.model.snapshot.lineLimit : 1000)
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .hitTestBehavior(HitTestMode.None)
    } else if (this.model.snapshot.kind === 'image' && this.model.snapshot.image.length > 0) {
      Image('resource://RAWFILE/' + this.model.snapshot.image)
        .objectFit(ImageFit.Contain)
        .fillColor(this.color(this.model.snapshot.foreground, '#ff000000'))
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
    } else if (this.model.snapshot.kind === 'path') {
      Path().commands(this.model.snapshot.path)
        .width('100%')
        .height('100%')
        .fill(this.color(this.model.snapshot.background, '#00000000'))
        .stroke(this.color(this.model.snapshot.border, '#00000000'))
        .strokeWidth(this.model.snapshot.borderWidth)
        .strokeDashArray(this.model.snapshot.dash)
        .hitTestBehavior(HitTestMode.None)
    } else if (this.model.snapshot.kind === 'editor') {
      if (this.model.snapshot.multiline) {
        TextArea({ text: this.model.snapshot.text, placeholder: this.model.snapshot.placeholder })
          .backgroundColor(this.isIOS() ? '#14767680' : '#0d000000')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(this.isIOS() ? 14 : 12)
          .fontSize(this.model.snapshot.fontSize)
          .fontColor(this.color(this.model.snapshot.foreground, '#ff000000'))
          .width('100%')
          .height('100%')
          .onFocus(() => this.action(8))
          .onBlur(() => this.action(9))
          .onChange((value: string) => {
            if (value !== this.model.snapshot.text) nativeApp.appEvent(this.model.snapshot.id, 7, value);
          })
      } else {
        TextInput({ text: this.model.snapshot.text, placeholder: this.model.snapshot.placeholder })
          .type(this.model.snapshot.secure ? InputType.Password : InputType.Normal)
          .backgroundColor(this.isIOS() ? '#14767680' : '#0d000000')
          .padding({ left: 12, right: 12 })
          .borderRadius(this.isIOS() ? 14 : 12)
          .fontSize(this.model.snapshot.fontSize)
          .fontColor(this.color(this.model.snapshot.foreground, '#ff000000'))
          .width('100%')
          .height('100%')
          .onSubmit(() => nativeApp.appEvent(this.model.snapshot.id, 16, ''))
          .onFocus(() => this.action(8))
          .onBlur(() => this.action(9))
          .onChange((value: string) => {
            if (value !== this.model.snapshot.text) nativeApp.appEvent(this.model.snapshot.id, 7, value);
          })
      }
    } else if (this.model.snapshot.kind === 'scroll') {
      Scroll(this.scroller) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.children()
        }
        .width(this.model.snapshot.children[0]?.width ?? this.model.snapshot.width)
        .height(this.model.snapshot.children[0]?.height ?? this.model.snapshot.height)
      }
      .width('100%')
      .height('100%')
      .scrollable(this.model.snapshot.scrollDirection === 'both' ? ScrollDirection.FREE :
        this.model.snapshot.scrollDirection === 'horizontal' ? ScrollDirection.Horizontal : ScrollDirection.Vertical)
      .scrollBar(this.model.snapshot.scrollIndicators ? BarState.Auto : BarState.Off)
    } else if (this.model.snapshot.kind === 'button' && this.model.snapshot.children.length === 0) {
      Text(this.model.snapshot.text)
        .fontSize(this.model.snapshot.fontSize + 'vp')
        .fontWeight(this.model.snapshot.fontWeight)
        .fontFamily(this.model.snapshot.fontFamily)
        .fontColor(this.color(this.model.snapshot.foreground, '#ff000000'))
        .width('100%')
        .height('100%')
        .align(Alignment.Center)
        .hitTestBehavior(HitTestMode.None)
    } else {
      this.children()
    }
  }

  @Builder
  private visual() {
    if (this.model.snapshot.kind === 'button' && this.model.snapshot.hitTesting) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.content()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .padding(0)
      .borderRadius(0)
      .backgroundColor(Color.Transparent)
      .hoverEffect(HoverEffect.None)
      .accessibilityText(this.model.snapshot.label)
      .accessibilitySelected(this.model.snapshot.selected)
      .id(this.model.snapshot.label.length > 0 ? 'swift-action-' + this.model.snapshot.label : 'swift-node-' + String(this.model.snapshot.id))
      .onClick((event: ClickEvent) => {
        nativeApp.appEvent(this.model.snapshot.id, 11,
          JSON.stringify([this.model.snapshot.x + event.x, this.model.snapshot.y + event.y]));
      })
      .parallelGesture(TapGesture({ count: 2 }).onAction((event: GestureEvent) => {
        const finger = event.fingerList[0];
        if (finger) nativeApp.appEvent(this.model.snapshot.id, 12,
          JSON.stringify([this.model.snapshot.x + finger.localX, this.model.snapshot.y + finger.localY]));
      }))
      .onHover((hovered: boolean) => this.action(hovered ? 2 : 3))
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) this.action(4);
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.action(5);
      })
      .onFocus(() => this.action(8))
      .onBlur(() => this.action(9))
    } else {
      this.content()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.visual()
    }
    .width(this.model.snapshot.width)
    .height(this.model.snapshot.height)
    .position({ x: this.model.snapshot.x - this.parentX, y: this.model.snapshot.y - this.parentY })
    .backgroundColor(this.resolvedBackground())
    .border({
      width: this.model.snapshot.kind === 'path' ? 0 : this.model.snapshot.borderWidth,
      radius: this.resolvedRadius(),
      color: this.color(this.model.snapshot.border, '#00000000')
    })
    .clip(this.model.snapshot.clip && !this.model.snapshot.clipPath)
    .clipShape(this.makeClipShape(this.model.snapshot.clipPath))
    .rotate({ angle: this.model.snapshot.rotation })
    .scale({ x: this.model.snapshot.scaleX, y: this.model.snapshot.scaleY })
    .opacity(this.parentOpacity > 0 ? Math.min(1, this.model.snapshot.opacity / this.parentOpacity) : 0)
    .blur(this.model.snapshot.blurRadius ?? 0)
    .enabled(this.model.snapshot.enabled)
    .hitTestBehavior(this.model.snapshot.hitTesting ? HitTestMode.Transparent : HitTestMode.None)
  }
}

@Component
struct NavStackHost {
  @ObjectLink @Watch('syncNavStack') model: GalleryModel;
  @Consume('uiStyle') uiStyle: string;
  @State private rootModel: GalleryModel | undefined = undefined;
  private pageInfos: NavPathStack = new NavPathStack();
  private pageCache: Map<string, GalleryModel> = new Map<string, GalleryModel>();

  aboutToAppear(): void {
    this.syncNavStack();
  }

  private syncNavStack(): void {
    const snap = this.model.snapshot;
    const pageKey = snap.subtitle ?? '0';
    const depth = snap.intValue ?? 0;
    const pageNode = snap.children.length > 0 ? snap.children[0] : undefined;
    if (!pageNode) return;

    const existing = this.pageCache.get(pageKey);
    if (existing) {
      existing.update(pageNode);
    } else {
      this.pageCache.set(pageKey, new GalleryModel(pageNode));
    }

    if (depth === 0 || pageKey === '0') {
      this.rootModel = this.pageCache.get('0') ?? this.pageCache.get(pageKey);
      const count = this.pageInfos.size();
      if (count === 1) {
        this.pageInfos.pop(true);
      } else if (count > 1) {
        this.pageInfos.clear(true);
      }
      return;
    }

    if (!this.rootModel) {
      this.rootModel = this.pageCache.get('0') ?? this.pageCache.get(pageKey);
    }

    const names = this.pageInfos.getAllPathName();
    const topName = names.length > 0 ? names[names.length - 1] : '';
    if (topName === pageKey && names.length === depth) {
      return;
    }
    if (depth > names.length) {
      this.pageInfos.pushPath({ name: pageKey }, true);
    } else if (depth < names.length) {
      while (this.pageInfos.size() > depth) {
        this.pageInfos.pop(true);
      }
    } else if (topName !== pageKey) {
      this.pageInfos.replacePath({ name: pageKey }, true);
    }
  }

  @Builder
  private buildDestination(name: string) {
    NavDestination() {
      if (this.pageCache.has(name)) {
        Stack({ alignContent: Alignment.TopStart }) {
          GalleryElement({
            model: this.pageCache.get(name) as GalleryModel,
            parentX: this.model.snapshot.x,
            parentY: this.model.snapshot.y,
            parentOpacity: this.model.snapshot.opacity
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .hideTitleBar(true)
    .backgroundColor(this.uiStyle === 'ios' ? '#fff2f2f7' : '#fff1f3f5')
    .onBackPressed(() => {
      if ((this.model.snapshot.intValue ?? 0) > 0) {
        nativeApp.appEvent(this.model.snapshot.id, 14, '');
      }
      return false;
    })
  }

  build() {
    Navigation(this.pageInfos) {
      if (this.rootModel) {
        Stack({ alignContent: Alignment.TopStart }) {
          GalleryElement({
            model: this.rootModel,
            parentX: this.model.snapshot.x,
            parentY: this.model.snapshot.y,
            parentOpacity: this.model.snapshot.opacity
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideToolBar(true)
    .navDestination(this.buildDestination)
    .width('100%')
    .height('100%')
  }
}

@Entry
@Component
struct Index {
  @State private tree: GalleryModel | undefined = undefined;
  @Provide('uiStyle') uiStyle: string = '{{INITIAL_UI_STYLE}}';
  @StorageProp('crossSwiftIsDark') @Watch('onColorModeChange') isDark: boolean = false;
  private mounted: boolean = false;

  onColorModeChange(): void {
    if (this.mounted) {
      nativeApp.setColorScheme(this.isDark);
    }
  }

  aboutToDisappear(): void {
    if (this.mounted) nativeApp.unmountApp();
    this.mounted = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.tree) {
        GalleryElement({ model: this.tree })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDark ? '#ff000000' : (this.uiStyle === 'ios' ? '#fff2f2f7' : '#fff1f3f5'))
    .onAreaChange((_old: Area, area: Area) => {
      const width = Number(area.width);
      const height = Number(area.height);
      if (width <= 0 || height <= 0) return;
      if (this.mounted) {
        nativeApp.resizeApp(width, height);
      } else {
        this.mounted = true;
        nativeApp.mountApp((json: string) => {
          const snapshot = JSON.parse(json) as GalleryNode;
          if (this.tree && this.tree.snapshot.id === snapshot.id) {
            this.tree.update(snapshot);
          } else {
            this.tree = new GalleryModel(snapshot);
            hilog.info(0x0000, 'CrossSwiftUI', 'CROSSSWIFT_HARMONY mounted');
          }
        }, width, height, this.getUIContext().vp2px(1));
        nativeApp.setColorScheme(this.isDark);
      }
    })
  }
}
