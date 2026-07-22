# AppPorts 1.8.0 用户体验可靠性改造设计

日期：2026-07-22  
状态：已获用户实施授权，分批实施中  
目标：在不改变既有迁移布局和磁盘格式的前提下，把扫描、迁移、权限和失败恢复状态完整地传达给用户。

## 背景与范围

1.8.0 的视觉骨架、原生 Settings、列表选择和迁移回滚基础已经存在。当前高风险问题集中在状态边界：旧扫描可能覆盖新路径，长操作无法取消，空列表无法区分失败，成功但有警告不会到达 UI，选择集合可能与列表脱节。

本轮按以下顺序实施：

1. 扫描一致性、外部卷身份和选择集合安全性。
2. 迁移操作生命周期、取消、容量预检和结果状态。
3. 空态、权限旅程、批量失败恢复和进度阶段。
4. 键盘/VoiceOver、窄窗口、徽章密度、路径操作和更新提示。

不改变：外部目录布局、现有 UserDefaults 键、既有回滚算法、最低 macOS 12.0 部署目标；不引入第三方依赖或一次性重写整个 View 架构。

## 设计原则

- 用户看到的路径、列表和当前操作必须来自同一个快照。
- 长操作必须可观察、可取消或明确说明不可取消的阶段。
- “空”“失败”“未扫描”“搜索无结果”“卷离线”必须使用不同状态。
- 批量操作先做一次资格预检，显示将执行、跳过和原因。
- 服务层返回结构化结果，UI 不通过日志推测成功与否。
- 任何状态改造都保留 macOS 12 回退路径。

## 1. 扫描协调器

新增轻量 `ApplicationScanCoordinator`（可先作为 ContentView 内部类型，稳定后再独立文件），负责保存本地、外部和原子扫描 Task，以及每类扫描的 generation。

每次扫描快照包含：

- 标准化根路径；
- 外部卷 resource identifier/volume UUID（能取得时）；
- 自定义扫描目录快照；
- 当前 generation。

扫描完成后只有在 Task 未取消、generation 仍匹配、外部路径和卷身份仍匹配时才能提交结果。路径切换立即取消旧 Task、清除旧选择，并将列表置为 `scanning`，而不是暂时显示旧数据。

扫描状态统一为：`notStarted`、`scanning`、`loaded`、`loadedEmpty`、`searchEmpty`、`offline`、`failed(message)`。扫描器不再把所有读取错误静默折叠为 `[]`；兼容现有调用时可先返回列表和 warning 集合。

每次提交列表后执行：

```swift
selectedLocalApps.formIntersection(Set(localApps.map(\.id)))
selectedExternalApps.formIntersection(Set(externalApps.map(\.id)))
```

并以同一份 `ActionPreflight` 计算底栏标题、启用状态和确认摘要。

## 2. 迁移操作生命周期

新增场景级 `MigrationOperationState`，由 ContentView 持有并传给三个功能区，而不是让子 View 自己持有无法追踪的 Task。

阶段：

- `preparing`：检查权限、容量、卷连接和资格；
- `copying`：可取消，FileCopier 在递归、文件之间和重试循环检查 cancellation；
- `committing`：创建入口、切换源目录、写标记；明确提示暂不可取消；
- `finalizing`：清理、锁定、重签名和刷新；显示阶段进度；
- `finished(OperationOutcome)` / `cancelled` / `failed`。

进度组件根据操作类型显示“迁移、接回、链接、还原”等动态文案。没有可靠字节总量时使用 indeterminate ProgressView；单个大文件复制时至少先显示当前文件，并按时间节流刷新。

覆盖层必须阻止底层操作被键盘/VoiceOver 激活，并保留全局取消或退出确认入口。切换 tab 不得隐藏仍在进行的操作。

## 3. 预检与结构化结果

新增可测试的 `ActionPreflight`，输出：

- eligible items；
- skipped items 与原因（运行中、系统应用、已链接、权限、App Store/iOS 设置）；
- 估算总大小；
- 目标卷可用空间、是否同启动卷、是否离线；
- 推荐动作和按钮文案。

迁移服务和 `DataDirMover` 逐步返回 `OperationOutcome`：

- `success`；
- `successWithWarning(message, recoveryURLs)`；
- `rolledBack(message)`；
- `failed(error, recoveryState)`。

批量操作保留每项结果，不因第一项失败而丢失后续状态；完成页支持仅重试失败项、在 Finder 中显示和复制诊断信息。

## 4. 权限、空态和恢复

权限检查按能力拆分：应用 Bundle 修改、用户目录读取、目标目录写入和重签名分别检查。README、欢迎页和数据目录页统一术语；“稍后”只跳过当前会话，永久关闭必须明确叫“不再提示”且可在设置恢复。

应用页和数据目录页使用统一状态枚举，空态提供下一步动作。外部卷挂载/卸载时通过 NSWorkspace 通知或可靠的可用性检查更新状态，离线时暂停相关按钮。

## 5. 后续可见 UX

- `⌘F` 聚焦当前页面搜索，不隐式切换主 tab；数据目录搜索提供同等焦点入口。
- 主要文字使用语义字体，选择态不只依赖颜色，装饰图标隐藏或汇总成 AX value。
- 视图宽度使用窄宽 fallback，路径提供复制/Finder 操作。
- 状态徽章保留一个主状态，框架/签名/锁定信息收进详情。
- 更新提示改为非阻塞，显示版本差异并支持跳过版本。
- 自定义目录“移除记录”必须说明只移除配置，并对已链接状态确认后再执行。

## 验证策略

每个批次都执行外置 Xcode Debug build 和相关单元测试；最终执行 Release clean build、全量测试、LocalizationAuditTests，以及真实 UI/AX 验证。

必须补充的行为测试：

- 外部卷 A/B 扫描乱序提交；
- 取消和 partial/backup/staging 恢复；
- 容量不足、卷离线和权限矩阵；
- 批量部分失败与仅重试失败项；
- warning outcome 到 UI 的展示；
- 搜索/扫描后选择集合交集；
- 当前页面搜索焦点与进度 overlay 的 AX 语义。
