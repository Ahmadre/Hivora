#include "hinata_splash.h"

#include <d2d1.h>
#include <d2d1helper.h>
#include <dwrite_3.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <string>

using Microsoft::WRL::ComPtr;

namespace {

// --- Choreografie (Sekunden) — identisch zu HinataSplashView.swift ----------
constexpr float kHexStart = 0.10f, kHexDuration = 0.62f;
constexpr float kBarStart = 0.50f, kBarDuration = 0.38f;
constexpr float kPopStart = 0.62f;
constexpr float kWordStart = 0.88f, kWordDuration = 0.55f;
constexpr float kFadeStart = 1.90f, kFadeDuration = 0.35f;
constexpr float kTotal = kFadeStart + kFadeDuration;

// Spring: damping 12, stiffness 220 (CASpringAnimation-Parameter von macOS)
constexpr float kSpringStiffness = 220.0f;
constexpr float kSpringDamping = 12.0f;

constexpr wchar_t kWindowClass[] = L"HinataSplashWindow";
constexpr UINT_PTR kTimerId = 1;
constexpr UINT kFrameIntervalMs = 16;  // ~60 fps

// Honey-Amber #D9A032 — Marke in beiden Themes
constexpr D2D1_COLOR_F kMarkColor = {0.851f, 0.627f, 0.196f, 1.0f};
constexpr D2D1_COLOR_F kBgDark = {0.075f, 0.067f, 0.098f, 1.0f};   // #131119
constexpr D2D1_COLOR_F kBgLight = {0.957f, 0.953f, 0.937f, 1.0f};  // #F4F3EF

// Cubic-Bezier-Easing wie in CSS/Core Animation (P0=(0,0), P3=(1,1)).
float CubicBezier(float x1, float y1, float x2, float y2, float t) {
  if (t <= 0.0f) return 0.0f;
  if (t >= 1.0f) return 1.0f;
  auto curve_x = [&](float u) {
    float v = 1.0f - u;
    return 3 * v * v * u * x1 + 3 * v * u * u * x2 + u * u * u;
  };
  auto curve_y = [&](float u) {
    float v = 1.0f - u;
    return 3 * v * v * u * y1 + 3 * v * u * u * y2 + u * u * u;
  };
  // Bisektion: robust und für 60 fps schnell genug (kein Ableitungs-Sonderfall).
  float lo = 0.0f, hi = 1.0f, u = t;
  for (int i = 0; i < 24; ++i) {
    u = 0.5f * (lo + hi);
    if (curve_x(u) < t) {
      lo = u;
    } else {
      hi = u;
    }
  }
  return curve_y(u);
}

// Unterdämpfter Feder-Verlauf 0→1 (analog CASpringAnimation).
float Spring(float t) {
  if (t <= 0.0f) return 0.0f;
  const float omega0 = std::sqrt(kSpringStiffness);
  const float zeta = kSpringDamping / (2.0f * omega0);
  if (zeta >= 1.0f) return 1.0f - std::exp(-omega0 * t) * (1.0f + omega0 * t);
  const float omega_d = omega0 * std::sqrt(1.0f - zeta * zeta);
  const float decay = std::exp(-zeta * omega0 * t);
  return 1.0f - decay * (std::cos(omega_d * t) +
                         (zeta * omega0 / omega_d) * std::sin(omega_d * t));
}

bool SystemUsesDarkTheme() {
  DWORD value = 1;  // Fallback: hell
  DWORD size = sizeof(value);
  if (RegGetValueW(HKEY_CURRENT_USER,
                   L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\"
                   L"Personalize",
                   L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &value,
                   &size) != ERROR_SUCCESS) {
    return false;
  }
  return value == 0;
}

// Sora liegt bereits als Flutter-Asset neben der exe — kein zweites Font-Copy
// im Runner nötig (macOS/iOS bündeln es, weil dort kein flutter_assets-Pfad
// zur Laufzeit erreichbar ist).
std::wstring SoraFontPath() {
  wchar_t exe_path[MAX_PATH];
  DWORD length = GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (length == 0 || length == MAX_PATH) return L"";
  std::wstring path(exe_path, length);
  size_t last_slash = path.find_last_of(L'\\');
  if (last_slash == std::wstring::npos) return L"";
  path.resize(last_slash);
  return path + L"\\data\\flutter_assets\\assets\\fonts\\Sora-Variable.ttf";
}

}  // namespace

