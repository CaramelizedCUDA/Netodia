# Windows SMTC 验收记录（脱敏）

日期：2026-11-09。

当前待提交代码已经整合上游 `d08a2d3584c59a87ba899fb6330c0910590579e3`，代码提交为 `fdd2bc728ecd37ddb6b962fc59a3c70089309f22`。最终验证记录位于 `review-materials/windows-smtc/final/`。下文此前基线、工作区修订和原生输出按历史阶段保留，不代表新提交仍未纳入完整补丁。

本记录更新交接文档中的验收范围、构建记录与实际运行结果。范围仅限本机 Windows；Linux/macOS 不纳入本次实测，也不以缺少这两个平台的实测作为本次 Windows 验收的待办。

## 验收对象与范围

- 环境：Windows 11，版本 `10.0.26300`，Rust 工具链 `1.97.0`。
- 原运行源码定位：本地 `483c0bcb` 提交及当时工作区修订，尚未提交或推送；仅检出该提交不足以复现完整修复。
- 原运行产物：Windows debug 构建，SHA-256：
  `7f7960e204a86e2f883f50ac099d526c84ca059db8f3f9d024d10b8dd2a2acfc`。
- 本轮补证提供从公开基线 `7c86a143d13db5141c711b275ec948bf684d5d48` 到完整修复的 [source.patch](review-materials/windows-smtc/source.patch)，包括未跟踪的新测试文件。补丁在隔离基线副本中实际应用后，五个源码文件均与当前工作区逐字节一致。
- 本轮按源码清单重新构建并绑定一次相同矩阵的原生回放。新产物 SHA-256 为 `db72c78051b56563d7959ff8d9e61a2df4479687918bc56de021b8a329000b32`，与原产物分开记录；没有追溯性补造原运行的构建清单。
- 使用真实队列和数据库的一致副本；不在公开材料中保留曲名、艺术家、专辑、曲目 ID、实际歌曲时长、个人路径或日志原文。
- 副本设置为静音和共享音频输出，关闭自动更新；用独立可执行文件名区分测试 SMTC 会话。
- 仅控制测试会话。验收结束时，原安装实例仍运行，测试实例已退出。
- 包含真实数据的副本已删除，保留的结果为匿名匹配布尔值和通用错误计数。

## Windows 原生结果

选择队列中不同于第一首的曲目 A，以及相邻的另一首曲目 B。曲目 A 使用不存在的本地封面，曲目 B 使用有效的合成 PNG 封面。以下操作通过真实 Windows SMTC 会话完成，未用模拟面板代替这些原生结果。

这些结果由脚本逐字段比较，不是人工目测。预期元信息来自测试副本的 `queue-seed.json / playlist_tracks`，并非从数据库读取；实际值来自 WinRT 的 `TryGetMediaPropertiesAsync()`、`GetTimelineProperties()` 和 `GetPlaybackInfo()`。标题精确比较；艺术家和专辑与预期值去除首尾空白后精确比较；总时长按毫秒精确比较；状态与各步骤指定的 `Paused`/`Playing` 比较。

恢复位置是测试副本设定的 **1000 ms ± 100 ms**，不代表原始用户保存位置。进度要求在 15 秒内前进超过 1000 ms；暂停稳定性采样间隔 1200 ms，允许变化不超过 100 ms。

原运行的 [匿名原始输出](review-materials/windows-smtc/original/native-result.original.json) 和 [实际执行脚本](review-materials/windows-smtc/original/native-acceptance.executed.ps1) 均逐字节保留。另有 [派生断言索引](review-materials/windows-smtc/original/assertions.summary.json)，明确标注其不是新执行结果。

| 场景 | 核对内容 | 结果 |
|---|---|---|
| 启动恢复 A，保持暂停 | 标题、艺术家、专辑、总时长、保存位置及暂停状态 | 全部匹配；未停留在第一首 |
| 播放 A | 文字、总时长、播放状态及进度推进 | 全部通过 |
| 下一首至 B | 文字、总时长及播放状态 | 全部匹配；未停留在第一首 |
| B 的有效本地封面 | SMTC 提供缩略图引用 | 通过 |
| 暂停 B | 信息保持正确，暂停位置不再前进 | 通过 |
| 恢复 B | 信息和播放状态正确 | 通过 |
| 上一首回到 A | 信息和播放状态正确，坏封面不阻断文字发布 | 通过 |

