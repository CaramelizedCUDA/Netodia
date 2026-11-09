# 最终提交的验证记录

本目录保留整合上游后的独立证据，不覆盖父目录中此前基线的构建和原生输出。

- 目标上游：`d08a2d3584c59a87ba899fb6330c0910590579e3`。
- 代码提交：`fdd2bc728ecd37ddb6b962fc59a3c70089309f22`。
- 代码分支：`codex/windows-smtc-metadata`。
- `source.patch` 是该上游到代码提交的完整差异，仅包含五个 SMTC 源码/测试文件。
- 这五个文件与此前审核版本逐字节相同；上游新增 Windows 任务栏代码由基线继承。
- 原先的私人邮箱提交未进入新分支新增的提交历史。新提交的作者与提交者均使用账户的 GitHub noreply 地址。

`source-capture.json` 记录完整 Git tree、补丁哈希、隔离应用结果，以及构建输入清单。`build-capture.json` 绑定实际成功构建及二进制，`checks.json` 保留完整 workspace 测试、Clippy、格式和构建的实际执行摘要。

最终结果：3530 条 workspace 测试通过，0 失败、0 忽略、0 过滤；Clippy、格式和构建均成功。坏封面矩阵六个检查点及真实 CDN 封面两个检查点通过，两个原生结果绑定同一最终二进制。`bad_cover.cleanup.json` 和 `remote_cover.cleanup.json` 记录测试数据副本已清理，原有安装实例保持运行。

`bad_cover-attempt1/` 保留最终构建首轮坏封面矩阵的暂停超时：恢复、播放和切歌元数据断言已通过，但首次观察 B 的元数据/Playing 后即发送 Pause，未先确认 B 的播放进度；SMTC 接受命令，却未在时限内观察到 Paused。第二轮保留相同字段和状态断言，增加“B 进度实际前进超过 1000 ms”的普通播放前置条件后，六检查点全部通过，没有修改业务源码或放宽暂停断言。

首轮失败的因果归属未确认。源码中，`state/transport.rs` 在异步切歌加载前可发布新的曲目状态；`ui/shell/event_sink.rs:22` 对加载期间的 Pause 先走 `cancel_queue_track_loading()`，而 `cloud_playback.rs:1042` 在异步加载返回后才清除 pending 标记。这是有依据的加载时序解释，相关代码未在本补丁中改动；本次没有对加载期间快速连按做额外测试，也没有将该解释写成已确认根因或证明它不受补丁时序影响。

`test-attempt1.json` 保留第一次 workspace 编译的 E0786 / Windows os error 1455 记录；最终单任务执行成功结果在 `checks.json`。父目录 `remote/attempt1/` 则属于此前基线的 WinRT 读取脚本失败，不能与本轮暂停超时混为一类。

原生验收复用已执行验证的脚本，但传入本目录的新构建清单，结果也写入本目录。先完成本机构建并核对新构建清单，再从仓库根目录分别运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File review-materials/windows-smtc/final/run_native.ps1 -Case bad_cover
powershell.exe -NoProfile -ExecutionPolicy Bypass -File review-materials/windows-smtc/final/run_native.ps1 -Case remote_cover
```

输入契约、静音共享输出、独立数据副本和清理方式与父目录说明相同。真实队列、数据库、歌词、日志原文及封面内容不进入导出材料。

本目录的 `verify_final.py` 仅检查文件、哈希和所记录结果的一致性，不构成第三方执行公证。完整文字/清空发布失败未在原生验收中触发；五秒重试间隔也不是自动唤醒计时器。
