# 安装与迁移流程

## 装入 Codex

将整个 netease-startup-guard 文件夹复制到目标电脑的 `$CODEX_HOME/skills/`；未设置 CODEX_HOME 时为 `%USERPROFILE%\.codex\skills\`。重新打开 Codex 会话后调用 `$netease-startup-guard`。若目标版本未发现技能，可直接让 Codex 读取文件夹里的 SKILL.md。Skill 文件夹本身不携带任何原电脑的注册表备份、日志、账户或 SID。

## 找到实际用户

从目标桌面 explorer.exe 进程的 GetOwnerSid 获取 SID，并核对所属会话。示例只用于读取：

```powershell
Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | ForEach-Object {
  $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid
  [pscustomobject]@{SessionId=$_.SessionId;Sid=$owner.Sid}
}
```

若多个不同用户会话，先明确目标。不要用沙箱 whoami 或硬编码用户名。登记任务需要的权限与守护本身的权限不同；守护始终 Limited，不安装系统服务、不要求保存密码。

## 执行动作

以下变量必须替换为当前电脑已查证的值。每次 JobDirectory 必须是新的、实际用户可访问的目录，建议当前工作区 work 下 GUID 目录。不要把用户提供路径或命令拼成可执行脚本，传结构化参数。

```powershell
& "$skill\scripts\Invoke-Interactive.ps1" -ExpectedSid $sid -Action Inspect -JobDirectory $newJobDirectory
```

Inspect 输出的 Run 命令是最可靠的路径线索之一；确认文件存在、产品信息符合网易云。候选路径列表只是线索，不能证明是实际安装位置。也检查其他自动启动入口，脚本不会拦截那些入口。

```powershell
& "$skill\scripts\Invoke-Interactive.ps1" -ExpectedSid $sid -Action Install -JobDirectory $newJobDirectory -ExePath $verifiedExe -ExpectedCommand $verifiedCommand
```

如果当前没有启动项，省略 ExpectedCommand 将生成 `"已验证的完整路径" --orpheus-startup=autorun`。这是针对已知启动方式的规则；必须以模拟测试和后续真实更新验证，不声称覆盖所有版本。现有命令不符合此格式时脚本拒绝安装，先查证再适配。

生产运行目录默认是**实际交互用户**的 `%LOCALAPPDATA%\Codex\NetEaseStartupGuard`，与下载的 Skill 文件夹独立。不要传入命令执行环境推导的 LocalAppData。状态输出会返回实际路径。任务名包含本机 SID。

安装时已有同名守护不会覆盖。若它还执行 powershell.exe，保存已核实的原配置参数，使用新 Skill 的 Uninstall 先卸载并验证恢复，再向同一 RuntimeDirectory 执行 Install 与 Verify；首次 backup.json 必须保留。安装成功前不能把升级报告为完成。发现旧 NetEaseStartupGuard 任务会拒绝叠加。迁移需先确认旧任务、备份与恢复策略，不能直接注销不明任务。

```powershell
& "$skill\scripts\Invoke-Interactive.ps1" -ExpectedSid $sid -Action Verify -JobDirectory $newJobDirectory
& "$skill\scripts\Invoke-Interactive.ps1" -ExpectedSid $sid -Action Status -JobDirectory $newJobDirectory
```

检查任务 Running、Execute 指向运行目录的 NetEaseStartupGuard.exe、最近 90 秒内心跳 Host=native-winexe / ConsoleHandle=0、进程无主窗口、Run 值缺失和模拟 PASS。心跳每分钟刷新一次，只证明进程存活；不代替模拟测试。守护无 UI，不影响普通 EXE 启动路径。用户要求手动打开验证时，用现有程序的正常入口打开并检查窗口；可以通过当前可用 computer-use 工具或用户观察确认。只看到进程时明确证据限制。

## 卸载及恢复测试

用户双击运行目录的 `Uninstall-and-restore.cmd` 即可。它按当前用户身份删除本 Skill 的任务，并恢复首次 backup.json 中两个 cloudmusic 值。不会删除运行目录或日志，不更改其他启动项。恢复可能使原本开启的自启动重新开启，报告实际备份状态。

Codex 用 Invoke-Interactive 的 Uninstall 动作获得同等效果。卸载会逐值核对存在性、类型和数据，包含二进制 StartupApproved。若用户要求实测卸载，执行 Uninstall，核对任务消失与恢复值，再用相同路径/命令 Install 和 Verify，最终确认 Running。重装保留首次备份，不把中间状态误作安装前配置。

## 失败与安全范围

- 实际用户未登录时临时 Interactive 任务可能无法运行；不要改成 SYSTEM 来绕过。
- 临时任务超时属于结果未知：检查结果目录、正式任务、配置与备份，再决定恢复或重试，不重复安装。
- `RegNotifyChangeKeyValue` 监听键被整体删除后需要重新绑定；当前守护会失败并由任务有限重试。不承诺瞬时拦截或对新启动入口有效。
- 已保存的 Command 必须是核实过的固定值；不根据外部写入自动扩大匹配，避免误伤其他程序或特殊手动启动命令。
- PowerShell 只做进程级 ExecutionPolicy Bypass，不改机器执行策略、ACL、安全软件、播放器文件或更新机制。
- 稳定目录权限使用用户默认权限；若电脑策略禁止该目录脚本执行，应报告具体阻塞，不能禁用安全控制。

## 本包验证与来源

运行 `scripts/Test-Isolated.ps1 -WorkDirectory <workspace/work>` 验证独立键的事件监听和恢复函数。脚本不创建登录任务、不调用网易云、不接触真实 Run；同时检查 EXE 的 Windows 子系统类型、控制台句柄和主窗口句柄。

Windows 注册表变更通知：[Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regnotifychangekeyvalue)。注册表权限作用于键：[Microsoft Learn](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights)。

隔离测试并不能证明所有电脑上都可安装，也不能证明播放器更新/音频播放功能；目标电脑必须按前述流程验收。

## 无窗口编译依赖

Build-Hosts.ps1 使用 Windows 自带的 .NET Framework x64 csc.exe，将 GuardHost.cs 和 WindowlessRunner.cs 编译为 /target:winexe。守护直接监听注册表，无 PowerShell 子进程；临时安装任务的入口用 CreateNoWindow 启动短时 PowerShell 工作。编译失败时停止并报告，不下载编译器、不禁用安全策略、不回退 -WindowStyle Hidden。不要把任务设置中的 Hidden 属性当作隐藏窗口的替代品。
