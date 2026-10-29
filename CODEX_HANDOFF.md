# Textream TA：Codex 接手说明

交接日期：2026-10-28（America/Los_Angeles）。用户已试用，并表示当前版本基本可用。请从现有完整应用继续修改。

## 先取得正确版本

- 仓库：<https://github.com/George121380/textream>
- 工作分支：`codex/zoom-live-notch`。**直接克隆默认 master 会拿到较旧版本。**
- 固定交接版本：`ta-handoff-2026-10-28`，对应的 Release 提供完整交接包和可运行应用。
- 当前可执行文件的源码提交：`8ff2e52db39f95453d2c35bd5f75921f133f2ae4`。
- 完整构建及 44 项回归检查：<https://github.com/George121380/textream/actions/runs/40820924263>。
- 交接标签在该提交上补充文档和打包工具；应用源码与上述已构建提交一致。包内 `BUILD_MANIFEST.json` 记录精确版本及校验值。

```sh
git clone --branch codex/zoom-live-notch https://github.com/George121380/textream.git
cd textream
```

复现固定版本时执行 `git checkout ta-handoff-2026-10-28`，继续开发前创建自己的分支。若收到的是交接 ZIP，进入其中的 `source/`；它是源码快照，不含 `.git` 和凭据，联网后建议克隆仓库。

## 用户实际要做什么

用户在 Zoom 中听学生提问，希望快速得到可以直接照念的英文答复。流程是：

1. ScreenCaptureKit 读取电脑播放的会议声音。
2. Apple Speech 转成问题文本；默认英文识别。
3. 停顿约 1.8 秒后，Responses API 调用 `gpt-6.1-terra`，使用 `reasoning.effort: low`。
4. 生成 4–6 个简短英文句子，流式显示在 TA Assistant。
5. 成功完成的回答自动进入 Textream **原版刘海字幕**，继续听取下一道问题。

用户自己的麦克风不接入 TA 转写。戴耳机不妨碍捕获播放声音。捕获范围目前是所有系统播放声音，并非仅 Zoom。

## 已接受的设置与操作

- 默认模型保持 GPT-6.1 Terra；回答语言 English。
- 刘海宽度为 **750**，设置中的上限已从 500 放宽到 900。750 是这台机器的偏好，**新装应用仍需在 Appearance → Width 手动设为 750**。
- 原版悬浮层使用 pinned + Classic 自动滚动，避免启动第二个麦克风语音识别器。
- `Control + Option + Command + A` 打开答疑窗口；应用启动时用 Carbon `RegisterEventHotKey` 注册全局组合键。旧的 Command-Shift-A 与 Zoom 静音冲突，已替换。
- 开启 `Enable TA assistant`、`Auto reply after a pause`、`Show completed replies in notch automatically` 后使用。
- `Read in prompter` 可重新显示已有回答；`Pause audio` 暂停收音；`New student` 清空会话上下文。
- 关闭 TA Assistant 会停止收音和请求并清空对话；重启应用后必须重新启用。笔记仅在进程内保存。
- `handoff/recommended-settings.json` 是无密钥的设置清单，不会自动导入到用户的电脑。

## 已验证到什么程度

| 项目 | 证据与边界 |
| --- | --- |
| 完整 macOS 应用 | Xcode 26.3 云端编译成功，包含 arm64、x86_64；Intel 仅构建验证，没有真机测试 |
| 回归检查 | 44 项通过，使用 mock，不访问网络、Keychain 或音频 |
| 本机 | macOS 15.7.3、Apple Silicon；没有升级本机 Xcode 14.1 |
| 真实 API | 已保存的 Keychain 密钥可用；Terra 返回英文回答 |
| 收音与自动触发 | 合成英文音频的完整链路已通过；随后在真实 Zoom 试用中观察到转写和英文答复 |
| 速度 | 实际试用显示过 1.8、2.0 秒生成时间；这是生成阶段用时，不含转写和停顿，不是性能保证 |
| 刘海 | 完整应用原版悬浮层已启用；用户在试用中要求加宽，最终本机设为 750 |
| 新快捷键 | 新组合键在 Textream 内打开助手已验证；系统日志确认全局注册成功。自动化工具向 Zoom 发键未确认全局唤起，仍需用物理键盘在 Zoom 前台复核 |
| 更新后状态 | 最新快捷键版已启动，重新登记音频权限后显示 Listening to meeting audio |

尚未做完整长会话、中文转写、所有音频设备切换、多显示器和全屏 Zoom 回归。不要把上述有限试用写成所有场景通过。

## 文件地图

- `Textream/Textream/TAMeetingCapture.swift`：系统音频、Apple Speech、约 50 秒的识别任务轮换。
- `Textream/Textream/TAResponseClient.swift`：Keychain、HTTPS Responses 请求、SSE、模型参数与口头答复提示词。
- `Textream/Textream/TAAssistantModel.swift`：开关、停顿触发、取消和过期结果保护、最近三轮上下文、成功回答回调。
- `Textream/Textream/TAAssistantView.swift`：答疑面板、Setup、自动刘海开关。
- `Textream/Textream/TextreamApp.swift`：应用入口、菜单、全局快捷键，以及 `openTAAssistant()` 内的原版刘海连接。
- `Textream/Textream/NotchSettings.swift`、`NotchOverlayController.swift`：原版外观、宽度和阅读行为。
- `TARegressionTests.swift`：**CI 使用的** 44 项检查。不要误用其他目录中的旧副本。
- `.github/workflows/ta-checks.yml`：完整通用架构构建及测试。
- `tests/TAIntegrationHarness.swift`：旧工具链可构建的独立测试壳，有自己的简化刘海。它会在阅读时暂停音频，**不能替代完整应用作为交付物**。
- `scripts/package-ta-handoff.py`：用跟踪中的源码和已验证 `.app` 重新生成交接包。

