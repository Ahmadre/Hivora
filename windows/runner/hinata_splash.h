#ifndef RUNNER_HINATA_SPLASH_H_
#define RUNNER_HINATA_SPLASH_H_

#include <windows.h>

#include <memory>

// Hinata native Splash-Animation für Windows (Direct2D / DirectWrite).
// Gleiche Choreografie wie macOS (Core Animation), Android (AVD), iOS (UIKit)
// und Web (CSS): Sechseck zeichnen → Balken → Pop → Wortmarke → Ausblenden.
//
// Die Splash liegt als eigenes Kind-Fenster über dem Flutter-View und entfernt
// sich selbst, sobald die Choreografie durch ist.
class HinataSplash {
 public:
  // Blendet die Splash über |parent| ein. Gibt nullptr zurück, wenn Direct2D
  // nicht verfügbar ist — der Start der App darf daran nie scheitern.
  static std::unique_ptr<HinataSplash> Present(HWND parent);

  ~HinataSplash();

  // Auf die neue Client-Größe des Elternfensters ziehen.
  void Resize(int width, int height);

 private:
  HinataSplash() = default;

  HWND hwnd_ = nullptr;
};

#endif  // RUNNER_HINATA_SPLASH_H_
