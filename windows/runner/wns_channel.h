#ifndef RUNNER_WNS_CHANNEL_H_
#define RUNNER_WNS_CHANNEL_H_

#include <flutter/flutter_engine.h>
#include <windows.h>

// Windows Push Notification Services channel registration.
//
// Firebase Cloud Messaging has no Windows implementation, so the Windows build
// registers a WNS *channel URI* where the other platforms register an FCM
// token. This exposes that URI to Dart over the method channel
// "hinata/wns" with a single method:
//
//   getChannelUri() -> String?   (null when unavailable, never throws)
//
// Availability depends on the app running with package identity: WNS is only
// reachable from the MSIX build. A plain `flutter run` has no identity and gets
// null, which the Dart side treats exactly like "push not supported here".
namespace hinata {

// Registers with the push and notification platforms. MUST be called at the top
// of wWinMain, before any window or engine exists: when a notification click
// starts the app, Windows COM-activates it and delivers the activation almost
// immediately. Registering later — e.g. once the Flutter window is up — means
// the activation arrives before anyone is listening and is lost, which is
// exactly what a cold-start click looked like.
void InitNotifications();

// Registers the method channel on |engine|. |window| is the runner's top-level
// HWND, used to hop the asynchronous WinRT reply back onto the platform thread —
// flutter::MethodResult must not be completed from a background thread.
void RegisterWnsChannel(flutter::FlutterEngine* engine, HWND window);

// Raises the window when a notification click started this process. Call once
// the window is actually on screen — i.e. after Flutter's first frame; raising
// it earlier does nothing, because the runner keeps the window hidden until
// then and a COM-activated process gets no foreground rights of its own.
void ForegroundIfLaunchedFromNotification(HWND window);

// Forwarded from the runner's window procedure. Returns true when the message
// belonged to this module and was handled.
bool HandleWnsChannelMessage(UINT message);

}  // namespace hinata

#endif  // RUNNER_WNS_CHANNEL_H_