原运行的计数来源是整个验收区间内的日志匹配行数增量：带封面发布失败日志 **2 行**，文字发布或清空失败日志 **0 行**。第一类日志在准备文字兜底前输出，不能直接称为“兜底成功 2 次”；第二类的 0 只表示**未观察到相应失败日志**，不表示记录了所有原生发布返回值。原运行未保留逐事件日志或错误码数组，不再据其总计数反推事件归属。

本轮仅为补强追踪，重复一次相同矩阵，直接保存 [增强原生输出](review-materials/windows-smtc/native-result.replay.json)。六个检查点均逐字段通过，五个媒体控制 API 的实际返回值均为 `true`。日志观察边界显示：A 启动恢复后累计 1 行，B 的各阶段累计仍为 1 行，返回 A 后累计 2 行，退出后仍为 2 行；两条日志均提取到通用错误码 `0x80070002`。这是观察边界计数，仍需考虑日志缓冲，不能当作无延迟调用跟踪。

媒体控制 API 返回 `true` 表示命令被接受，不是 `set_metadata()` 的返回值。文字发布效果由 SMTC 状态断言确认；客户端原生 `set_metadata()` 返回值没有被记录。原生矩阵未专门触发清空或强制文字发布失败，这些分支的单元测试结果另列，不提升为原生验收结论。

验收准备期间修正了脚本对 WinRT 集合的枚举方式，以及同名 `Netodia.exe` 的会话区分方式。这些是验收脚本问题，不是客户端的播放或元数据回归；最终脚本仅选择独立命名的测试实例。

## 代码与自动检查

- 新增的封面处理、失败回退和重试逻辑仅在 Windows 编译。
- MPRIS 目录相对上游基线 `7c86a143` 无差异。
- macOS 元数据发布代码块与该基线逐字比对一致；非 Windows 封面转换保留原有实现。
- 新增的相关测试仅在 Windows 编译；未新增或修改 Linux/macOS 专用测试行为。
- 未新增依赖，未修改网络 URL 解析器、响应体限制或保护测试的豁免表。

| 检查 | 时间分类与结果 |
|---|---|
| `cargo test --locked -p netodia-integrations --lib media_controls` | 上一轮最终修复源码检查：22 条通过；本轮补证未重跑 |
| `cargo test --locked -p netodia-net` | 更早版本：112 条通过，之后相关网络源码未改动；**未在最终构建或本轮补证重新执行** |
| `cargo clippy --all-targets --locked --workspace -- -D warnings` | 上一轮最终修复源码检查成功退出；本轮补证未重跑。存在增量缓存硬链接失败后复制回退的环境提示 |
| `cargo fmt --all -- --check` | 上一轮通过；本轮没有修改业务源码 |
| `git diff --check` | 上一轮通过；本轮补证材料写入后也已通过 |
| `net_primitives` | 上一轮最终修复源码 2 条通过；本轮补证未重跑，命令级构建设置见下节 |
| 完整补丁应用及文件核对 | 本轮新执行，5 个源码文件逐字节匹配 |
| 来源绑定构建 | 本轮新执行，退出码 0，构建前后输入哈希不变 |
| 同一 Windows 原生矩阵 | 本轮新执行 1 次，6 个检查点和位置断言均通过；未增加验收场景 |

本轮没有执行完整 workspace 测试套件。

本记录不证明实际可听声音、独占音频模式、所有真实封面或 Release 构建的行为。合成封面检查仅验证 SMTC 缩略图引用非空，不是图像内容比对。这些均不作为本次 SMTC 验收待办扩展。

完整方法、逐阶段计数、源码清单、哈希与独立复现步骤见 [证据包说明](review-materials/windows-smtc/README.md) 及 [构建捕获清单](review-materials/windows-smtc/build-capture.json)。哈希用于关联这些本地材料，不是第三方执行公证。

