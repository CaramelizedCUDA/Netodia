# Windows SMTC 证据包

日期：2026-11-09。范围为本机 Windows SMTC。本包按阶段保留原始、补证和最终提交的记录；业务修复保持同一五文件范围。

**当前待审核代码以 `final/` 为准**：提交 `fdd2bc728ecd37ddb6b962fc59a3c70089309f22` 已整合上游 `d08a2d35…`，完整补丁为 `final/source.patch`。父目录的 `source.patch`、`build-capture.json` 及下表记录对应此前 `7c86a143…` 基线，作为历史证据保留。请先看 `PR-readiness.md` 和 `final/README.md`，再按需追溯旧记录。

## 从哪里开始核对

| 文件 | 性质与用途 |
|---|---|
| `original/native-result.original.json` | 上一轮脚本直接写出的原始匿名 JSON，逐字节保留，未补写字段 |
| `original/native-acceptance.executed.ps1` | 上一轮成功执行的原生验收脚本，逐字节保留 |
| `original/assertions.summary.json` | 从原始 JSON 和脚本调用关系派生的索引；不是新执行输出 |
| `derive_original_summary.py` | 上述派生索引的生成代码 |
| `native-result.replay.json` | 本轮只重复一次同一矩阵，脚本直接输出的新证据，含逐字段断言、命令返回值和观察边界 |
| `replay/acceptance.ps1` | 本轮实际执行的增强记录脚本；不对客户端注入成功日志或测试 API |
| `replay/prepare.py` | 数据副本和可控封面准备脚本；整合了此前手动执行的独立文件名准备步骤 |
| `replay/run.ps1` | 调用准备和验收脚本，并检查、清理私有副本 |
| `cleanup.replay.json` | 本轮实际清理检查结果，仅证明测试副本和上下文文件已删除 |
| `source.patch` | 从公开上游基线到完整当前修复的补丁，包含最初本地提交和之后工作区修订，包括未跟踪的新测试文件 |
| `build-capture.json` | 本轮构建实际返回码、工具链版本、补丁哈希、逐文件哈希和受测二进制哈希 |
| `capture_source.py` | 捕获补丁、隔离验证补丁、构建和记录来源的脚本 |
| `verify_evidence.py` | 只读核对导出文件哈希、原始/派生关系及回放与构建清单的一致性，不代替重新执行 |
| `evidence-manifest.json`、`SHA256SUMS` | 证据文件完整性索引；不是第三方签名或执行公证 |

## 原生断言如何判定

预期元信息来自**测试副本**的 `queue-seed.json / playlist_tracks`，不是数据库查询，也不是人工目测。数据库副本用于客户端正常启动，不作为这些断言的预期值来源。

准备脚本选择非首项 A 和相邻、标题不同的 B，并保证两者标题都不同于首项。它将 A 的封面设为不存在的本地文件，将 B 等其他项的封面设为有效合成 PNG。原始曲名、艺术家、专辑、ID、歌曲时长及数据副本没有打包。

实际值来自 Windows WinRT：

- `TryGetMediaPropertiesAsync()`：`Title`、`Artist`、`AlbumTitle`；
- `GetTimelineProperties()`：`EndTime.TotalMilliseconds`、`Position.TotalMilliseconds`；
- `GetPlaybackInfo().PlaybackStatus`：播放状态。

`Checkpoint` 逐字段执行以下比较；任何一个失败都会使脚本失败：

| 字段 | 规则 |
|---|---|
| 标题 | 与预期标题区分大小写的字符串相等 |
| 艺术家、专辑 | 与预期字段转为字符串并去除首尾空白后的值区分大小写相等 |
| 总时长 | SMTC `EndTime` 的毫秒数与预期 `duration_ms` 精确相等 |
| 播放状态 | 与该检查点明确指定的 `Paused` 或 `Playing` 相等 |
| 非首项 | 实际标题不同于种子队列第一项标题；准备脚本另行选择非首项索引 |

`expected_track_match` 是标题、艺术家、专辑、总时长四个比较结果的合取，**不是歌曲 ID 校验或音频内容识别**。

恢复位置是准备脚本在副本中设置的 **1000 ms**，允许误差 **100 ms**；不是用户原始保存位置。进度推进要求 15 秒内增加超过 1000 ms；暂停稳定性是在 1200 ms 采样间隔内变化不超过 100 ms。恢复播放检查了状态和元信息，没有另外声称测量了恢复后的声音或音频链路。

