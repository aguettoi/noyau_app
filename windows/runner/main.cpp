#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

namespace {

constexpr wchar_t kUrlScheme[] = L"com.financielpilote.app";

bool SetCurrentUserRegistryString(const std::wstring& subkey,
                                  const wchar_t* value_name,
                                  const std::wstring& value) {
  return ::RegSetKeyValueW(
             HKEY_CURRENT_USER, subkey.c_str(), value_name, REG_SZ,
             value.c_str(),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

bool RegisterUrlProtocolForCurrentUser() {
  wchar_t executable_path[MAX_PATH];
  const DWORD path_length =
      ::GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length == MAX_PATH) {
    return false;
  }

  const std::wstring protocol_key =
      std::wstring(L"Software\\Classes\\") + kUrlScheme;
  const std::wstring command_key = protocol_key + L"\\shell\\open\\command";
  const std::wstring command =
      L"\"" + std::wstring(executable_path, path_length) + L"\" \"%1\"";

  return SetCurrentUserRegistryString(protocol_key, nullptr,
                                      L"URL:FINANCIEL PILOTE") &&
         SetCurrentUserRegistryString(protocol_key, L"URL Protocol", L"") &&
         SetCurrentUserRegistryString(command_key, nullptr, command);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Forward a protocol activation to the already-running application instead
  // of opening a second window with a second copy of the authenticated state.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // app_links handles the URI once Windows launches the application. Portable
  // Windows builds have no installer to register their custom scheme, so keep
  // the per-user handler aligned with the executable that is actually running.
  RegisterUrlProtocolForCurrentUser();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"FINANCIEL PILOTE", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
