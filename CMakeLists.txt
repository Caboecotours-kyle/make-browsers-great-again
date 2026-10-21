cmake_minimum_required(VERSION 3.24)

# Configure with scripts/build.sh, which fetches CEF and Ninja first.

set(MBGA_MIN_MACOS 15.0)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET ${MBGA_MIN_MACOS})
set(CMAKE_Swift_COMPILER_TARGET arm64-apple-macosx${MBGA_MIN_MACOS})
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

project(mbga LANGUAGES C CXX Swift)

set(MBGA_PRODUCT_NAME "MBGA")
set(MBGA_BUNDLE_ID "dev.mbga.browser")
set(MBGA_VERSION "0.1.0")
option(MBGA_MOCK_KEYCHAIN "Use a mock keychain (avoids prompts on ad-hoc signed builds)" ON)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out")

# ----------------------------------------------------------------------- CEF

set(CEF_ROOT "${CMAKE_SOURCE_DIR}/third_party/cef/dist")
if(NOT EXISTS "${CEF_ROOT}/cmake/FindCEF.cmake")
  message(FATAL_ERROR "CEF not found in ${CEF_ROOT}. Run scripts/fetch-cef.sh.")
endif()
list(APPEND CMAKE_MODULE_PATH "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)
add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)
# FindCEF lowers the deployment target for its own code; ours needs macOS 15.
set(CMAKE_OSX_DEPLOYMENT_TARGET ${MBGA_MIN_MACOS})
set(CEF_FRAMEWORK "${CEF_BINARY_DIR_RELEASE}/Chromium Embedded Framework.framework")

# ----------------------------------------------------------------- Rust core

find_program(CARGO cargo HINTS "$ENV{HOME}/.cargo/bin" REQUIRED)
set(CORE_DIR "${CMAKE_SOURCE_DIR}/core")
set(CORE_TARGET_DIR "${CMAKE_BINARY_DIR}/core-target")
set(CORE_LIB "${CORE_TARGET_DIR}/release/libmbga_core.a")
set(CORE_GEN "${CMAKE_BINARY_DIR}/core-bindings")
set(CORE_SWIFT "${CORE_GEN}/mbga_core.swift")
file(GLOB_RECURSE CORE_SOURCES CONFIGURE_DEPENDS "${CORE_DIR}/src/*.rs")

add_custom_command(
  OUTPUT "${CORE_LIB}" "${CORE_SWIFT}" "${CORE_GEN}/mbga_coreFFI.h"
         "${CORE_GEN}/mbga_coreFFI.modulemap"
  COMMAND ${CMAKE_COMMAND} -E env MACOSX_DEPLOYMENT_TARGET=${MBGA_MIN_MACOS}
          "${CARGO}" build --release --lib
          --manifest-path "${CORE_DIR}/Cargo.toml"
          --target-dir "${CORE_TARGET_DIR}"
  # The bindgen CLI lives behind a feature so it never ends up in the app;
  # build it in its own target dir to keep the library's features lean.
  COMMAND ${CMAKE_COMMAND} -E env MACOSX_DEPLOYMENT_TARGET=${MBGA_MIN_MACOS}
          "${CARGO}" run --release --quiet --features bindgen
          --bin uniffi-bindgen
          --manifest-path "${CORE_DIR}/Cargo.toml"
          --target-dir "${CORE_TARGET_DIR}/bindgen"
          -- generate --library "${CORE_TARGET_DIR}/release/libmbga_core.dylib"
          --language swift --out-dir "${CORE_GEN}"
  DEPENDS ${CORE_SOURCES} "${CORE_DIR}/Cargo.toml"
  WORKING_DIRECTORY "${CORE_DIR}"
  COMMENT "Building Rust core"
  USES_TERMINAL
  VERBATIM)
add_custom_target(mbga_core DEPENDS "${CORE_LIB}" "${CORE_SWIFT}")

# ------------------------------------------------------------- engine bridge

add_library(mbga_engine STATIC
  shell/engine/MBEngine.h
  shell/engine/MBEngine.mm)
SET_LIBRARY_TARGET_PROPERTIES(mbga_engine)
target_compile_options(mbga_engine PRIVATE -fobjc-arc)
if(MBGA_MOCK_KEYCHAIN)
  target_compile_definitions(mbga_engine PRIVATE MBGA_MOCK_KEYCHAIN)