## 不升级本机 Xcode 的构建方法

用户不希望升级 Xcode，也不需要登录 Apple 账号。完整项目采用较新的 Xcode 工程格式，使用已有的 GitHub Actions：

1. 推送你的工作分支。
2. 打开 Actions → TA Assistant checks → Run workflow，选择正确分支；若 `gh` 已授权，可运行：

```sh
gh workflow run ta-checks.yml --repo George121380/textream --ref YOUR_BRANCH
gh run list --repo George121380/textream --workflow ta-checks.yml --branch YOUR_BRANCH
gh run watch RUN_ID --repo George121380/textream --exit-status
gh run download RUN_ID --repo George121380/textream --name Textream-TA-unsigned --dir build/artifacts
```

不要为了这个交接版推送 `v*` 标签：另一个上游 release 工作流会修改 master，并要求开发者签名凭据。此交接版使用 `ta-handoff-*` 标签。

工作流只对 master 的相关 push、相关 PR 和手动运行触发；普通功能分支 push 不会自动构建。必须按实际提交检查成功状态。Actions 附件只保留七天；交接 Release 附件没有这个七天过期限制。

本机仅验证 TA 模块时可用：

```sh
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  Textream/Textream/TA*.swift TARegressionTests.swift -o /tmp/textream-ta-tests
/tmp/textream-ta-tests
```

完整项目的等价云端构建命令见工作流。除非用户另有要求，不改 iOS 项目。

## 安装与权限：最容易卡住的地方

Release 中的 `Textream-TA-macOS-universal.zip` 是已进行本机 ad-hoc 签名的完整应用，不是 Apple Developer ID 签名或公证的正式发行版。解压后放到稳定位置，例如 `~/Applications/Textream.app`。本次用户机器使用的就是该位置。API key 和本机偏好不在应用包内。

在其他 Mac 上，系统可能要求在 Privacy & Security 中确认打开此已知来源的测试应用。不要关闭 Gatekeeper、SIP，或批量删除安全属性。

每次重新编译并替换 ad-hoc 签名的应用，旧 TCC 权限可能绑定旧二进制，即使开关显示 on 也无法录音。**只开关 Screen & System Audio Recording 曾无法解决**。验证过的恢复方法：

1. System Settings → Privacy & Security → Screen & System Audio Recording。
2. 选中 **Textream** 那一行，移除失效条目；不要动其他应用。
3. 按 `+`，选择实际安装路径下的新 `Textream.app`。
4. 选择 Quit & Reopen；重新打开助手并启用，确认状态为 Listening to meeting audio。
5. 如仍失败，再检查 Speech Recognition。系统日志中出现 `Failed to match existing code requirement` 表示仍是旧二进制授权问题。

CI 的原始 unsigned ZIP 若需自行本机签名：

```sh
# 仅清理 Finder 元数据；保留 quarantine 等安全属性。
xattr -rd com.apple.FinderInfo /path/to/Textream.app 2>/dev/null || true
codesign --force --sign - --entitlements Textream/Textream/Textream.entitlements /path/to/Textream.app
codesign --verify --deep --strict /path/to/Textream.app
```

复制到目标路径后再验证。这个工作区的文件提供程序可能在复制时重新添加 FinderInfo，导致验证报资源元数据错误。

## 下一位 Codex 优先检查什么

1. 在 Zoom 前台用物理键盘复核全局快捷键；也验证已有助手窗口的前置行为。
2. 做一次连续两道真实问题 → 英文回复 → 刘海的完整测试，观察下一题是否覆盖正在朗读的内容。
3. 现在每次停顿都会触发回答，闲聊、片段和误识别也可能触发付费请求；需要更好的问题边界或显式手动模式。
4. 只有问题和三轮对话，不知道用户个人研究项目。需要此类回答时，应让用户提供事实背景；不要编造个人经历。
5. 课程笔记目前只在内存里；长期保存、课程配置和更好提示词属于可继续开发的方向。
6. 后续可改进低延迟流式刘海显示、滚动速度、回答排队、收音错误详情和稳定签名。当前仅在完整成功后打开刘海，避免展示失败流的残缺答案。

## 凭据与发布边界

API key 位于 macOS Keychain，service 为 `textream.ta.openai`、account 为 `api-key`。通过应用读取和使用，不打印、不导出、不打包。交接包只含版本控制中的源码、说明、公共设置清单和应用文件，不包含本机凭据、会议内容或偏好数据库。

在公共仓库的 issue、commit、Release 和日志里不要粘贴真实会议转写或个人研究资料。发布前检查源码提交与构建来源，生成 SHA-256 清单；不要上传整个本机工作目录。

## 重新打包

在干净、已提交的工作树中运行；脚本会核对应用源码与指定二进制来源提交一致，并检查完整应用签名和双架构。

```sh
python3 scripts/package-ta-handoff.py \
  --app /path/to/Textream.app \
  --binary-commit 8ff2e52db39f95453d2c35bd5f75921f133f2ae4 \
  --ci-url https://github.com/George121380/textream/actions/runs/40820924263 \
  --output dist/handoff
```

修改应用后必须换成新构建的提交和 CI URL。输出包括完整交接 ZIP、独立应用 ZIP、源码 ZIP、构建清单和 SHA-256 清单。先验证解包和签名，再将这些明确选定的附件上传到新的 Release。