// Gesamter Zeichen-/Animationszustand. Liegt am HWND (GWLP_USERDATA), damit die
// statische WndProc darauf zugreifen kann.
struct SplashState {
  ComPtr<ID2D1Factory> d2d_factory;
  ComPtr<ID2D1HwndRenderTarget> render_target;
  ComPtr<IDWriteFactory> dwrite_factory;
  ComPtr<IDWriteTextFormat> text_format;
  ComPtr<IDWriteFontCollection> font_collection;  // Sora, falls ladbar
  ComPtr<ID2D1PathGeometry> hex_geometry;
  ComPtr<ID2D1PathGeometry> bar_geometry;

  HinataSplash* owner = nullptr;  // wird benachrichtigt, wenn das Fenster geht
  LARGE_INTEGER start_ticks{};
  LARGE_INTEGER frequency{};
  float mark_size = 0.0f;   // Kantenlänge des Logo-Quadrats
  float hex_length = 0.0f;  // Pfadlängen für die Dash-basierte Stroke-Animation
  float bar_length = 0.0f;
  bool dark = false;
  bool geometry_valid = false;
};

namespace {

SplashState* StateOf(HWND hwnd) {
  return reinterpret_cast<SplashState*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
}

float ElapsedSeconds(const SplashState& state) {
  LARGE_INTEGER now;
  QueryPerformanceCounter(&now);
  return static_cast<float>(now.QuadPart - state.start_ticks.QuadPart) /
         static_cast<float>(state.frequency.QuadPart);
}

// Sechseck + Balken im 120-Einheiten-Designraum. Win32 zeichnet y nach unten,
// die Koordinaten werden daher — anders als bei AppKit — nicht gespiegelt.
void BuildGeometry(SplashState* state, float mark_size) {
  state->geometry_valid = false;
  state->hex_geometry.Reset();
  state->bar_geometry.Reset();
  if (mark_size <= 0.0f) return;

  const float s = mark_size / 120.0f;
  auto point = [s](float x, float y) { return D2D1::Point2F(x * s, y * s); };

  struct {
    ComPtr<ID2D1PathGeometry>* target;
    bool closed;
    D2D1_POINT_2F points[6];
    int count;
  } shapes[] = {
      {&state->hex_geometry,
       true,
       {point(60, 14), point(99.8f, 37), point(99.8f, 83), point(60, 106),
        point(20.2f, 83), point(20.2f, 37)},
       6},
      {&state->bar_geometry, false, {point(20.2f, 60), point(99.8f, 60)}, 2},
  };

  for (auto& shape : shapes) {
    ComPtr<ID2D1PathGeometry> geometry;
    if (FAILED(state->d2d_factory->CreatePathGeometry(&geometry))) return;
    ComPtr<ID2D1GeometrySink> sink;
    if (FAILED(geometry->Open(&sink))) return;
    sink->BeginFigure(shape.points[0], D2D1_FIGURE_BEGIN_HOLLOW);
    for (int i = 1; i < shape.count; ++i) sink->AddLine(shape.points[i]);
    sink->EndFigure(shape.closed ? D2D1_FIGURE_END_CLOSED
                                 : D2D1_FIGURE_END_OPEN);
    if (FAILED(sink->Close())) return;
    *shape.target = geometry;
  }

  if (FAILED(state->hex_geometry->ComputeLength(nullptr, &state->hex_length)) ||
      FAILED(state->bar_geometry->ComputeLength(nullptr, &state->bar_length))) {
    return;
  }
  state->mark_size = mark_size;
  state->geometry_valid = true;
}

// Teil-Stroke über ein Dash-Muster: sichtbares Segment = progress * Länge.
// D2D rechnet Dash-Längen in Vielfachen der Strichstärke.
void DrawPartialStroke(SplashState* state, ID2D1Geometry* geometry,
                       ID2D1Brush* brush, float total_length, float stroke_width,
                       float progress) {
  if (progress <= 0.0f || stroke_width <= 0.0f) return;
  if (progress >= 1.0f) {
    ComPtr<ID2D1StrokeStyle> solid;
    state->d2d_factory->CreateStrokeStyle(
        D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
                                    D2D1_CAP_STYLE_ROUND,
                                    D2D1_LINE_JOIN_ROUND),
        nullptr, 0, &solid);
    state->render_target->DrawGeometry(geometry, brush, stroke_width,
                                       solid.Get());
    return;
  }
  const float visible = (total_length * progress) / stroke_width;
  const float hidden = (total_length / stroke_width) + 1.0f;
  const float dashes[] = {visible, hidden};
  ComPtr<ID2D1StrokeStyle> dashed;
  if (FAILED(state->d2d_factory->CreateStrokeStyle(
          D2D1::StrokeStyleProperties(
              D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
              D2D1_LINE_JOIN_ROUND, 10.0f, D2D1_DASH_STYLE_CUSTOM, 0.0f),
          dashes, ARRAYSIZE(dashes), &dashed))) {
    return;
  }
  state->render_target->DrawGeometry(geometry, brush, stroke_width,
                                     dashed.Get());
}

