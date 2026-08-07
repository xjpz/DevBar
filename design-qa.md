# 个人中心视觉 QA

- 视觉基线：`docs/assets/ios-profile-message-center-option-3.png`
- 基线尺寸：853 × 1844
- 实现页面：`DevBariOS/Views/IOSProfileView.swift`
- 验收状态：已完成代码级对齐；运行截图对比待完成
- 当前实现截图：`/var/folders/46/snvj_qw957s1kkc2czg1kt300000gn/T/codex-clipboard-e1386d73-2f51-4f29-a77e-aa47eb49d50b.png`
- 当前截图尺寸：1179 × 2556（393 × 852 pt，@3x）

## 已对齐项目

- 页面由系统 `List/Form` 改为预览中的独立标题、资料头部、消息主卡片、账户卡片和退出卡片结构。
- 头像使用等宽等高圆形裁切；首页工具栏入口同时约束为圆形按钮边界。
- 消息卡片展示两条摘要、未读数量和“查看全部”入口。
- 昵称默认仅展示；点击铅笔后进入内联编辑，且只有昵称实际变化时才显示圆形确认按钮。
- 退出登录使用独立卡片，不再显示头像/昵称存储说明。
- 页面背景、卡片圆角、浅蓝强调色和留白按预览重新实现，并保留深色/Geek 主题适配。

## 验证记录

1. `xcodebuild` DevBariOS Debug / generic iOS Simulator：通过。
2. `./scripts/codex-verify fast`：280 项测试通过。
3. `xcrun simctl list devices booted`：没有已启动设备，无法获取实现截图。

## 对比历史

### 第一次真机截图

- `[P1]` 页面横向溢出：有限的 `maxWidth` 在纵向 `ScrollView` 中采用了子视图理想宽度，导致整组内容宽于 393 pt；标题、头像、卡片左侧和卡片圆角均被裁切。
- `[P2]` 首页头像入口偏大：36 pt 的视觉尺寸加上工具栏控制区域后，比右侧工具栏图标明显更重。
- 修正：使用 `GeometryReader` 按视口明确计算内容宽度（手机为视口减去 40 pt，宽屏上限 620 pt），所有卡片固定填满该内容宽度；头像视觉尺寸改为 30 pt，工具栏容器改为 32 pt。
- 修正后截图：等待用户重新运行当前构建后提供，或启动 Simulator 后由 Codex 捕获。

### 第二次真机截图

- 截图：`/var/folders/46/snvj_qw957s1kkc2czg1kt300000gn/T/codex-clipboard-28995f0f-9a49-49cf-9970-4f15cfc533f0.png`
- `[P1]` 固定为 353 pt 的内容虽然不再自身溢出，但外层 `.frame(maxWidth: .infinity)` 在 `ScrollView` 内容坐标系中扩张到约 521 pt，再将内容居中到 x=84 pt，造成所有卡片右侧统一被裁切。
- 修正：外层宽度不再使用无限值，直接固定为 `GeometryReader` 提供的屏幕宽度；393 pt 外框中居中 353 pt 内容，左右间距确定为 20 pt。
- 修正后截图：等待用户重新运行当前构建后提供。

### 第三次真机截图

- 截图：`/var/folders/46/snvj_qw957s1kkc2czg1kt300000gn/T/codex-clipboard-9d4da4c8-448d-4a94-b9bf-0bae42be8e72.png`
- `[P1]` 第二次修正后偏移未发生变化，说明前景外框不是根因。结合固定的 63–64 pt 偏移复查布局后确认：`IOSProfileBackground` 内含 520 pt 装饰圆，作为根 `ZStack` 子视图参与尺寸计算，将根容器撑为 520 pt；393 pt 前景随后在其中居中，产生 `(520 - 393) / 2 ≈ 63.5 pt` 的额外偏移。
- 修正：装饰背景从根 `ZStack` 移入 `ScrollView.background`，并约束、裁切到视口尺寸；背景只负责绘制，不再参与前景布局计算。
- 修正后截图：等待用户重新运行当前构建后提供。

### 第四次真机截图

- 个人中心截图：`/var/folders/46/snvj_qw957s1kkc2czg1kt300000gn/T/codex-clipboard-1d420d78-d197-4c61-9637-48bbea9845ba.png`
- 账户与隐私截图：`/var/folders/46/snvj_qw957s1kkc2czg1kt300000gn/T/codex-clipboard-bcfdda64-45a9-440c-a379-a52e524e7214.png`
- 横向布局已恢复，左右留白与卡片边界完整。
- `[P2]` “账户与隐私”及“退出登录”卡片分别为 82 pt、76 pt，高于预览图约 64 pt、60 pt 的视觉密度。
- `[P2]` 账户与隐私页 Apple 登录单行出现过高留白；用户 ID 和头像说明属于用户明确要求移除的信息。
- 修正：两张按钮卡片高度改为 64 pt、60 pt；Apple 登录改为固定 50 pt 的显式单行布局；账户仅保留昵称，并删除用户 ID 与头像分区。
- 修正后截图：等待用户重新运行当前构建后提供。

## 后续视觉检查

启动 iPhone Simulator 后，进入已登录的个人中心并截图；需要在相同页面状态下与视觉基线并排检查标题位置、卡片宽度、纵向间距、头像尺寸和文本换行。

final result: blocked
