# PR 提交准备记录

2026-11-09：按用户授权推进到创建 PR 前的最终审核。尚未创建 PR。

## 已完成

- 新分支 `codex/windows-smtc-metadata` 已整合上游 `d08a2d3584c59a87ba899fb6330c0910590579e3`。
- 完整五文件补丁已纳入单一提交 `fdd2bc728ecd37ddb6b962fc59a3c70089309f22`；五个文件与此前审核版本逐字节一致，隔离补丁应用核对通过。
- 新提交作者与提交者均使用账户 GitHub noreply 邮箱；原私人邮箱提交仅保留在本地原分支，不在新分支新增历史中。
- 已创建 `CaramelizedCUDA/Netodia` fork，配置为 `fork` 远端与默认推送目标；`origin` 继续指向作者仓库。
- 最终提交完整 Windows workspace 测试通过：3530 passed，0 failed，0 ignored，0 filtered out，52 个测试目标。包含 22 条媒体控制、112 条网络测试和真实音频设备的 headless 扫描测试。
- 格式检查通过。第一次完整测试在编译时因 Windows 页面文件不足（E0786 / os error 1455）失败；单任务构建重跑后全套通过，没有跳过测试、修改页面文件或仓库/全局构建设置。

## 最终门禁与原生结果

- 全 workspace / all-targets Clippy 通过。
- 最终提交构建成功；受测二进制 SHA-256：`b0148070fe3a4053554ab864c6059256ddd082252b27ec2ef3c868e48b124987`。
- 坏封面矩阵六检查点通过；真实 CDN → 本地缓存 → 原生缩略图字节匹配通过，均绑定同一最终二进制。
- 首轮坏封面矩阵的暂停超时保留在 `final/bad_cover-attempt1/`。随后一次重跑增加实际进度前进的普通播放前置条件后通过；首轮归因未确认，详见 `final/README.md`。没有修改业务源码或放宽断言。
- 代码分支已推到用户 fork，提交 SHA 与本地一致。证据采用独立的 `codex/windows-smtc-evidence` 分支。发布前核对脱敏、文件清单和哈希；最终远端 SHA 单独核验。不创建 PR。

## 保留的范围说明

重试由后续状态事件经 `with_state_emit()` → `sync()` 触发；五秒截止时间本身不会主动唤醒。完整文字/清空失败后的原生恢复仍未触发。草稿限定为坏封面不阻断文字和时长，不承诺所有 SMTC 故障的自动恢复。

Linux/macOS 不做本机原生实测，其专用运行代码和测试不在补丁范围。私人交接文档、真实队列、数据库、封面和日志原文不会推送。

## 最终审核入口

- 代码比较：<https://github.com/HELPMEEADICE/Netodia/compare/main...CaramelizedCUDA:codex/windows-smtc-metadata>
- PR 正文：`PR-draft.md`；标题：`PR-title.txt`。
- 最终证据：`final/`；完整文件和报告由证据分支提供，代码 PR 仍为五文件改动。
- 已完成的本机验证与未确认归因的暂停观察均保留供审核；本轮不再增加测试或扩大修复。

用户最终审核通过后才创建 PR。未向作者提交 issue、评论或 PR。
