#include "wns_channel.h"

#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.PushNotifications.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>

#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <utility>

namespace hinata {

namespace {

using flutter::EncodableValue;
using flutter::MethodResult;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationChannel;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationChannelStatus;
using winrt::Microsoft::Windows::PushNotifications::PushNotificationManager;

constexpr char kChannelName[] = "hinata/wns";

// Entra "Managed application in local directory" object id of the app
// registration Partner Center's product is mapped to. Not a secret — it is the
// app's public identity, and WNS refuses any other. Must stay in sync with the
// PFN mapping filed with Microsoft (release/WINDOWS_PUSH_PFN_MAPPING.md).
constexpr wchar_t kRemoteId[] = L"33fa840e-5c3b-4cc0-8308-227acbecdf0d";

// Custom message used to hop a completed WinRT operation back onto the platform
// thread. WM_APP is the first id reserved for application use.
constexpr UINT kWmWnsChannelReady = WM_APP + 0x51;

struct PendingReply {
  std::unique_ptr<MethodResult<EncodableValue>> result;
  std::string uri;
};

// Custom message used to deliver a notification's deep link on the platform
// thread, for the same reason as the channel replies above.
constexpr UINT kWmDeepLink = WM_APP + 0x52;

std::mutex g_mutex;
std::queue<PendingReply> g_ready;
HWND g_window = nullptr;
bool g_registered = false;
bool g_notifications_registered = false;
// True when a notification click started this process. The window can only be
// raised once it actually exists and Flutter has shown it, which is well after
// the activation is consumed.
bool g_launched_from_notification = false;

// The deep link of a notification the user clicked. Buffered because a click
// can *launch* the app: the event then fires long before Dart has a handler,
// so the link is kept until Dart asks for it (getInitialDeepLink), mirroring
// how the FCM path consumes its initial message.
std::mutex g_link_mutex;
std::string g_pending_link;
std::shared_ptr<flutter::MethodChannel<EncodableValue>> g_channel;

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  int size = ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                   static_cast<int>(value.size()), nullptr, 0,
                                   nullptr, nullptr);
  if (size <= 0) return {};
  std::string out(size, '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                        static_cast<int>(value.size()), out.data(), size,
                        nullptr, nullptr);
  return out;
}

std::string ToUtf8(const winrt::hstring& value) {
  return ToUtf8(std::wstring(value.c_str(), value.size()));
}

void Enqueue(std::unique_ptr<MethodResult<EncodableValue>> result,
             std::string uri) {
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_ready.push(PendingReply{std::move(result), std::move(uri)});
  }
  if (g_window) ::PostMessage(g_window, kWmWnsChannelReady, 0, 0);
}

// A notification click that *starts* the app activates it as a COM server, so
// Windows does not bring the window forward the way a normal launch does — the
// user is left looking at whatever was on screen. Foreground rights belong to
// the process the user just interacted with, so this has to be done by hand.
void BringToForeground(HWND window) {
  if (!window) return;
  ::ShowWindow(window, ::IsIconic(window) ? SW_RESTORE : SW_SHOW);

  // SetForegroundWindow is refused unless the calling thread already owns the
  // foreground. Borrowing the current foreground thread's input queue for the
  // call is the long-standing way around that.
  HWND foreground = ::GetForegroundWindow();
  DWORD other = ::GetWindowThreadProcessId(foreground, nullptr);
  DWORD self = ::GetCurrentThreadId();
  bool attached = other && other != self &&
                  ::AttachThreadInput(other, self, TRUE);
  ::SetForegroundWindow(window);
  ::SetActiveWindow(window);
  if (attached) ::AttachThreadInput(other, self, FALSE);

  // Even with the input queue attached the request can be refused — a
  // COM-activated process has no foreground rights of its own. Briefly making
  // the window topmost forces it in front, then the flag is dropped again so it
  // behaves like a normal window afterwards.
  if (::GetForegroundWindow() != window) {
    constexpr UINT kFlags = SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW;
    ::SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0, kFlags);
    ::SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0, kFlags);
    ::SetForegroundWindow(window);
  }
}

