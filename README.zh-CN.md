<p align="center">
  <img src="assets/meld-lockup.svg" alt="Meld" width="280">
</p>

<p align="center"><strong>让形状过渡拥有自己的观点。</strong><br>确定性的几何规划、弹簧物理和原生 Flutter 绘制，组合成一个小而完整的 API。</p>

<p align="center">
  <a href="https://github.com/fluttercandies/meld">代码仓库</a> ·
  <a href="https://fluttercandies.github.io/meld/">在线 Showcase</a> ·
  <a href="examples/showcase">Showcase 源码</a> ·
  <a href="README.md">English</a>
</p>

Meld 让一个矢量形状自然地变成另一个形状，避免普通逐点插值常见的“橡皮泥”观感。它会一次性规划子路径配对、旋转、缩放、拓扑和弹簧状态，之后每一帧都保持轻量且可观测。

## 3 分钟上手

```yaml
dependencies:
meld: ^1.0.0
```

```dart
import 'package:flutter/material.dart';
import 'package:meld/meld.dart';

class MenuButton extends StatelessWidget {
  const MenuButton({super.key});

  static const menu = PathDataSource('M3 6H21M3 12H21M3 18H21');
  static const close = PathDataSource('M5 5L19 19M19 5L5 19');

  @override
  Widget build(BuildContext context) {
    return const MeldIcon(
      from: menu,
      to: close,
      progress: 0.5,
      size: 32,
      label: '菜单',
    );
  }
}
```

同一个 `MeldIcon` 既支持 `icon` 端点的声明式更新，也支持 `controller` 命令式控制。`progress` 是完全受控且确定性的，适合手势拖拽、进度条和时间轴编辑器。

## 三种控制方式

```dart
final controller = MeldIconController(initialSource: MenuButton.menu);

// 命令式模式：把 controller 交给 MeldIcon 后等待过渡完成。
await controller.morphTo(MenuButton.close, preset: SpringPreset.snappy);

// 拖动模式：没有 ticker，也没有隐藏状态。
controller.seek(MenuButton.close, 0.72);

// 运行中/暂停态原地反向；已完成端点会成为新的起点并正向播放。
await controller.reverse(preset: SpringPreset.snappy);

// 序列模式：多个过渡可以组合。
await controller.playSequence([MenuButton.menu, MenuButton.close]);
```

使用 `MeldIconTheme` 统一视觉语言。`MeldPaintStyle.outline` 始终绘制几何轮廓，`original` 保留输入源声明或解析出的真实绘制意图，`both` 会先填充闭合轮廓再描边。几何源可以显式声明 `MeldSourcePaintStyle.fill`、`.outline` 或 `.both`；未显式覆盖时，SVG markup 会从内联 `fill`/`stroke` 属性推导原始样式。

## 输入格式

- `PathDataSource`：支持相对命令、简写曲线、弧线、科学计数法和隐式重复的 SVG path。
- `SvgMarkupSource`：支持 `path`、`line`、`circle`、`ellipse`、`rect`、`polyline`、`polygon` 以及 `viewBox`。
- `GeometrySource`：适合生成式图标和 fixture 的结构化、可序列化几何。
- `CubicSource`：适合预计算资源和适配器的标准 cubic 路径。
- `meld_font`：可选的静态 TTF/OTF 轮廓适配器。传入应用已经持有的字体字节，Meld 不会下载或捆绑字体。

字体轮廓是填充 glyph 几何，不是 stroke。适配器支持 Unicode cmap、简单和复合 TrueType glyph，以及 quadratic 到 cubic 的转换。CFF、彩色和可变字体轮廓会明确返回诊断异常，避免视觉 fallback 静默进入生产环境。

```dart
final data = await rootBundle.load('assets/YourLicensedFont.ttf');
final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
final home = Meld.sourceFromIconData(Icons.home_rounded, fontBytes: bytes);
final homeIcon = MeldIcon(
  icon: home,
  paintStyle: MeldPaintStyle.original,
  label: '主页',
);
```

字体资源及其许可证由应用负责；进入 plan 的只有轮廓几何。

## 为什么更自然

普通插值假设两个图标中编号相同的点彼此对应。Meld 会先匹配子路径，搜索闭合路径的最佳切点和方向，再求相似变换。Polar 插值让形状作为一个整体旋转和缩放；tangent-aware 策略保护平滑曲线，同时保留真实角点。如果拓扑不明确，Meld 会把不确定性写进 diagnostics，而不是藏在某一帧里。

## 物理、质量与可观测性

```dart
final plan = MeldEngine(
  sampling: const SamplingConfig(pointCount: 64, adaptive: true),
).plan(MenuButton.menu, MenuButton.close);

final json = plan.toJson();
final restored = MeldPlan.fromJson(json);
```

Plan 是确定性的并且可以序列化。缓存是有界 LRU，并提供命中/未命中指标。`MeldDiagnosticsOverlay` 是可选的调试面板，可查看缓存、残差、采样点、弹簧和规划耗时；发布版不需要时不要放入布局。

运行可复现的桌面 benchmark：

```bash
melos bootstrap
melos run benchmark
```

benchmark 输出适合在 CI 中比较。出现回归时先检查 plan diagnostics，再决定是否调整质量档位。

## 无障碍与平台

`MeldIcon` 是标准 Flutter Widget，可在移动端、桌面端和 Web 使用，不依赖 platform channel。提供 `label` 暴露 image 语义；纯装饰图标使用 `excludeFromSemantics`。`MeldMotionMode.user` 遵循 `MediaQuery.disableAnimations`，`never` 直接落到端点，`always` 适合 Showcase 或受控预览。

## Showcase 与文档

[`examples/showcase`](https://fluttercandies.github.io/meld/) 是响应式验收工具，不使用 mock 业务数据。它支持起点/终点独立选择、快捷图标对、原始 path data、SVG markup、真实 Flutter 字体轮廓、progress 拖拽、spring 参数、质量档位和实时 diagnostics 面板。

- [架构](guides/architecture.md)
- [性能](guides/performance.md)
- [故障排查](guides/troubleshooting.md)
- [迁移说明](guides/migration.md)

## 开发

Meld 使用 Melos 管理 workspace。修改前先阅读 `GOALS.md`。开发流程是“设计 → 完整实现 → 静态检查 → 定向验证 → 全量回归”，本项目不采用 TDD。

```bash
melos bootstrap
melos run format
melos run analyze
melos run test
melos run benchmark
```

## 许可证

Meld 使用 [MIT License](LICENSE)。字体文件由提供它们的应用负责，分发字体字节前请检查字体自身许可证。

欢迎打开 Showcase 体验，提交带有可复现 fixture 的 issue，或向 <https://github.com/fluttercandies/meld> 发送聚焦的 pull request。
