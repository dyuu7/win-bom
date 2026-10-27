# win-bom

`win-bom` 是一份个人的轻量 Windows 软件物料清单（software bill of materials）。目标是在干净系统或新电脑上恢复同一组常用软件，而不是复制整套系统状态。

它只收录有意长期保留的软件，不包含私有数据、软件配置、驱动、系统组件，也不把安装时顺带出现的运行时和依赖当作个人选择。

## 规则

- GUI 软件默认由 WinGet 管理。
- 独立的 CLI 软件默认由 Scoop 管理。
- 随主程序提供的 CLI 跟随主程序，例如 Docker Desktop 的 `docker` 和 VS Code 的 `code`。
- 同一个软件只在一个清单中出现；Scoop 的 bucket 和 WinGet 的 source 都是软件身份的一部分。
- 默认使用包管理器当前可提供的版本，不在清单中锁定一般软件版本。
- 从清单删除软件只表示以后不再安装，不会触发卸载。卸载是独立、显式的操作。
- 驱动、系统功能、硬件厂商工具和应用运行时属于系统环境，不进入这份轻量清单。

WinGet 清单目前覆盖桌面应用，Scoop 清单覆盖独立 CLI、字体和以下例外：

| 软件 | 管理器 | 原因 |
| --- | --- | --- |
| `7zip` | Scoop | 同时是 Scoop 解压流程的常用依赖，不宜为分类而搬走 |
| `openhardwaremonitor` | Scoop | WinGet 没有对应的精确包 |
| Fira Code / Maple Mono Nerd Fonts | Scoop | 字体不属于 GUI 或 CLI，由 `nerd-fonts` bucket 统一提供 |
| `zlocation` | Scoop | PowerShell 环境扩展，不是普通桌面应用 |
| `ddns-go` | Scoop | 后台工具，来自项目使用的自定义 bucket |

## 文件

| 文件 | 作用 |
| --- | --- |
| `winget.json` | WinGet 原生导出结构；只维护人工确认的包 ID 和 source |
| `scoop.json` | Scoopfile 兼容结构；只维护 app、bucket 和 bucket source |
| `bootstrap.ps1` | 校验清单，准备包管理器，逐个安装并汇总失败项 |
| `README.md` | 边界、用法和维护流程 |

`scoop.json` 有意不记录安装时版本。它表达“选择哪个软件”，不表达“复刻某台机器的版本状态”。

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

这段流程不配置代理、Shell 主题、字体映射、应用账户或 WSL 发行版内的环境。它们属于下一步的配置问题，不应混入软件选择清单。

当前清单不是 `winget export` 或 `scoop export` 的全量镜像。现有机器上可能有软件仍由另一个管理器安装，例如 GUI 软件最初来自 Scoop，或 CLI 软件仍来自 WinGet。`bootstrap.ps1` 只补齐清单，不会迁移或卸载旧来源；确认新来源可用后，再单独执行显式清理。

## 维护

新增 GUI 软件时，先确认唯一、精确的 WinGet ID：

```powershell
winget search --id <publisher.package> --exact --source winget
```

然后把 `PackageIdentifier` 加入 `winget.json`。新增 CLI 时，先确认 Scoop 包及其 bucket：

```powershell
scoop info <app>
```

如果它来自新 bucket，同时把 bucket 名称和固定 Git source 加入 `scoop.json`，再添加 app。

`winget export` 和 `scoop export` 适合盘点当前机器，但导出结果会把历史工具、依赖和无意保留的软件一起带走。不要把完整导出直接覆盖人工清单；只把经过确认的条目迁入。

修改清单后，至少验证 JSON 可解析、包 ID 可在声明 source 中找到，并在干净虚拟机或新用户环境中完整运行一次。安装成功只证明软件已落地；账户登录、许可证、系统级前置条件和需要重启的安装器仍需人工处理。
