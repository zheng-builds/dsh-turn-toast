# 发版流程

本文件记录 `dsh-turn-toast` 的标准发版步骤，避免每次重新摸索。

## 0. 前提

- npm 账号 `z1628873342` 已登录（`npm whoami` 应返回该用户名）
- 账号已开启 2FA（安全密钥 / 身份验证器），**批准暂存版本时必须过 2FA**
- Git 凭据已缓存（推送不再提示输入密码）

## 1. 改代码并本地验证

```powershell
# 直接跑脚本看效果（不经过插件）
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "D:\Deepseek Projects\Projects\dsh-turn-notify\lib\notify.ps1" `
  -Message "测试文案" -Seconds 4 -Force -Log "$env:TEMP\dsh-turn-notify\test.log"
```

日志在 `%TEMP%\dsh-turn-notify\test.log`，会记录：通知状态、音效来源、卡片位置与尺寸。

## 2. 改版本号

语义化版本：

| 改动类型 | 版本位 | 例子 |
|---|---|---|
| 破坏性改动（配置项不兼容） | major | 0.1.1 → 1.0.0 |
| 新功能（新配置项、新行为） | minor | 0.1.1 → 0.2.0 |
| 修复 / 样式微调 | patch | 0.1.1 → 0.1.2 |

改 `package.json` 里的 `version`；**已发布的版本号不能复用**。

## 3. 提交并推送 GitHub

```powershell
cd "D:\Deepseek Projects\Projects\dsh-turn-notify"
git add -A
git commit -m "feat: 一句话说明改了什么"
git push
```

## 4. 暂存到 npm（不需要 2FA）

```powershell
npm stage publish . --tag latest
```

输出会给出一个 stage id，例如：

```
+ dsh-turn-toast@0.1.2 (staged with id <stage-id>)
```

## 5. 等待校验通过

```powershell
npm stage list dsh-turn-toast
```

`status` 会经历 `validating` → `staged`。
**只有变成 `staged` 才能批准**，`validating` 时点批准不会生效。

## 6. 批准（需要 2FA）

命令行：

```powershell
npm stage approve <stage-id>
```

会打印一个链接 → 浏览器打开 → 安全密钥确认。
或者到 https://www.npmjs.com/package/dsh-turn-toast 点 **Approve**。

## 7. 验证发布

```powershell
npm view dsh-turn-toast version          # 应返回新版本号
```

registry 直查：

```powershell
node -e "fetch('https://registry.npmjs.org/dsh-turn-toast?t='+Date.now()).then(r=>r.json()).then(j=>console.log(Object.keys(j.versions).join(', '), '| latest:', j['dist-tags'].latest))"
```

tarball 可下载性：

```powershell
node -e "fetch('https://registry.npmjs.org/dsh-turn-toast/-/dsh-turn-toast-<版本>.tgz?t='+Date.now(),{method:'HEAD'}).then(r=>console.log(r.status))"
```

## 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| tarball 裸链接 404、带 `?t=` 却是 200 | npm CDN 负缓存 | 等 15–60 分钟，无需操作 |
| `EOTP` / `409 needs 2FA` | 直接 `npm publish` 需要验证码 | 改用 `npm stage publish` + 批准流程 |
| 批准时提示 `validating` | 扫描还没完成 | 等 1–2 分钟再试 |
| `npm stage list` 为空 | 暂存已被批准或过期 | 查 registry 版本列表确认 |
| `npm error 404 name can only contain URL-friendly characters` | 同上，是通用 404 文案 | 不是包名问题 |

## 插件本地安装（开发时）

```powershell
# 安装本地目录（会建立链接，改代码后需重载插件）
# 通过 DSH 的 plugin_manager：「安装 bundle」→ 目标填项目绝对路径
```

重载插件：在 Plugins 页把 `dsh-turn-toast` 关掉再打开，或修改 `cordis.patch.yml` 后重新加载。

## 市场收录（仅首次）

1. Fork https://github.com/awesome-dsh-plugin/awesome-dsh-plugin
2. 在 fork 里新建 `data/plugins/zheng-builds__dsh-turn-toast.yml`：

```yaml
url: https://github.com/zheng-builds/dsh-turn-toast
name: zheng-builds/dsh-turn-toast
category: ui
description:
  en: Desktop toast with a soft chime when a DSH turn finishes, skipped in fullscreen apps.
  zh: 每轮任务结束时在屏幕右下角弹提示并播放提示音，全屏时不打扰。
```

3. 回到原仓库 → Contribute → Open pull request

要求：仓库带 `dsh-plugin` topic、仓库满 1 天、`package.json` 声明 `dsh.bundle`。