下面是本轮结果的跨字段摘录，字段分别来自 `checks[0]` 和 `position_assertions`，不是另一份独立观测：

```yaml
case: startup_restore_bad_cover
expected_track_alias: A
expected_source: private queue-seed.json
expected_track_match: true
title_match: true
artist_match: true
album_match: true
duration_match: true
position_match: true
playback_status_match: true
```

## 返回值、状态断言和日志观察分开解读

1. **原生状态断言**：六个检查点的字段比较全部成立。它证明读到的 SMTC 状态匹配受控输入。
2. **媒体控制 API 返回值**：本轮直接记录 `TryPlayAsync`、`TrySkipNextAsync`、`TryPauseAsync`、`TryPlayAsync`、`TrySkipPreviousAsync` 的返回值，五个均为 `true`。其含义是媒体控制命令被接受，不是 `set_metadata()` 返回值，也不是声音输出成功。
3. **日志观察**：下表来自对测试实例日志匹配行数的增量统计。没有修改客户端日志来制造证据。

| 观察边界 | 带封面发布失败日志累计行数 | 相对前一观察边界增量 | 文字/清空失败日志累计行数 |
|---|---:|---:|---:|
| 启动前 | 0 | — | 0 |
| A 启动恢复断言后 | 1 | 1 | 0 |
| A 播放和进度断言后 | 1 | 0 | 0 |
| 下一首 B 断言后 | 1 | 0 | 0 |
| 暂停 B 断言后 | 1 | 0 | 0 |
| 恢复 B 断言后 | 1 | 0 | 0 |
| 返回 A 断言后 | 2 | 1 | 0 |
| 测试进程退出后 | 2 | 0 | 0 |

统计使用的字符串为：

```text
Failed to set media metadata with artwork:
Failed to set media metadata:
Failed to clear media metadata:
```

第一类日志在带封面调用报错、即将尝试文字兜底时产生，**不是兜底成功日志**。本轮两条记录均提取到通用错误码 `0x80070002`。日志可能缓冲，因此表格表示“在哪个观察边界看到新增行”，不能当作无延迟的函数调用跟踪。

“文字/清空失败日志为 0”严格只表示**未观察到匹配的失败日志**。客户端原生 `set_metadata()` 返回值没有被记录。本轮没有专门触发元数据清空或强制文字发布失败；这些控制分支由前一轮模拟面板单元测试覆盖，不能将其冒充本轮原生清空验收。

上一轮原始 JSON 只保留了总增量 `2` 和 `0`，没有逐事件计数或错误码数组。它们不能被追溯性补写；本轮新证据独立保存，未覆盖旧输出。

## 源码、构建和二进制的关联

可独立应用的基线是公开提交：

```text
7c86a143d13db5141c711b275ec948bf684d5d48
```

不需要先取得本地未推送的 `483c0bcb`。`source.patch` 已包含它及当前工作区完整修订。

本轮已经执行：

- 在隔离目录还原补丁涉及的基线文件；
- `git apply --check`，然后在该隔离目录实际应用补丁；
- 将得到的五个源码文件与工作区文件逐字节比较，全部一致；
- 构建前记录五个源码文件及 Cargo、锁文件、工具链和构建配置的哈希，构建后确认未变化；
- 构建成功后记录二进制哈希；原生脚本开始时再次校验二进制及全部记录的源码输入。

本轮绑定值：

```text
source.patch SHA-256:
86009027ada03b7aa737512bfad441fdbe135fed5869d8523e891fc78358f3e3

source snapshot SHA-256:
32a0d82ffd51834e6afb8c3db5bc2fd6dd1c6b004687f425c34fda49441315b1

replay binary SHA-256:
db72c78051b56563d7959ff8d9e61a2df4479687918bc56de021b8a329000b32
```

旧输出所指的 `7f7960…` 二进制与本轮重建的 `db72c7…` 分开记录。没有将新源码清单冒充为旧运行当时自动生成的构建证明。二进制哈希用于标识本机受测产物，不承诺其他机器可以得到逐字节相同的 Debug 二进制。

## 独立复现

先核对现有包内文件及记录的一致性（不启动客户端、不改文件）：

```powershell
python review-materials/windows-smtc/verify_evidence.py
```

在另一份 Windows 检出中先切换到上述基线，从仓库根目录执行：