void Render(HWND hwnd, SplashState* state) {
  if (!state->render_target) return;

  RECT client;
  GetClientRect(hwnd, &client);
  const float width = static_cast<float>(client.right - client.left);
  const float height = static_cast<float>(client.bottom - client.top);
  if (width <= 0 || height <= 0) return;

  const float t = ElapsedSeconds(*state);

  // Layout: Logo = 30 % der kleineren Fensterkante, Wortmarke darunter.
  const float m = (std::min)(width, height);
  const float mark_size = m * 0.30f;
  const float gap = m * 0.06f;
  const float font_size = m * 0.095f;
  if (std::fabs(mark_size - state->mark_size) > 0.5f) {
    BuildGeometry(state, mark_size);
  }

  state->render_target->BeginDraw();
  state->render_target->Clear(state->dark ? kBgDark : kBgLight);

  ComPtr<ID2D1SolidColorBrush> brush;
  if (FAILED(state->render_target->CreateSolidColorBrush(kMarkColor, &brush))) {
    state->render_target->EndDraw();
    return;
  }

  // Wortmarken-Höhe zuerst messen, damit der Block exakt zentriert steht.
  float word_height = font_size * 1.3f;
  ComPtr<IDWriteTextLayout> layout;
  if (state->text_format && state->dwrite_factory) {
    if (SUCCEEDED(state->dwrite_factory->CreateTextLayout(
            L"hinata", 6, state->text_format.Get(), width, height * 2,
            &layout))) {
      DWRITE_TEXT_METRICS metrics{};
      if (SUCCEEDED(layout->GetMetrics(&metrics))) word_height = metrics.height;
    }
  }

  const float total_height = mark_size + gap + word_height;
  const float top = (height - total_height) / 2.0f;
  const float mark_left = (width - mark_size) / 2.0f;

  if (state->geometry_valid) {
    const float scale = 0.94f + 0.06f * Spring((std::max)(0.0f, t - kPopStart));
    const float center_x = mark_left + mark_size / 2.0f;
    const float center_y = top + mark_size / 2.0f;
    state->render_target->SetTransform(
        D2D1::Matrix3x2F::Translation(mark_left, top) *
        D2D1::Matrix3x2F::Scale(scale, scale, D2D1::Point2F(center_x,
                                                            center_y)));

    const float stroke_width = 11.0f * (mark_size / 120.0f);
    DrawPartialStroke(
        state, state->hex_geometry.Get(), brush.Get(), state->hex_length,
        stroke_width,
        CubicBezier(0.66f, 0, 0.18f, 1, (t - kHexStart) / kHexDuration));
    DrawPartialStroke(
        state, state->bar_geometry.Get(), brush.Get(), state->bar_length,
        stroke_width,
        CubicBezier(0.4f, 0, 0.18f, 1, (t - kBarStart) / kBarDuration));
    state->render_target->SetTransform(D2D1::Matrix3x2F::Identity());
  }

  if (layout && t >= kWordStart) {
    const float opacity =
        CubicBezier(0.22f, 1, 0.36f, 1, (t - kWordStart) / kWordDuration);
    brush->SetOpacity(opacity);
    state->render_target->DrawTextLayout(
        D2D1::Point2F(0, top + mark_size + gap), layout.Get(), brush.Get());
    brush->SetOpacity(1.0f);
  }

  state->render_target->EndDraw();
}

