#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$REPO_DIR/build/macos-apps"
FINAL_DIR="$BUILD_DIR/final"
TMP_DIR="$BUILD_DIR/tmp"
IDENTITY_DEFAULT='Developer ID Application: Chaojifeng (Xiamen) Network Technology Co., Ltd. (DYGN8HZFL9)'
IDENTITY="${CODESIGN_IDENTITY:-$IDENTITY_DEFAULT}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
TEAM_ID="${TEAM_ID:-DYGN8HZFL9}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

mkdir -p "$BUILD_DIR" "$FINAL_DIR" "$TMP_DIR"
rm -rf "$TMP_DIR"/* "$FINAL_DIR"/*

create_icns() {
  local src_png="$1"
  local out_icns="$2"
  local base
  base="$(mktemp -d "$TMP_DIR/iconset.XXXXXX")"
  local iconset="$base/AppIcon.iconset"
  mkdir -p "$iconset"

  sips -z 16 16     "$src_png" --out "$iconset/icon_16x16.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$src_png" --out "$iconset/icon_32x32.png" >/dev/null
  sips -z 64 64     "$src_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$src_png" --out "$iconset/icon_128x128.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$src_png" --out "$iconset/icon_256x256.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$src_png" --out "$iconset/icon_512x512.png" >/dev/null
  cp "$src_png" "$iconset/icon_512x512@2x.png"

  iconutil -c icns "$iconset" -o "$out_icns"
}

create_app() {
  local app_name="$1"
  local bundle_id="$2"
  local src_script="$3"
  local icon_png="$4"
  local launch_arg="${5:-}"
  local app_dir="$TMP_DIR/$app_name.app"
  local contents="$app_dir/Contents"
  local macos="$contents/MacOS"
  local resources="$contents/Resources"
  mkdir -p "$macos" "$resources"

  cp "$src_script" "$resources/installer.command"
  chmod 755 "$resources/installer.command"

  if [[ "$launch_arg" == "--app-gui" ]]; then
    local swift_src="$TMP_DIR/${bundle_id}.swift"
    cat > "$swift_src" <<'EOS'
import AppKit
import Foundation

final class InstallerApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var keyField: NSSecureTextField!
    private var reuseButton: NSButton!
    private var startButton: NSButton!
    private var closeButton: NSButton!
    private var useButton: NSButton!
    private var statusLabel: NSTextField!
    private var progress: NSProgressIndicator!
    private var textView: NSTextView!
    private var process: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenAI Codex 安装器"
        window.center()

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        let title = NSTextField(labelWithString: "OpenAI Codex CLI 一键安装")
        title.font = NSFont.boldSystemFont(ofSize: 20)
        title.frame = NSRect(x: 24, y: 512, width: 520, height: 28)
        content.addSubview(title)

        let desc = NSTextField(labelWithString: "输入 OpenAI API Key 后开始安装。安装器会检测 Node.js、安装 Codex CLI、写入配置并校验结果。")
        desc.frame = NSRect(x: 24, y: 482, width: 700, height: 22)
        content.addSubview(desc)

        let keyLabel = NSTextField(labelWithString: "OpenAI API Key")
        keyLabel.frame = NSRect(x: 24, y: 448, width: 160, height: 20)
        content.addSubview(keyLabel)

        keyField = NSSecureTextField(frame: NSRect(x: 24, y: 418, width: 520, height: 28))
        keyField.placeholderString = "sk-..."
        content.addSubview(keyField)

        reuseButton = NSButton(checkboxWithTitle: "复用已保存的 Key", target: nil, action: nil)
        reuseButton.frame = NSRect(x: 560, y: 418, width: 160, height: 28)
        reuseButton.isEnabled = hasSavedKey()
        reuseButton.state = reuseButton.isEnabled ? .on : .off
        content.addSubview(reuseButton)

        statusLabel = NSTextField(labelWithString: reuseButton.isEnabled ? "检测到已有配置，可直接复用或输入新 Key 覆盖。" : "等待输入 API Key。")
        statusLabel.frame = NSRect(x: 24, y: 386, width: 700, height: 22)
        content.addSubview(statusLabel)

        progress = NSProgressIndicator(frame: NSRect(x: 24, y: 360, width: 700, height: 16))
        progress.isIndeterminate = true
        progress.controlSize = .small
        content.addSubview(progress)

        let scrollView = NSScrollView(frame: NSRect(x: 24, y: 78, width: 700, height: 260))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        content.addSubview(scrollView)

        startButton = NSButton(title: "开始安装", target: self, action: #selector(startInstall))
        startButton.frame = NSRect(x: 24, y: 24, width: 110, height: 34)
        content.addSubview(startButton)

        closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.frame = NSRect(x: 146, y: 24, width: 90, height: 34)
        content.addSubview(closeButton)

        useButton = NSButton(title: "前往使用", target: self, action: #selector(openCodex))
        useButton.frame = NSRect(x: 248, y: 24, width: 110, height: 34)
        useButton.isEnabled = false
        content.addSubview(useButton)

        window.makeKeyAndOrderFront(nil)
    }

    private func hasSavedKey() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = object["OPENAI_API_KEY"] as? String else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func closeWindow() {
        if process?.isRunning == true {
            let alert = NSAlert()
            alert.messageText = "安装仍在进行"
            alert.informativeText = "请等待安装结束后再关闭窗口。"
            alert.addButton(withTitle: "知道了")
            alert.runModal()
            return
        }
        NSApp.terminate(nil)
    }

    @objc private func startInstall() {
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let reuseSaved = reuseButton.state == .on
        if key.isEmpty && !reuseSaved {
            showAlert(title: "请输入 OpenAI API Key", message: "如果已经安装过，也可以勾选复用已保存的 Key。", style: .warning)
            return
        }

        textView.string = ""
        statusLabel.stringValue = "正在安装，请不要关闭窗口..."
        startButton.isEnabled = false
        keyField.isEnabled = false
        reuseButton.isEnabled = false
        useButton.isEnabled = false
        progress.startAnimation(nil)
        appendLog("INFO\t准备开始安装...")

        let scriptURL = Bundle.main.resourceURL!.appendingPathComponent("installer.command")
        let task = Process()
        task.executableURL = scriptURL
        var args = ["--gui"]

        var keyFileURL: URL?
        if !key.isEmpty {
            keyFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("codex-installer-key-\(UUID().uuidString)")
            do {
                try key.write(to: keyFileURL!, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL!.path)
                args.append("--api-key-file=\(keyFileURL!.path)")
            } catch {
                showAlert(title: "无法创建临时文件", message: error.localizedDescription, style: .critical)
                resetControls()
                return
            }
        }
        if reuseSaved {
            args.append("--reuse-saved-key")
        }
        task.arguments = args

        let pipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendLog(text) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendLog(text) }
        }

        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.progress.stopAnimation(nil)
                self?.resetControls()
                try? keyFileURL.map { try FileManager.default.removeItem(at: $0) }
                if process.terminationStatus == 0 {
                    self?.statusLabel.stringValue = "安装完成，可以在终端输入 codex 使用。"
                    self?.useButton.isEnabled = true
                    self?.showAlert(title: "安装完成", message: "现在可以点击“前往使用”，安装器会在桌面目录打开终端并启动 Codex。", style: .informational)
                } else {
                    self?.statusLabel.stringValue = "安装失败。请查看日志并把错误信息发给支持同学。"
                    self?.useButton.isEnabled = false
                    self?.showAlert(title: "安装失败", message: "请查看窗口中的日志输出。", style: .critical)
                }
            }
        }

        do {
            process = task
            try task.run()
        } catch {
            resetControls()
            useButton.isEnabled = false
            showAlert(title: "无法启动安装器", message: error.localizedDescription, style: .critical)
        }
    }

    @objc private func openCodex() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let command = "#!/bin/zsh\n" +
            "export PATH=\"/usr/local/bin:/opt/homebrew/bin:$PATH\"\n" +
            "cd \(shellQuote(desktop.path))\n" +
            "exec codex\n"
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("openai-codex-launch-\(UUID().uuidString).command")
        do {
            try command.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            showAlert(title: "无法准备 Codex", message: error.localizedDescription, style: .critical)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Terminal", scriptURL.path]

        do {
            try task.run()
            statusLabel.stringValue = "已在桌面目录打开终端并运行 codex。"
        } catch {
            showAlert(title: "无法打开 Codex", message: error.localizedDescription, style: .critical)
        }
    }

    private func resetControls() {
        startButton.isEnabled = true
        keyField.isEnabled = true
        reuseButton.isEnabled = hasSavedKey()
    }

    private func appendLog(_ text: String) {
        textView.string += text
        textView.scrollToEndOfDocument(nil)
    }

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window)
    }

    private func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

let app = NSApplication.shared
let delegate = InstallerApp()
app.delegate = delegate
app.run()
EOS
    swiftc "$swift_src" -o "$macos/launcher"
  else
    cat > "$macos/launcher" <<'EOS'
#!/bin/bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_PATH="$APP_DIR/Resources/installer.command"
chmod 755 "$SCRIPT_PATH"
LAUNCH_ARG="__LAUNCH_ARG__"
if [[ -n "$LAUNCH_ARG" ]]; then
  "$SCRIPT_PATH" "$LAUNCH_ARG"
else
  open -a Terminal "$SCRIPT_PATH"
fi
EOS
    LAUNCH_ARG_VALUE="$launch_arg" perl -0pi -e 's/__LAUNCH_ARG__/$ENV{LAUNCH_ARG_VALUE}/g' "$macos/launcher"
  fi
  chmod 755 "$macos/launcher"

  create_icns "$icon_png" "$resources/AppIcon.icns"

  cat > "$contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$app_name</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$app_name</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

  /usr/libexec/PlistBuddy -c "Print" "$contents/Info.plist" >/dev/null
  echo "$app_dir"
}

sign_notarize_zip() {
  local app_dir="$1"
  local zip_name="$2"
  if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$FINAL_DIR/$zip_name"
    return
  fi
  codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$TMP_DIR/$zip_name"
  xcrun notarytool submit "$TMP_DIR/$zip_name" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$app_dir"
  spctl --assess --type execute -vv "$app_dir"
  ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$FINAL_DIR/$zip_name"
}

GLM_APP=$(create_app "智谱 Claude Code 安装器" "com.chaojifeng.glm-claude-installer" "$REPO_DIR/scripts/macos/install-glm-claude.command" "$REPO_DIR/assets/rendered/zai-logo.svg.png")
CODEX_APP=$(create_app "OpenAI Codex 安装器" "com.chaojifeng.openai-codex-installer" "$REPO_DIR/scripts/macos/install-openai-codex.command" "$REPO_DIR/assets/rendered/codex-color.png" "--app-gui")

sign_notarize_zip "$GLM_APP" "智谱-Claude-Code-安装器-macOS.zip"
sign_notarize_zip "$CODEX_APP" "OpenAI-Codex-安装器-macOS.zip"

echo "\nFinal artifacts:"
find "$FINAL_DIR" -maxdepth 1 -type f -name '*.zip' | sort
