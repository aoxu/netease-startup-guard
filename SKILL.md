---
name: netease-startup-guard
description: 在 Windows 为网易云音乐安装、检查或卸载登录后常驻的自启动守护，清除更新重建的已确认启动项，备份恢复配置并验证手动打开。用于网易云更新后恢复开机启动，不用于禁止程序运行或阻止更新。
---

# 网易云开机启动守护

## 范围与边界

这是写入后自动清理，不是写入前阻止。只匹配当前用户 Run 下一个明确名称和完整命令，保留原有 StartupApproved 状态；不锁整个注册表、不改 EXE 或更新器、不结束播放器进程。需要一个常驻的无控制台原生进程（目标电脑使用 .NET Framework 编译），登录任务以 Limited + Interactive 运行，不保存密码。未来更换启动机制、路径、参数或名称可能绕过；不要声称永久有效或零资源消耗。

普通问答只解释方案。用户要求安装、修复或卸载后才执行相应变更；已授权就继续，不额外增加确认。不要把历史电脑的账号、SID、路径或备份带到新电脑。

## 执行环境

不能仅凭 whoami 相同认定读到了桌面用户的注册表。曾出现命令执行环境与 Interactive 任务读到不同 HKCU 内容。安装、备份、模拟验证和卸载必须在同一个交互式用户环境执行。

使用 [scripts/Invoke-Interactive.ps1](scripts/Invoke-Interactive.ps1) 派发临时 Interactive/Limited 任务。独立确认目标用户 SID（例如 explorer.exe 的所有者 SID；多用户会话需明确目标），通过 ExpectedSid 传入；临时任务自动回收。不要从沙箱账户推断目标用户。权限不足时遵循宿主审批机制。

运行前读取 [references/workflow.md](references/workflow.md)。脚本兼容 Windows PowerShell 5.1；用 powershell.exe -NoProfile -ExecutionPolicy Bypass -File 执行，仅进程级策略，不更改系统策略。

## 流程

1. Inspect：检查实际用户的 Run 命令、Windows 禁用记录及 EXE 候选。核实文件为网易云；候选有歧义则查证，不能猜。检查本 Skill 或历史 NetEaseStartupGuard 任务，避免重复守护。
2. 确认范围：默认只覆盖 HKCU\Software\Microsoft\Windows\CurrentVersion\Run 中 cloudmusic。其他名称、HKLM、计划任务或启动文件夹不自动扩大范围；先定位并说明需要适配。
3. Install：指定已验证的 EXE 路径；有现存命令时需传逐字核实的 ExpectedCommand。安装至实际用户 LocalAppData 的独立目录，首次备份不覆盖；已有安装只报告状态。若 Execute 为 powershell.exe，按参考流程先卸载旧任务、核对恢复，再安装新版本，保留首次备份；不要误把只更新 Skill 当作更新了守护。
4. Verify：在同一 Interactive 环境模拟重写命令并等待清除，异常时恢复模拟前的值。检查任务 Running、心跳 Host=native-winexe、ConsoleHandle=0 及进程无主窗口。此动作短暂写入真实启动项，不能在即将注销或重启时执行。
5. 正常打开不带 autorun 参数的 EXE，观察主窗口。进程存在只能证明启动，不能证明播放、登录或更新功能；不要为测试播放音频、切歌或关闭原有窗口。
6. 提供稳定的 Uninstall-and-restore.cmd 路径。恢复的是安装前状态，可能原本已开启。严格卸载测试按参考流程执行，不能覆盖原备份，最终重新启用守护。
7. 汇报任务状态、模拟结果、手动打开证据、恢复测试结果，以及尚未验证的重启和真实更新；不要主动升级或重启来测试。

## 失败处理

安装失败回滚注册表并删除本次任务，保留日志和备份。未运行或验证失败不报完成；读取 guard.log、LastTaskResult 和 runner 输出。最多两轮有证据的修复，仍失败则停止变更、恢复原配置并报告。

可先运行 scripts/Test-Isolated.ps1：在独立测试注册表键和临时目录验证事件清理、匹配范围、二进制恢复和非匹配值保留，不触碰真实启动项或创建登录任务。
