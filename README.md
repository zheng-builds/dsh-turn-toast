# dsh-turn-notify

每轮任务结束时，在屏幕右下角弹一个提示卡片 —— 不依赖模型「记得去调用」，由宿主事件驱动。

## 行为

- 监听会话事件 `turn/end`（一轮结束）
- 取出这一轮最后一条助手回复的**第一句**，截断到 `maxChars`（默认 40 字）
- 用 PowerShell 画一个 WPF 卡片，`seconds` 秒后自动关闭，点击可提前关闭
- 弹窗同时播放提示音：默认用自带的 `assets/notify.wav`（三音上行琶音，合成、无版权），可换成自定义 WAV，或用 `sound: false` 关掉
- **全屏不弹**：`SHQueryUserNotificationState` 返回 2/3/4（忙碌、D3D 全屏、演示模式）时直接跳过
- `onlyWhenUnfocused`（默认开）：DSH 窗口在前台时不弹，你在看别的软件时才提醒
- 子会话（子代理）产生的 `turn/end` 不弹，避免一次任务弹多次

## 配置

改 `cordis.patch.yml` 里这个插件的 `config`：

```yaml
- insert:
    - id: turn-notify
      name: dsh-turn-notify
      config:
        enabled: true          # 总开关
        seconds: 6             # 停留秒数
        onlyWhenUnfocused: true # 仅当 DSH 不在前台时弹
        maxChars: 40           # 提示文字最大长度
        sound: true            # 是否播放提示音
        soundFile: ''          # 自定义 WAV 路径；留空用自带的 assets/notify.wav
```

## 依赖

- Windows 10/11
- `powershell.exe`（系统自带，Windows PowerShell 5.1 即可）
- 不需要 Python、Node 额外包、管理员权限

## 限制

- 仅支持 Windows（脚本用 WPF 与 Win32）
- 无边框窗口化的「假全屏」游戏可能不被系统判定为全屏，仍会弹窗
- 通知内容来自助手回复的首句，不做摘要

## 许可

MIT
