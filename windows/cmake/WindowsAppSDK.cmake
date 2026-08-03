# Windows App SDK for the Flutter runner.
#
# The runner is a plain CMake project, while the Windows App SDK ships as NuGet
# packages with MSBuild targets and no pre-generated C++ headers — the projection
# has to be produced from the shipped .winmd metadata. This module does that
# without introducing MSBuild or a vendored binary blob in the repo:
#
#   1. download the two NuGet packages (they are ordinary zips) at configure time
#   2. run cppwinrt.exe over the metadata to generate winrt/Microsoft.Windows.*.h
#   3. expose it all as the `windows_app_sdk` interface target
#   4. stage Microsoft.WindowsAppRuntime.Bootstrap.dll next to the executable
#
# Only needed for push notifications: Firebase has no Windows implementation, so
# Windows registers a WNS channel instead, and only PushNotificationManager can
# mint one for a packaged Win32 app (the classic PushNotificationChannelManager
# authenticates against a retired endpoint).

set(WASDK_FOUNDATION_VERSION "2.3.5")
# MUST match the cppwinrt the Windows SDK ships, because the generated headers
# are consumed together with the SDK's own winrt/base.h — we generate only the
# App SDK namespaces, not a full projection, so base.h is never ours. A newer
# generator produces headers whose static_assert rejects the older base.h with
# "Mismatched C++/WinRT headers".
#   Windows Kits 10.0.26100.0 → CPPWINRT_VERSION "2.0.250303.1"
set(WASDK_CPPWINRT_VERSION "2.0.250303.1")

set(WASDK_ROOT "${CMAKE_BINARY_DIR}/windows_app_sdk")
set(WASDK_FOUNDATION_DIR "${WASDK_ROOT}/foundation")
set(WASDK_CPPWINRT_DIR "${WASDK_ROOT}/cppwinrt")
set(WASDK_PROJECTION_DIR "${WASDK_ROOT}/projection")

# --- 1. fetch -----------------------------------------------------------------
function(_wasdk_fetch package version destination)
  if(EXISTS "${destination}/.fetched")
    return()
  endif()
  set(archive "${WASDK_ROOT}/${package}.${version}.zip")
  string(TOLOWER "${package}" lower)
  message(STATUS "Windows App SDK: fetching ${package} ${version}")
  file(DOWNLOAD
    "https://api.nuget.org/v3-flatcontainer/${lower}/${version}/${lower}.${version}.nupkg"
    "${archive}" STATUS status TLS_VERIFY ON SHOW_PROGRESS)
  list(GET status 0 code)
  if(NOT code EQUAL 0)
    list(GET status 1 reason)
    message(FATAL_ERROR "Could not download ${package} ${version}: ${reason}")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${destination}")
  file(WRITE "${destination}/.fetched" "${version}")
endfunction()

_wasdk_fetch("Microsoft.WindowsAppSDK.Foundation" "${WASDK_FOUNDATION_VERSION}" "${WASDK_FOUNDATION_DIR}")
_wasdk_fetch("Microsoft.Windows.CppWinRT" "${WASDK_CPPWINRT_VERSION}" "${WASDK_CPPWINRT_DIR}")

# --- 2. generate the C++/WinRT projection -------------------------------------
#
# Generate ONLY the two namespaces the runner uses, and merely *reference* the
# rest of the metadata. Feeding the whole metadata folder as `-input` fails:
# Microsoft.Security.Authentication.OAuth references Microsoft.UI.WindowId, a
# WinUI type that lives in a different package we neither ship nor need.
# `-reference sdk` supplies the Windows SDK types both projections build on.
if(NOT EXISTS "${WASDK_PROJECTION_DIR}/winrt/Microsoft.Windows.PushNotifications.h")
  message(STATUS "Windows App SDK: generating the C++/WinRT projection")
  execute_process(
    COMMAND "${WASDK_CPPWINRT_DIR}/bin/cppwinrt.exe"
            -input "${WASDK_FOUNDATION_DIR}/metadata/Microsoft.Windows.PushNotifications.winmd"
            -input "${WASDK_FOUNDATION_DIR}/metadata/Microsoft.Windows.AppLifecycle.winmd"
            # Clicking a toast activates the app through AppNotifications, not
            # through the push path — without this the deep link in the
            # notification's launch argument is simply dropped.
            -input "${WASDK_FOUNDATION_DIR}/metadata/Microsoft.Windows.AppNotifications.winmd"
            -reference "${WASDK_FOUNDATION_DIR}/metadata"
            -reference sdk
            -output "${WASDK_PROJECTION_DIR}"
    RESULT_VARIABLE cppwinrt_result
    OUTPUT_VARIABLE cppwinrt_output
    ERROR_VARIABLE cppwinrt_output)
  if(NOT cppwinrt_result EQUAL 0)
    message(FATAL_ERROR "cppwinrt failed: ${cppwinrt_output}")
  endif()
endif()

# --- 3. the target ------------------------------------------------------------
add_library(windows_app_sdk INTERFACE)
target_include_directories(windows_app_sdk INTERFACE
  "${WASDK_PROJECTION_DIR}"
  "${WASDK_FOUNDATION_DIR}/include")
target_link_libraries(windows_app_sdk INTERFACE
  "${WASDK_FOUNDATION_DIR}/lib/native/x64/Microsoft.WindowsAppRuntime.Bootstrap.lib")

# --- 4. the runtime DLL -------------------------------------------------------
# The bootstrapper DLL must sit beside the executable; the rest of the runtime
# comes from the framework package the MSIX depends on.
set(WASDK_BOOTSTRAP_DLL
  "${WASDK_FOUNDATION_DIR}/runtimes/win-x64/native/Microsoft.WindowsAppRuntime.Bootstrap.dll"
  CACHE INTERNAL "")