```powershell
git apply --check review-materials/windows-smtc/source.patch
git apply review-materials/windows-smtc/source.patch
python review-materials/windows-smtc/capture_source.py
powershell.exe -NoProfile -ExecutionPolicy Bypass -File review-materials/windows-smtc/replay/run.ps1
```

不要在已经包含该补丁的工作区再次应用。运行前先另存本证据包，因为捕获和回放脚本会写入新的清单与结果。本轮已实际执行上述捕获和回放脚本；补丁应用步骤是在隔离基线副本中验证的，没有回退或改写当前工作区。

复现需要 Windows、仓库指定的 Rust 工具链、Python，以及本机可播放的有效队列。当前准备脚本按本机实际输入契约读取 `%APPDATA%/Netodia` 中的 `settings.json`、`views.json`、`netease-favorites.json`、`netodia.db` 和 `queue.json`；不是为缺少这些输入的全新安装编写的通用夹具。队列的 `playlist_tracks` 必须至少能选择标题不同于首项的 A 和相邻 B。运行脚本会启动独立命名、静音、共享输出的测试实例，控制该实例并在结束后清理其私有副本；不需要向审查者提供本机私有队列或数据库。

## 证据边界

- 本轮新执行：补丁应用及逐字节核对、源码快照绑定构建、一次相同 Windows 原生矩阵、私有副本清理。
- 上一轮保留：22 条媒体控制测试、完整 workspace Clippy、格式和差异检查；本轮没有为了补证而重跑这些检查。
- 更早保留：`netodia-net` 112 条此前版本测试通过，之后相关网络源码未改动；**未在最终构建或本次补证重新执行**。
- 不主张验证实际可听声音、独占音频、所有真实封面、Release 构建、Linux/macOS，或整个 workspace 测试套件。上述六检查点矩阵的缩略图断言仅为引用非空；随后真实 CDN 验收的字节比较单列在下节。
- 没有修改旧封面暂留这一既有依赖行为，没有安装、提交、推送或上传任何材料。
- 私有种子队列和原始日志按脱敏要求删除。审查者可以审核脚本、匿名输出、补丁和哈希，并在自己的有效输入上重复执行；本包不是第三方执行公证。

## 追加原生验收与 PR 草稿

`remote/` 是新增的真实 CDN 封面验收，不替代或改写 `original/` 和 `replay/` 的历史证据。它保留私有队列中的真实远程 URL，在新的空缓存副本中播放一个非首曲，读取原生 WinRT 缩略图字节并与本地新缓存文件计算结果比较。导出结果不含歌曲字段、URL、真实图片或图片哈希。

最终 `remote/native-result.json` 为通过：暂停恢复时缓存 0、缩略图无；播放后缓存 1、原生缩略图与缓存字节匹配；元数据字段与预期匹配且进度推进。原有实例仍运行，测试副本已清理。原生文字发布返回值没有被采集，也没有触发完整文字/清空失败。

`remote/attempt1/` 保留首轮未完成核对的失败输出及实际执行脚本。失败属于验收脚本的 WinRT 接口投影和释放错误；修正后只完整重跑了一轮。首轮输出中未执行到的后续字段是初始化值，不能作为缓存状态观测。

可在满足前述本机输入契约的 Windows 检出上单独重复这条路径（真实云音乐播放还需有效账户/网络和可播放曲目）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File review-materials/windows-smtc/remote/run.ps1
```

`PR-title.txt` 与 `PR-draft.md` 按上游 PR 模板准备；`PR-readiness.md` 单列正式提交前的事项。草稿明确重试依赖后续 `with_state_emit()`，五秒不是自动唤醒定时器。该阶段没有创建 GitHub PR、提交或推送；随后最终准备阶段已将完整代码提交到用户 fork，当前状态以 `PR-readiness.md` 为准。


## 最终准备完成记录

最终完整 Windows workspace 测试为 3530 passed / 0 failed / 0 ignored / 0 filtered out，Clippy、格式和构建成功；同一最终产物的坏封面六检查点与真实 CDN 两检查点通过。最终首次暂停超时及补充普通播放前置条件后的结果分开保留，归因未确认，不因后一次通过而删除前一次失败。

使用 `python review-materials/windows-smtc/final/verify_final.py` 核对新提交证据；父目录 `verify_evidence.py` 核对整个导出包及历史记录。先前基线的原始脚本和匿名输出均保留原样。
