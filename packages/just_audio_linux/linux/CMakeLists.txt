cmake_minimum_required(VERSION 3.13)
set(PROJECT_NAME "just_audio_linux")
project(${PROJECT_NAME} LANGUAGES CXX)

# The plugin name must match the pubspec's `pluginClass`, snake-cased: the
# generated registrant calls just_audio_linux_plugin_register_with_registrar.
set(PLUGIN_NAME "just_audio_linux_plugin")

add_library(${PLUGIN_NAME} SHARED
  "just_audio_linux_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

# `flutter` carries GTK and GLib through its own interface, so only GStreamer
# has to be found here.
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET gstreamer-1.0)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GSTREAMER)

# Nothing to copy into the bundle: GStreamer is a system library on every
# desktop this runs on, and every Flatpak/Snap runtime ships it too. Bundling a
# second copy would fight the one already installed over its plugin registry.
set(just_audio_linux_bundled_libraries
  ""
  PARENT_SCOPE
)