## 保留的 Windows 构建记录

默认完整调试信息的 `cargo test --locked -p netodia --test net_primitives` 曾在应用链接阶段遇到 MSVC 未解析符号错误。当时 `netodia_views` 静态库约为 4.37 GB。

仅对该 crate 在单次命令中减少调试信息后，静态库约为 249 MB，应用链接成功，原有两条保护测试均通过：

```powershell
cargo test --locked -p netodia --test net_primitives --config 'profile.test.package.netodia-views.debug=1'
```

用于原生验收的可执行文件通过以下命令构建成功：

```powershell
cargo build --locked -p netodia --config 'profile.dev.package.netodia-views.debug=1'
```

以上结果支持链接问题与过大的调试构建产物有关，但没有进一步断言其底层根因。没有将这些覆盖设置写入仓库或全局配置，也没有关闭断言、跳过测试或放宽安全检查。

## 保留的既有行为

souvlaki 的 Windows 后端在 `cover_url: None` 时不主动清除旧缩略图。这是原有依赖行为，没有作为本次修复引入的回归处理，也没有为此增加清除封面的原生接口。本次修复的目标是使坏封面不再阻断当前歌曲文字及总时长的发布。

安装版可执行文件没有替换；本记录不代表已安装或发布当前工作区修订。

## 追加：真实 CDN 封面的原生验收与重试调用链

本节记录随后新增的两轮最小验收，不改写前述坏封面矩阵的历史结论。业务源码未改动，继续使用 `build-capture.json` 绑定的同一补丁、源码快照和可执行文件。真实队列的远程封面 URL 被保留在私有副本中，`netease-artwork` 初始为空，没有直接向 SMTC 填入合成图片或预制缓存。

| 观察或断言 | 最终原生结果 |
|---|---|
| 暂停恢复非首曲 A | 标题、艺术家、专辑、时长及暂停状态逐字段匹配 |
| 恢复时缓存文件数 / SMTC 缩略图 | 0 / 无 |
| 通过原生 SMTC 发送 Play | 返回 `true`，随后观察到 Playing |
| 播放后的本地封面缓存文件数 | 1 |
| WinRT 返回的缩略图内容与新缓存文件 | SHA-256 完全一致；结果仅导出匹配布尔值 |
| 当前文字、时长、状态及播放进度 | 字段匹配，进度推进超过 1000 ms |
| 从 Play 到缩略图核对之间的额外媒体控制命令 | 0 |
| 原有实例 / 测试实例 / 私有数据副本 | 原实例仍运行 / 测试实例退出 / 副本已删除 |

实际执行脚本与匿名输出见 [remote/acceptance.ps1](review-materials/windows-smtc/remote/acceptance.ps1)、[remote/native-result.json](review-materials/windows-smtc/remote/native-result.json) 和 [remote/cleanup.json](review-materials/windows-smtc/remote/cleanup.json)。真实图片、歌曲字段、URL、图片哈希和原始日志均未导出。

第一轮没有完成字节核对，结果为失败：脚本对 WinRT COM 流的接口投影及资源释放方式不正确。独立的四字节合成流检查定位后，改用显式接口反射读取和 COM 引用释放；第二轮完成上述全部断言。第一轮实际脚本和失败输出保留在 `remote/attempt1/`，未覆盖为通过结果。失败输出中尚未执行到的后续计数保留初始化值，不能当成对应实际状态的观测。

源码链路为 `cloud_playback.rs::queue_track_metadata()` 分离合法远程 URL，`download_cover()` 使用原有 `cover_request_url()` 与 `get_capped()`（1 MiB、30 秒），`store_image()` 返回缓存本地路径；`cache_cover_after_start()` 在仍为同一云曲目且尚无封面时更新 `state.source.artwork_path` 并调用 `with_state_emit()`。后者生成当前源的轻量 VM 并调用 `sync()`；封面字段的变化使元数据重新发布。原生缩略图与新缓存字节相同，为这条真实路径补上运行证据。队列持久化项仍可保存原始 URL，不能据此判断当前播放源没有转换为本地路径。

