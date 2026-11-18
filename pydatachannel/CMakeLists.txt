cmake_minimum_required(VERSION 3.19...3.31)
project(pydatachannel LANGUAGES C CXX)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# libdatachannel (fetched by build.sh at a pinned commit), static, with only what the binding uses
set(BUILD_SHARED_LIBS OFF)
set(NO_WEBSOCKET ON)
set(NO_EXAMPLES ON)
set(NO_TESTS ON)
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)  # let the set()s above override libdatachannel's option()s
add_subdirectory(libdatachannel-src EXCLUDE_FROM_ALL)

find_package(Python 3.12 REQUIRED COMPONENTS Interpreter Development.Module Development.SABIModule)
find_package(nanobind CONFIG REQUIRED)

nanobind_add_module(_rtc STABLE_ABI NB_STATIC pydatachannel/_rtc.cpp)
target_link_libraries(_rtc PRIVATE datachannel-static)
if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
  # keep libdatachannel's and its deps' symbols out of the module's dynamic symbol table
  target_link_options(_rtc PRIVATE -Wl,--exclude-libs,ALL)
endif()