// Called from the AppNotifications callback, which runs off the platform
// thread — the link is parked and a message posted, exactly like the channel
// replies.
void OnNotificationInvoked(std::string argument) {
  if (argument.empty()) return;
  {
    std::lock_guard<std::mutex> lock(g_link_mutex);
    g_pending_link = std::move(argument);
  }
  if (g_window) ::PostMessage(g_window, kWmDeepLink, 0, 0);
}

void RegisterNotificationActivation() {
  if (g_notifications_registered) return;
  try {
    using winrt::Microsoft::Windows::AppNotifications::AppNotificationManager;
    auto manager = AppNotificationManager::Default();
    // The deep link travels in the notification's `launch` attribute, which
    // surfaces here as Argument() — not in Arguments(), which parses it as
    // key=value pairs and would yield the whole path as a key.
    manager.NotificationInvoked([](auto const&, auto const& args) {
      std::string arg = ToUtf8(args.Argument());
      OnNotificationInvoked(std::move(arg));
    });
    // Must come after the handler is attached, otherwise a cold-start
    // activation is delivered before anyone is listening.
    manager.Register();
    g_notifications_registered = true;
  } catch (...) {
    // Unpackaged or runtime-less build: clicking a toast just opens the app.
  }
}

void RequestChannel(std::unique_ptr<MethodResult<EncodableValue>> result) {
  auto shared = std::make_shared<std::unique_ptr<MethodResult<EncodableValue>>>(
      std::move(result));
  try {
    if (!PushNotificationManager::IsSupported()) {
      // No push on this machine/build — the Dart side reads null as "not
      // available here" and simply registers no device.
      if (*shared) Enqueue(std::move(*shared), std::string());
      return;
    }
    auto operation =
        PushNotificationManager::Default().CreateChannelAsync(winrt::guid(kRemoteId));
    operation.Completed([shared](auto const& op, auto /*status*/) {
      std::string uri;
      try {
        auto result = op.GetResults();
        if (result.Status() == PushNotificationChannelStatus::CompletedSuccess) {
          PushNotificationChannel channel = result.Channel();
          uri = ToUtf8(channel.Uri().ToString());
        }
      } catch (...) {
        // Reported to Dart as null; never worth crashing the app over.
      }
      if (*shared) Enqueue(std::move(*shared), std::move(uri));
    });
  } catch (...) {
    // Thrown when the runtime is missing or the process has no package
    // identity (a plain `flutter run`). Expected, not an error.
    if (*shared) Enqueue(std::move(*shared), std::string());
  }
}

}  // namespace

// A cold-start click does NOT arrive through NotificationInvoked — measured:
// the process is COM-activated with `----AppNotificationActivated: -Embedding`,
// Register() succeeds first thing, and the event still never fires. The payload
// of the activation that *started* the process sits in the activated-event args
// instead, and is only readable after Register() (documented ordering).
void ConsumeLaunchActivation() {
  try {
    using winrt::Microsoft::Windows::AppLifecycle::AppInstance;
    using winrt::Microsoft::Windows::AppLifecycle::ExtendedActivationKind;
    using winrt::Microsoft::Windows::AppNotifications::
        AppNotificationActivatedEventArgs;

    auto activated = AppInstance::GetCurrent().GetActivatedEventArgs();
    if (activated.Kind() != ExtendedActivationKind::AppNotification) return;

    auto args = activated.Data().as<AppNotificationActivatedEventArgs>();
    std::string argument = ToUtf8(args.Argument());
    g_launched_from_notification = true;
    OnNotificationInvoked(std::move(argument));
  } catch (...) {
  }
}