LRESULT CALLBACK SplashWndProc(HWND hwnd, UINT message, WPARAM wparam,
                               LPARAM lparam) {
  SplashState* state = StateOf(hwnd);

  switch (message) {
    case WM_TIMER: {
      if (!state) break;
      const float t = ElapsedSeconds(*state);
      if (t >= kFadeStart) {
        const float fade = (std::min)(1.0f, (t - kFadeStart) / kFadeDuration);
        SetLayeredWindowAttributes(
            hwnd, 0, static_cast<BYTE>((1.0f - fade) * 255.0f), LWA_ALPHA);
      }
      if (t >= kTotal) {
        KillTimer(hwnd, kTimerId);
        DestroyWindow(hwnd);
        return 0;
      }
      Render(hwnd, state);
      return 0;
    }
    case WM_PAINT: {
      if (state) Render(hwnd, state);
      ValidateRect(hwnd, nullptr);
      return 0;
    }
    case WM_SIZE: {
      if (state && state->render_target) {
        state->render_target->Resize(
            D2D1::SizeU(LOWORD(lparam), HIWORD(lparam)));
      }
      return 0;
    }
    case WM_ERASEBKGND:
      return 1;  // Kein Flackern — gezeichnet wird ausschließlich per D2D.
    case WM_NCHITTEST:
      return HTTRANSPARENT;  // Klicks gehen an das Flutter-Fenster darunter.
    case WM_DESTROY: {
      if (state) {
        if (state->owner) state->owner->OnWindowDestroyed();
        SetWindowLongPtr(hwnd, GWLP_USERDATA, 0);
        delete state;
      }
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace

std::unique_ptr<HinataSplash> HinataSplash::Present(HWND parent) {
  if (!parent) return nullptr;

  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = SplashWndProc;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.lpszClassName = kWindowClass;
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    if (!RegisterClassW(&window_class)) return nullptr;
    class_registered = true;
  }

  auto state = std::make_unique<SplashState>();
  if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
                               state->d2d_factory.GetAddressOf()))) {
    return nullptr;
  }
  if (FAILED(DWriteCreateFactory(
          DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
          reinterpret_cast<IUnknown**>(state->dwrite_factory.GetAddressOf())))) {
    return nullptr;
  }

  RECT client;
  GetClientRect(parent, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;

  HWND hwnd = CreateWindowExW(
      WS_EX_LAYERED, kWindowClass, L"", WS_CHILD | WS_VISIBLE, 0, 0, width,
      height, parent, nullptr, GetModuleHandle(nullptr), nullptr);
  if (!hwnd) return nullptr;
  SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

  if (FAILED(state->d2d_factory->CreateHwndRenderTarget(
          D2D1::RenderTargetProperties(),
          D2D1::HwndRenderTargetProperties(
              hwnd, D2D1::SizeU((std::max)(1, width), (std::max)(1, height))),
          &state->render_target))) {
    DestroyWindow(hwnd);
    return nullptr;
  }

  // Sora (wght 600) aus den Flutter-Assets; Fallback: Segoe UI Semibold.
  const float font_size =
      (std::max)(1.0f, static_cast<float>((std::min)(width, height))) * 0.095f;
  const std::wstring sora = SoraFontPath();
  ComPtr<IDWriteFactory5> dwrite5;
  if (!sora.empty() &&
      SUCCEEDED(state->dwrite_factory.As(&dwrite5))) {
    ComPtr<IDWriteFontFile> font_file;
    ComPtr<IDWriteFontSetBuilder1> set_builder;
    ComPtr<IDWriteFontSet> font_set;
    if (SUCCEEDED(dwrite5->CreateFontFileReference(sora.c_str(), nullptr,
                                                   &font_file))) {
      ComPtr<IDWriteFontSetBuilder> builder;
      if (SUCCEEDED(dwrite5->CreateFontSetBuilder(&builder)) &&
          SUCCEEDED(builder.As(&set_builder)) &&
          SUCCEEDED(set_builder->AddFontFile(font_file.Get())) &&
          SUCCEEDED(set_builder->CreateFontSet(&font_set))) {
        ComPtr<IDWriteFontCollection1> collection;
        if (SUCCEEDED(dwrite5->CreateFontCollectionFromFontSet(font_set.Get(),
                                                               &collection))) {
          state->font_collection = collection;
        }
      }
    }
  }
  state->dwrite_factory->CreateTextFormat(
      state->font_collection ? L"Sora" : L"Segoe UI",
      state->font_collection.Get(), DWRITE_FONT_WEIGHT_SEMI_BOLD,
      DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, font_size, L"",
      &state->text_format);
  if (state->text_format) {
    state->text_format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
  }

  state->dark = SystemUsesDarkTheme();
  QueryPerformanceFrequency(&state->frequency);
  QueryPerformanceCounter(&state->start_ticks);

  auto splash = std::unique_ptr<HinataSplash>(new HinataSplash());
  splash->hwnd_ = hwnd;
  state->owner = splash.get();

  SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(
                                            state.release()));
  SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  SetTimer(hwnd, kTimerId, kFrameIntervalMs, nullptr);
  return splash;
}

HinataSplash::~HinataSplash() {
  if (hwnd_ && IsWindow(hwnd_)) DestroyWindow(hwnd_);
}

void HinataSplash::Resize(int width, int height) {
  if (hwnd_ && IsWindow(hwnd_)) {
    SetWindowPos(hwnd_, HWND_TOP, 0, 0, width, height, SWP_NOACTIVATE);
  }
}
