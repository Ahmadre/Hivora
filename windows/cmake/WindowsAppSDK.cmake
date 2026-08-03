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

# The generator MUST match the cppwinrt the Windows SDK ships, because the
# generated headers are consumed together with the SDK's own winrt/base.h — we
# generate only the App SDK namespaces, not a full projection, so base.h is
# never ours. A mismatched generator produces headers whose static_assert
# rejects that base.h with "Mismatched C++/WinRT headers".
#
# Which version that is depends on the machine: a dev box and a CI runner ship
# different Windows Kits. So it is read out of the SDK's own base.h instead of
# pinned — a pin only ever matches the machine it was written on. The fallback
# is this repo's dev baseline (Windows Kits 10.0.26100.0).
set(WASDK_CPPWINRT_FALLBACK "2.0.250303.1")

set(_wasdk_base_headers "")
foreach(_kit_root "$ENV{ProgramFiles\(x86\)}/Windows Kits/10" "$ENV{ProgramFiles}/Windows Kits/10")
  if(EXISTS "${_kit_root}/Include")
    file(GLOB _found "${_kit_root}/Include/*/cppwinrt/winrt/base.h")
    list(APPEND _wasdk_base_headers ${_found})
  endif()
endforeach()
# Prefer the kit the build actually targets; otherwise the newest installed one.
set(_wasdk_base_h "")
if(CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION)
  foreach(_candidate ${_wasdk_base_headers})
    if(_candidate MATCHES "/Include/${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}/")
      set(_wasdk_base_h "${_candidate}")
    endif()
  endforeach()
endif()
if(NOT _wasdk_base_h AND _wasdk_base_headers)
  list(SORT _wasdk_base_headers)
  list(GET _wasdk_base_headers -1 _wasdk_base_h)
endif()

set(WASDK_CPPWINRT_VERSION "${WASDK_CPPWINRT_FALLBACK}")
if(_wasdk_base_h)
  file(STRINGS "${_wasdk_base_h}" _wasdk_version_line
       REGEX "^#define[ \t]+CPPWINRT_VERSION[ \t]" LIMIT_COUNT 1)
  if(_wasdk_version_line MATCHES "\"([0-9][0-9A-Za-z.-]*)\"")
    set(WASDK_CPPWINRT_VERSION "${CMAKE_MATCH_1}")
    message(STATUS "Windows App SDK: SDK cppwinrt is ${WASDK_CPPWINRT_VERSION} (${_wasdk_base_h})")
  endif()
endif()

set(WASDK_ROOT "${CMAKE_BINARY_DIR}/windows_app_sdk")
set(WASDK_FOUNDATION_DIR "${WASDK_ROOT}/foundation")
set(WASDK_CPPWINRT_DIR "${WASDK_ROOT}/cppwinrt")
set(WASDK_PROJECTION_DIR "${WASDK_ROOT}/projection")

# --- 1. fetch -----------------------------------------------------------------
# |ok| reports success instead of aborting, so a version that turns out not to
# exist on nuget.org can be retried with another one.
function(_wasdk_fetch package version destination ok)
  set(${ok} TRUE PARENT_SCOPE)
  if(EXISTS "${destination}/.fetched")
    # The marker records the version, so switching versions (a different SDK on
    # this machine, a bumped pin) actually re-downloads instead of silently
    # keeping the old package.
    file(READ "${destination}/.fetched" fetched)
    if(fetched STREQUAL version)
      return()
    endif()
    file(REMOVE_RECURSE "${destination}")
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
    message(STATUS "Windows App SDK: ${package} ${version} unavailable — ${reason}")
    file(REMOVE "${archive}")
    set(${ok} FALSE PARENT_SCOPE)
    return()
  endif()
  file(ARCHIVE_EXTRACT INPUT "${archive}" DESTINATION "${destination}")
  file(WRITE "${destination}/.fetched" "${version}")
endfunction()

_wasdk_fetch("Microsoft.WindowsAppSDK.Foundation" "${WASDK_FOUNDATION_VERSION}"
             "${WASDK_FOUNDATION_DIR}" _wasdk_ok)
if(NOT _wasdk_ok)
  message(FATAL_ERROR
    "Could not download Microsoft.WindowsAppSDK.Foundation ${WASDK_FOUNDATION_VERSION}")
endif()

_wasdk_fetch("Microsoft.Windows.CppWinRT" "${WASDK_CPPWINRT_VERSION}"
             "${WASDK_CPPWINRT_DIR}" _wasdk_ok)
# Not every SDK's cppwinrt build is published to nuget.org under that exact
# version. Falling back keeps the build going; a mismatch would then surface as
# a clear "Mismatched C++/WinRT headers" error rather than a download failure.
if(NOT _wasdk_ok AND NOT WASDK_CPPWINRT_VERSION STREQUAL WASDK_CPPWINRT_FALLBACK)
  message(WARNING "Windows App SDK: cppwinrt ${WASDK_CPPWINRT_VERSION} is not on "
                  "nuget.org — falling back to ${WASDK_CPPWINRT_FALLBACK}")
  set(WASDK_CPPWINRT_VERSION "${WASDK_CPPWINRT_FALLBACK}")
  _wasdk_fetch("Microsoft.Windows.CppWinRT" "${WASDK_CPPWINRT_VERSION}"
               "${WASDK_CPPWINRT_DIR}" _wasdk_ok)
endif()
if(NOT _wasdk_ok)
  message(FATAL_ERROR "Could not download Microsoft.Windows.CppWinRT ${WASDK_CPPWINRT_VERSION}")
endif()

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
