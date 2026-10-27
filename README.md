# win-bom

个人 Windows 软件清单，用于在新电脑或干净系统上安装常用软件。

只收录长期使用的软件；配置、账户、许可证、驱动、系统组件、硬件厂商工具和应用运行时单独管理。

## 规则

- GUI 软件默认由 WinGet 管理。
- 独立的 CLI 软件默认由 Scoop 管理。
- 随主程序提供的 CLI 跟随主程序，例如 Docker Desktop 的 `docker` 和 VS Code 的 `code`。
- 同一个软件只在一个清单中出现；Scoop 的 bucket 和 WinGet 的 source 都是软件身份的一部分。
- 默认使用包管理器当前可提供的版本，不在清单中锁定一般软件版本。
- 从清单删除软件只表示以后不再安装，不会触发卸载。

Scoop 还管理以下软件：

| 软件 | 原因 |
| --- | --- |
| `7zip` | Scoop 解压流程的常用依赖 |
| `openhardwaremonitor` / `ds4windows` | WinGet 无对应精确包；DS4Windows 使用 schmaldeo 分支 |
| Fira Code / Maple Mono Nerd Fonts | 由 `nerd-fonts` bucket 提供 |
| `zlocation` | PowerShell 环境扩展 |
| `ddns-go` | `docket` bucket 提供的后台工具 |
| `Fanhuaji` / `FontLoaderSub` / `foobox-cn` | WinGet 无对应精确包，使用 `docket` 中的工具和定制发行版 |

`versions` bucket 提供 `ffmpeg-yt-dlp-nightly`。各 bucket 的地址见 `scoop.json`。

WinGet 使用 `winget` 和 `msstore` 两个 source；火绒安全软件、UU 加速器和 WeGame 使用 `msstore`。

## 文件

| 文件 | 作用 |
| --- | --- |
| `winget.json` | WinGet 原生导出结构；只维护人工确认的包 ID 和 source |
| `scoop.json` | Scoopfile 兼容结构；只维护 app、bucket 和 bucket source |
| `bootstrap.ps1` | 校验清单，准备包管理器，逐个安装并汇总失败项 |

## 使用

要求 Windows 10/11、可用的 App Installer/WinGet、网络连接，以及按需确认个别安装器的 UAC 提示。请在普通用户终端运行，不要用管理员终端启动整个流程；Scoop 不应以管理员身份安装。

从 Git Bash：

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File ./bootstrap.ps1
```

没有 PowerShell 7 时，可从 PowerShell 或 Git Bash 使用 Windows PowerShell：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1
```

缺少 Scoop 时，脚本会执行官方 `https://get.scoop.sh` 用户级安装器。安装阶段遵循各包管理器的幂等判断；已有软件不会因为重复运行而升级。只要有一项失败，脚本最后会列出失败项并返回非零退出码。

脚本只安装清单中的软件，不迁移已有安装的来源，也不执行卸载。代理、Shell、字体映射和 WSL 内部环境需单独配置。

## 维护

新增 GUI 软件时，确认包 ID 及其 source（`winget` 或 `msstore`）：

```powershell
winget search --id <package-id> --exact --source <source>
```

然后把 `PackageIdentifier` 加入 `winget.json`。新增 CLI 时，先确认 Scoop 包及其 bucket：

```powershell
scoop info <app>
```

如果它来自新 bucket，同时把 bucket 名称和固定 Git source 加入 `scoop.json`，再添加 app。

`winget export` 和 `scoop export` 可用于盘点，只将确认需要的软件增量加入清单。

修改后检查 JSON 可解析、包 ID 能在声明来源中找到；完整恢复可在干净虚拟机或新用户环境验证。
