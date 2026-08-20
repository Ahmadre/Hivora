#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // A second `hinata` (or `xdg-open hinata://…`) is forwarded to this process
  // rather than starting its own — see my_application_command_line — so
  // activate() can be reached again while a window already exists. Building a
  // second FlView would mean a second Dart isolate with its own session and
  // its own idea of which server is selected; present what is already running
  // instead.
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "hinata");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "hinata");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command_line.
//
// This replaces the generated `local_command_line` override, and that swap is
// what makes `hinata://` deep links work at all on Linux.
//
// The generated override registered the application and activated it in the
// *local* process, which — together with G_APPLICATION_NON_UNIQUE — meant every
// `xdg-open hinata://auth-callback?code=…` started a brand-new Hinata with its
// own Dart isolate, while the instance the user was actually signing in from
// never heard about the link. Handing the work to GApplication's default
// local_command_line instead gives us the standard GNOME single-instance
// behaviour: the first process owns the bus name and every later launch ships
// its argv over D-Bus to that process, which emits ::command-line here.
//
// The URI itself is delivered to Dart by the `gtk` plugin (a dependency of
// app_links_linux), which connects its own ::command-line handler when the
// plugins are registered. That handler is the reason this function does not
// forward anything itself: ::command-line uses g_signal_accumulator_first_wins,
// so the first handler to return ends the emission — on a re-launch the plugin
// wins and this class closure never runs, and on the very first launch there is
// no plugin yet and this one runs. Both paths are needed; neither is redundant.
//
// A cold start is therefore the case the plugin cannot see, which is why the
// arguments are still forwarded to the Dart entrypoint below: `main` picks the
// hinata:// one out of them itself (see _launchDeepLink in lib/main.dart).
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);

  gint argc = 0;
  gchar** arguments =
      g_application_command_line_get_arguments(command_line, &argc);
  // Strip out the first argument as it is the binary name — but only if there
  // is one. These arguments are not this process's argv: on a re-launch they
  // arrive over D-Bus from whichever process asked this instance to open a
  // link, and nothing on that wire guarantees a program name is present. An
  // empty array is a one-element array holding only the NULL terminator, so
  // `arguments + 1` would point past the end of the allocation and g_strdupv
  // would read whatever follows it on the heap.
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments =
      g_strdupv(argc > 0 ? arguments + 1 : arguments);
  g_strfreev(arguments);

  // GApplication does NOT activate by itself once an application claims to
  // handle its own command line — without this the window would never appear.
  g_application_activate(application);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // G_APPLICATION_HANDLES_COMMAND_LINE, and deliberately NOT the generated
  // G_APPLICATION_NON_UNIQUE: the desktop entry registers
  // x-scheme-handler/hinata and launches `hinata %u`, so a deep link arrives as
  // a *new* process, and only a unique application forwards that argv to the
  // instance the user is already working in (see my_application_command_line).
  // The trade-off is that `hinata` can no longer be started twice — the second
  // launch hands its arguments to the first and exits. That is what every GNOME
  // application does, and the app can switch servers from inside anyway; it is
  // worth knowing during development, where a stale instance makes a fresh
  // `flutter run -d linux` exit immediately.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
