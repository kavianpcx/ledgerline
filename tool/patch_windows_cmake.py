from pathlib import Path


cmake_path = Path("windows/CMakeLists.txt")
cmake = cmake_path.read_text(encoding="utf-8")
definition = "add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)"
if definition not in cmake:
    marker = "include(flutter/generated_plugins.cmake)"
    if marker not in cmake:
        raise SystemExit("Generated Windows CMake file has no Flutter plugin include.")
    cmake = cmake.replace(marker, f"{definition}\n{marker}", 1)
    cmake_path.write_text(cmake, encoding="utf-8")