`MetadataRetry` 的实际语义也已核对：`with_state_emit()` → `MediaControlsHandle::sync()` → `MetadataRetry::publish()`。播放/暂停、切歌、封面缓存回调等状态事件可以重进；500 ms 播放监视路径仅走 `update_position()`，该函数只更新播放状态/进度。**已确认的限制是：五秒截止时间本身不会唤醒 `sync()`；没有后续状态事件时，待发布快照不会主动重试。** 发生状态事件且冷却已过后可以再次尝试，元数据变化也可绕过同一快照的冷却。

本次真实 CDN 验收没有触发完整文字/清空发布失败，也没有验证这类失败后的原生恢复；这一点仍是未验证路径，不能用本次封面成功、此前坏封面回退成功或单元测试手动推进时间代替。当前 PR 草稿将修复目标限定为坏封面不阻断文字与时长发布，并明确上述事件驱动重试限制。

## 最终提交准备：上游整合与完整 Windows 检查

最终代码提交为 `fdd2bc728ecd37ddb6b962fc59a3c70089309f22`，直接基于上游 `d08a2d3584c59a87ba899fb6330c0910590579e3`。新增历史只有一条 Conventional Commits 提交，包含完整五文件修订；五个文件与此前审核版本逐字节相同。上游新增的任务栏修改由基线继承，不计入本补丁。新提交作者、提交者使用 GitHub noreply 邮箱；含私人邮箱的原提交仅保留在本地原分支。

最终 Windows 自动检查结果：

| 检查 | 最终结果 |
|---|---|
| `cargo test --locked --workspace --jobs 1 --config 'profile.test.package.netodia-views.debug=1'` | 3530 passed，0 failed，0 ignored，0 filtered out；52 个测试目标 |
| 媒体控制子集 | 上述完整执行中 22 条通过 |
| `netodia-net` 子集 | 上述最终提交完整执行中 112 条通过，已补齐此前最终版本未重跑的证据 |
| `net_primitives` / headless 扫描 | 均在完整执行中通过；未使用 Windows CI 对 headless 的跳过参数 |
| `cargo clippy --all-targets --locked --workspace --jobs 1 -- -D warnings` | 成功退出，退出码 0 |
| `cargo fmt --all -- --check` | 通过，退出码 0 |

第一次完整 workspace 尝试在编译阶段因 Windows 页面文件/提交容量不足而失败：`E0786`，底层为 `os error 1455`，读取目标为大型 `netodia_ui` 调试静态库；该次没有进入测试。保留 `final/test-attempt1.json`，最终单任务执行结果单独记录。没有修改系统页面文件、仓库/全局配置、保护测试或断言，也没有跳过测试。

最终补丁和隔离应用结果见 `final/source.patch`、`final/source-capture.json`；原始测试输出仅本地保留，公开材料使用匿名统计与测试名摘要。本段所列结果与前文旧基线的历史检查分开，完整测试成功不提升未触发的原生失败路径为已验证。

最终构建也已成功，二进制 SHA-256 为 `b0148070fe3a4053554ab864c6059256ddd082252b27ec2ef3c868e48b124987`。本轮原生结果位于 `final/bad_cover.json`、`final/remote_cover.json`：六检查点坏封面矩阵和两检查点真实 CDN 封面均通过，缩略图字节与新缓存匹配；两个结果绑定同一构建，安装实例保持运行，测试副本已清理。

最终构建的第一轮坏封面矩阵在切到 B 后立即暂停时超时，不能记为通过，原输出和脚本保留在 `final/bad_cover-attempt1/`。第二轮在确认 B 的实际进度前进超过 1000 ms 后再发 Pause，原有元数据、暂停稳定性和状态断言均通过。没有修改业务源码或放宽断言。

首轮失败的原因未作原生调用跟踪确认。相关未修改源码可先发布曲目状态、再异步加载云播放；加载期间 Pause 会优先取消 pending 请求，这为时序解释提供依据，但不能单凭这些代码断定首轮失败走了该分支，也不能由“代码未改动”直接证明它不受补丁时序影响。本次不扩大到加载期间快速连按的边界测试，作为未确认归因的观察记录提交审核。
