# 项目开发说明

## 当前工程

这是 Godot 4.7.2 / GDScript 战斗游戏，使用 GL Compatibility 渲染，支持桌面和 Web。工程入口是 `godot/project.godot`。旧版 Lua / LÖVE 运行代码已移除。

- `godot/game.gd`：关卡、任务状态、输入、武器发射、探测、镜头和效果。
- `godot/ship.gd`：飞船物理、AI、能量、热量和伤害。
- `godot/projectile.gd`：弹体、制导、鱼雷动力和爆炸伤害。
- `godot/tactical_overlay.gd`：战术地图、HUD 图标、目标标记和跃迁读条。
- `godot/check.gd`：可运行的机制回归检查。
- `docs/design.md` 和 `docs/*.png`：原始企划与设计图。它们描述长期设计，不代表所有机制已经实现。
- `docs/legacy-art/`：旧版美术与字体参考，不参与当前运行。
- `build/`：本地导出和渲染预览，已忽略。

## 运行与验证

```sh
godot --headless --path godot --editor --import
godot --path godot
godot --headless --path godot --script res://check.gd
git diff --check
```

修改玩法后运行机制检查；修改视觉后使用实际渲染确认布局和效果。Web 导出：`godot --headless --path godot --export-release Web ../build/web/index.html`，通过 HTTP 服务运行。

## 改动约定

沿现有调用流程修正共享逻辑，优先使用 Godot 原生节点与资源，保持改动直接、依赖最少。距离单位为米，时间为秒，持续伤害、能耗和热量按 delta 结算。

保留原始企划、设计图和参考素材；调整文档位置时修复相对链接。不要重新引入旧版 Lua 实现，不提交 `.godot/`、导出包、预览图或日志。

任务顺序、跃迁输入中断、隐身与红外、跨边界距离和鱼雷变体应保留回归检查。潜行任务的炮台停机必须永久生效，主控舰必须在潜行突围后才能受伤。结束动画应继续允许爆炸效果播放，并在重开关卡时清理。