endif()
add_dependencies(mbga_engine libcef_dll_wrapper)

# ------------------------------------------------------------ helper bundles

# The engine starts its subprocesses from these bundles. One per process
# type, all from the same executable, as Chromium expects on macOS.
set(MBGA_HELPER_TARGETS "")
set(MBGA_HELPER_NAMES "")
foreach(_suffixes ${CEF_HELPER_APP_SUFFIXES})
  string(REPLACE ":" ";" _suffixes "${_suffixes}")
  list(GET _suffixes 0 _name_suffix)
  list(GET _suffixes 1 _target_suffix)
  list(GET _suffixes 2 _plist_suffix)

  set(MBGA_HELPER_NAME "${MBGA_PRODUCT_NAME} Helper${_name_suffix}")
  set(MBGA_HELPER_ID_SUFFIX "${_plist_suffix}")
  set(_target "mbga_helper${_target_suffix}")
  set(_plist "${CMAKE_BINARY_DIR}/helper${_target_suffix}-Info.plist")
  configure_file(shell/resources/helper-Info.plist.in "${_plist}")

  add_executable(${_target} MACOSX_BUNDLE shell/helper/helper_main.mm)
  SET_EXECUTABLE_TARGET_PROPERTIES(${_target})
  add_dependencies(${_target} libcef_dll_wrapper)
  target_link_libraries(${_target} libcef_dll_wrapper ${CEF_STANDARD_LIBS})
  set_target_properties(${_target} PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${_plist}"
    OUTPUT_NAME "${MBGA_HELPER_NAME}")

  list(APPEND MBGA_HELPER_TARGETS ${_target})
  list(APPEND MBGA_HELPER_NAMES "${MBGA_HELPER_NAME}")
endforeach()

# ----------------------------------------------------------------------- app

file(GLOB MBGA_SWIFT_SOURCES CONFIGURE_DEPENDS shell/app/*.swift)
set_source_files_properties("${CORE_SWIFT}" PROPERTIES GENERATED TRUE)
configure_file(shell/resources/Info.plist.in "${CMAKE_BINARY_DIR}/Info.plist")

add_executable(mbga MACOSX_BUNDLE ${MBGA_SWIFT_SOURCES} "${CORE_SWIFT}")
add_dependencies(mbga mbga_core ${MBGA_HELPER_TARGETS})
set_target_properties(mbga PROPERTIES
  OUTPUT_NAME "${MBGA_PRODUCT_NAME}"
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_BINARY_DIR}/Info.plist")
target_compile_options(mbga PRIVATE
  "SHELL:-import-objc-header ${CMAKE_SOURCE_DIR}/shell/engine/MBEngine.h"
  "SHELL:-Xcc -fmodule-map-file=${CORE_GEN}/mbga_coreFFI.modulemap"
  "SHELL:-I ${CORE_GEN}")
target_link_libraries(mbga PRIVATE
  mbga_engine libcef_dll_wrapper "${CORE_LIB}" ${CEF_STANDARD_LIBS})

# Assemble the bundle: helpers and the framework go into Contents/Frameworks.
# rsync keeps incremental builds fast (the framework is ~320 MB).
set(_app "$<TARGET_BUNDLE_DIR:mbga>")
add_custom_command(TARGET mbga POST_BUILD
  COMMAND mkdir -p "${_app}/Contents/Frameworks/Chromium Embedded Framework.framework/Versions"
  COMMAND rsync -a --delete "${CEF_FRAMEWORK}/"
          "${_app}/Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/"
  COMMAND cd "${_app}/Contents/Frameworks/Chromium Embedded Framework.framework" &&
          ln -sfh A Versions/Current &&
          ln -sfh "Versions/A/Chromium Embedded Framework" "Chromium Embedded Framework" &&
          ln -sfh Versions/A/Libraries Libraries &&
          ln -sfh Versions/A/Resources Resources
  VERBATIM)
foreach(_name ${MBGA_HELPER_NAMES})
  add_custom_command(TARGET mbga POST_BUILD
    COMMAND rsync -a --delete "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/${_name}.app/"
            "${_app}/Contents/Frameworks/${_name}.app/"
    VERBATIM)
endforeach()
add_custom_command(TARGET mbga POST_BUILD
  COMMAND codesign --force --deep --sign - "${_app}"
  COMMENT "Ad-hoc signing ${MBGA_PRODUCT_NAME}.app"
  VERBATIM)
