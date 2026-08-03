#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "wns_channel.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Hinata: Splash NACH SetChildContent einblenden, damit sie in der Z-Order
  // über dem Flutter-View liegt.
  splash_ = HinataSplash::Present(GetHandle());

  // Hinata: WNS-Kanal für Push (FCM hat keine Windows-Implementierung).
  hinata::RegisterWnsChannel(flutter_controller_->engine(), GetHandle());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    // Only now is the window really on screen — a click that launched the app
    // can raise it from here, not earlier.
    hinata::ForegroundIfLaunchedFromNotification(GetHandle());
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  splash_ = nullptr;
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

  // Completed WNS channel requests hop back onto the platform thread through a
  // WM_APP message — flutter::MethodResult must not be completed off-thread.
  if (hinata::HandleWnsChannelMessage(message)) {
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_SIZE:
      // Win32Window skaliert nur child_content_; die Splash zieht selbst nach.
      if (splash_) {
        splash_->Resize(LOWORD(lparam), HIWORD(lparam));
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
