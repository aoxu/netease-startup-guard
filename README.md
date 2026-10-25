# 网易云音乐开机启动守护 · Codex Skill

针对网易云音乐 Windows 版更新后重新开启「开机自动运行」的情况，让 Codex 在电脑上安装一个登录后运行的守护：发现已确认的自启动项被重新写入时，自动清除它。

**守护只处理自启动项，不修改播放器文件、不结束网易云进程、不阻止更新程序运行。** 它不保证拦截所有未来版本；手动打开、真实更新和重启后的表现需要在目标电脑验证。

## 工作方式

```text
用户登录 Windows
    ↓
计划任务启动后台守护
    ↓
清理一次已确认的启动项，并监听注册表变化
    ↓
更新程序重新写入相同启动项 → 匹配名称与完整命令 → 清除该值
```

计划任务以当前用户的普通权限运行，不保存密码。守护常驻一个 Windows PowerShell 进程，通过注册表事件通知触发检查，每分钟刷新一次状态记录；不是每分钟轮询删除启动项。

当前支持的入口：

| 项目 | 范围 |
| --- | --- |
| 注册表位置 | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` |
| 值名称 | `cloudmusic` |
| 命令格式 | `"实际安装路径\cloudmusic.exe" --orpheus-startup=autorun` |
| 匹配方式 | 与安装时核实并保存的完整命令精确匹配 |
| 原有 Windows 禁用记录 | 保留并备份，卸载时恢复 |

实现依据：[微软注册表变更通知文档](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regnotifychangekeyvalue)。具体行为可查看 [Guard.ps1](scripts/Guard.ps1) 和 [Manage.ps1](scripts/Manage.ps1)。

## 在其他电脑安装

适用于具有 Windows PowerShell 5.1、计划任务功能及实际登录用户桌面的 Windows 环境。Codex 需要具备执行本地脚本、读取注册表及登记当前用户任务的权限。电脑管理策略可能限制这些操作；本 Skill 不绕过安全策略。

### 方式一：让 Codex 安装 Skill

把仓库地址发给目标电脑上的 Codex：

> 请将 https://github.com/aoxu/netease-startup-guard 安装为我的 Codex Skill。

安装 Skill 只是让 Codex 获得操作流程，**不会自动安装后台守护**。新开会话后，再发：

> 使用 $netease-startup-guard 配置网易云自启动守护，提供一键卸载恢复，并验证手动打开。

### 方式二：手动放入技能目录

下载或克隆仓库，将整个文件夹命名为 `netease-startup-guard`，放到：

```text
%USERPROFILE%\.codex\skills\netease-startup-guard\
```

如果配置了 `CODEX_HOME`，使用该目录下的 `skills` 文件夹。确保 `SKILL.md` 直接位于技能文件夹内，避免多套一层目录。新开 Codex 会话后使用上面的调用语句；若未发现 Skill，可让 Codex 直接读取本仓库的 [SKILL.md](SKILL.md)。

## 安装时 Codex 会做什么

1. 识别实际登录用户、网易云安装路径和已有启动入口。
2. 在同一个交互式用户环境中读取、备份和修改配置，避免沙箱账户或不同注册表视图造成误判。
3. 创建专属登录任务，并启动守护；检测到已有旧版守护时停止叠加安装。
4. 模拟写入启动项，验证自动清除且 Windows 禁用记录未改变。
5. 普通方式打开网易云，核对启动结果，并提供卸载入口。

运行文件默认保存在实际用户的：

```text
%LOCALAPPDATA%\Codex\NetEaseStartupGuard\
```

正式任务名为 `Codex-NetEaseStartupGuard-<用户SID>`。首次备份保存在 `backup.json`，不会随重复安装被覆盖。运行目录独立于 Skill 源码目录，使用期间不要删除运行目录。

## 检查、卸载和恢复

可直接对 Codex 说：

> 使用 $netease-startup-guard 检查守护是否运行，并模拟验证更新重写启动项。

或：

> 使用 $netease-startup-guard 卸载守护并恢复安装前的启动配置。

也可以双击运行目录中的 **`Uninstall-and-restore.cmd`**。它会停止并删除本 Skill 创建的任务，恢复原来的 `cloudmusic` 启动项与 Windows 禁用记录，保留备份和日志文件。

**恢复的是安装前状态，不是强制关闭自启动。** 如果安装前自启动处于开启状态，卸载恢复后也可能重新开启。不要使用其他电脑的 `backup.json`。

底层参数及验收流程见 [workflow.md](references/workflow.md)。通常应由 Codex 识别当前电脑信息后执行，不要直接照抄另一台电脑的账户、SID 或路径。

## 限制

- 这是「写入后清理」，存在短暂时间窗口。守护未运行时不能清理。
- 新版本如果更换名称、命令、安装路径或改用计划任务等入口，需要重新检查并调整规则。
- 不修改整个 `Run` 键权限，也不阻断播放器启动或更新；但不能据此宣称所有版本的兼容性已验证。
- 任务异常退出后最多按一分钟间隔重试三次；仍失败时需要诊断，不会无限重试。
- 不会自动重启电脑、升级网易云或播放音频来完成验收。

## 测试

在仓库根目录运行隔离测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Isolated.ps1 -WorkDirectory .\work\tests
```

它使用随机命名的测试注册表键，测试完成后清理该键，不写入真实 `Run`、不创建登录任务、不打开网易云。运行环境必须允许访问测试键。

当前已验证：

- 初始匹配项清理与连续变更事件处理。
- 非匹配命令和其他注册表值保留。
- 二进制配置与原本不存在的值恢复。
- 交互式任务派发及实际用户状态读取。

以上基于本项目本机隔离测试和检查，不代表已经覆盖所有 Windows 电脑。可移植版本仍需在每台目标电脑验收安装、卸载、手动打开、重启登录和下一次真实更新。

## 文件结构

```text
SKILL.md                       Codex 操作指引
agents/openai.yaml             Skill 展示信息
references/workflow.md         参数、迁移与验收说明
scripts/Common.ps1             注册表备份与恢复
scripts/Guard.ps1              事件监听守护
scripts/Manage.ps1             检查、安装、验证、卸载
scripts/Invoke-Interactive.ps1  交互式账户任务派发
scripts/Test-Isolated.ps1       隔离行为测试
```

`.gitignore` 排除本机备份、配置、日志、请求文件和测试输出。提交变更前仍应检查暂存区，不公开账户 SID、绝对用户路径或本机运行数据。
