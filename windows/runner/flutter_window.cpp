#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

// Moves one file to the Recycle Bin. Windows asks before deleting a file
// for good, for example on a drive without a bin. Returns 0 on success, -1
// when the user declined, or the SHFileOperation error code.
int MoveToRecycleBin(HWND owner, const std::string& path) {
  std::wstring from = Utf8ToWide(path);
  from.push_back(L'\0');  // the list ends with two nulls
  SHFILEOPSTRUCTW op = {};
  op.hwnd = owner;
  op.wFunc = FO_DELETE;
  op.pFrom = from.c_str();
  op.fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT |
              FOF_NOERRORUI | FOF_WANTNUKEWARNING;
  int code = SHFileOperationW(&op);
  if (code == 0 && op.fAnyOperationsAborted) return -1;
  return code;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // See FileSystemService.trash in lib/data/services/.
  trash_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "io.github.infvyr.ftube/trash",
          &flutter::StandardMethodCodec::GetInstance());
  trash_channel_->SetMethodCallHandler(
      [hwnd = GetHandle()](const auto& call, auto result) {
        const auto* args =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() != "trash" || !args) {
          result->NotImplemented();
          return;
        }
        auto it = args->find(flutter::EncodableValue("paths"));
        const auto* paths =
            it == args->end()
                ? nullptr
                : std::get_if<flutter::EncodableList>(&it->second);
        if (!paths) {
          result->Error("bad_args", "paths is required");
          return;
        }
        flutter::EncodableList moved;
        flutter::EncodableValue error;
        for (const auto& value : *paths) {
          const auto* path = std::get_if<std::string>(&value);
          if (!path) continue;
          int code = MoveToRecycleBin(hwnd, *path);
          if (code == 0) {
            moved.push_back(flutter::EncodableValue(*path));
          } else if (code > 0 && error.IsNull()) {
            error = flutter::EncodableValue(
                *path + ": SHFileOperation error " + std::to_string(code));
          }
        }
        result->Success(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("moved"), flutter::EncodableValue(moved)},
            {flutter::EncodableValue("error"), error},
        }));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  trash_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