void InitNotifications() {
  // Registering the app with the push platform is what allows WNS to activate
  // it (through the COM server declared in the package manifest) when a
  // notification arrives while the app is closed. Guarded: an unpackaged or
  // runtime-less build must still start normally.
  if (!g_registered) {
    try {
      if (PushNotificationManager::IsSupported()) {
        PushNotificationManager::Default().Register();
        g_registered = true;
      }
    } catch (...) {
    }
  }
  RegisterNotificationActivation();
  // Strictly after Register(), per the documented ordering.
  ConsumeLaunchActivation();
}

void RegisterWnsChannel(flutter::FlutterEngine* engine, HWND window) {
  if (engine == nullptr) return;
  g_window = window;

  auto channel = std::make_shared<flutter::MethodChannel<EncodableValue>>(
      engine->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name() == "getChannelUri") {
          RequestChannel(std::move(result));
          return;
        }
        if (call.method_name() == "getInitialDeepLink") {
          // Drains the buffer: a click that launched the app parks its link
          // here before Dart is ready to receive it.
          std::string link;
          {
            std::lock_guard<std::mutex> lock(g_link_mutex);
            link.swap(g_pending_link);
          }
          if (link.empty()) {
            result->Success(EncodableValue());
          } else {
            result->Success(EncodableValue(link));
          }
          return;
        }
        result->NotImplemented();
      });

  // Keep the channel alive for the process lifetime; the runner owns exactly
  // one engine and tears down at exit.
  g_channel = channel;

  // An activation that arrived before the window existed (the cold-start case,
  // registered from wWinMain) parked its link without being able to post —
  // flush it now that there is somewhere to post to.
  bool pending = false;
  {
    std::lock_guard<std::mutex> lock(g_link_mutex);
    pending = !g_pending_link.empty();
  }
  if (pending) {
    ::PostMessage(window, kWmDeepLink, 0, 0);
  }
}

void ForegroundIfLaunchedFromNotification(HWND window) {
  if (!g_launched_from_notification) return;
  g_launched_from_notification = false;
  BringToForeground(window);
}

bool HandleWnsChannelMessage(UINT message) {
  if (message == kWmDeepLink) {
    // Best-effort delivery to a *running* app. Deliberately does NOT clear the
    // buffer: on a cold start the activation fires while the engine is still
    // booting, so this call reaches no Dart handler and would silently drop
    // the link. Only getInitialDeepLink() drains the buffer, and Dart calls it
    // once during startup — so exactly one of the two paths delivers.
    std::string link;
    {
      std::lock_guard<std::mutex> lock(g_link_mutex);
      link = g_pending_link;
    }
    // The click was a user action on this app — show it, whether this process
    // was started by the click or was already running behind other windows.
    BringToForeground(g_window);
    if (!link.empty() && g_channel) {
      // Clear only once Dart has acknowledged. A handler-less engine replies
      // NotImplemented, which leaves the buffer for getInitialDeepLink — and
      // an acknowledged delivery stops that path from routing a second time.
      g_channel->InvokeMethod(
          "onDeepLink", std::make_unique<EncodableValue>(link),
          std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
              [](const EncodableValue*) {
                std::lock_guard<std::mutex> lock(g_link_mutex);
                g_pending_link.clear();
              },
              // Error and "no handler yet": leave the buffer alone so
              // getInitialDeepLink() still delivers the link.
              [](const std::string&, const std::string&,
                 const EncodableValue*) {},
              []() {}));
    }
    return true;
  }
  if (message != kWmWnsChannelReady) return false;
  for (;;) {
    PendingReply pending;
    {
      std::lock_guard<std::mutex> lock(g_mutex);
      if (g_ready.empty()) break;
      pending = std::move(g_ready.front());
      g_ready.pop();
    }
    if (!pending.result) continue;
    if (pending.uri.empty()) {
      pending.result->Success(EncodableValue());
    } else {
      pending.result->Success(EncodableValue(pending.uri));
    }
  }
  return true;
}

}  // namespace hinata
