# Copyright (c) 2017, Intel Corporation.

set_ifndef(JERRY_BASE ./deps/jerryscript)
set_ifndef(IOTC_BASE ./deps/iotivity-constrained)

set_ifndef(BOARD arduino_101)
set(ENV{BOARD} ${BOARD})

set_ifndef(JERRY_HEAP 16)
set_ifndef(JERRY_PROFILE minimal)

# build in src directory if not set
set_ifndef(JERRY_OUTPUT ${JERRY_BASE})

if("${BOARD}" STREQUAL "arduino_101")
  # ALL-IN-ONE build, slightly shrink build size, may not work on all platforms
  set(ALL_IN_ONE ON)
else()
  set(ALL_IN_ONE OFF)
endif()

if(VERBOSITY)
  add_definitions(-DZJS_VERBOSE=${VERBOSITY})
endif()

if("${SNAPSHOT}" STREQUAL "on")
  set(JS_PARSER OFF)
else()
  set(JS_PARSER ON)
endif()

if(ASHELL)
  add_definitions(-DASHELL=${ASHELL})
endif()

if(NOT "${BLE_ADDR}" STREQUAL "none")
  add_definitions(-DZJS_CONFIG_BLE_ADDRESS="${BLE_ADDR}")
endif()

if("${CB_STATS}" STREQUAL "on")
  add_definitions(-DZJS_PRINT_CALLBACK_STATS)
endif()

if("${VARIANT}" STREQUAL "debug")
  add_definitions(-DDEBUG_BUILD -DOC_DEBUG)
endif()

if(ZJS_FLAGS)
  set(ZJS_FLAGS_LIST ${ZJS_FLAGS})
  separate_arguments(ZJS_FLAGS_LIST)
  add_definitions(${ZJS_FLAGS_LIST})
endif()

target_compile_options(app PRIVATE
  -Wall
  -Wno-implicit-function-declaration
  )

set(APP_INCLUDES
  ./src
  ${ZEPHYR_BASE}/drivers
  ${JERRY_BASE}/jerry-core/include
  ${JERRY_BASE}/jerry-core/jrt
  ${JERRY_BASE}/jerry-ext/include
  ${CMAKE_BINARY_DIR}/../include
  )

set(APP_SRC
  src/main.c
  src/zjs_callbacks.c
  src/zjs_common.c
  src/zjs_error.c
  src/zjs_modules.c
  src/zjs_script.c
  src/zjs_timers.c
  src/zjs_util.c
  src/jerry-port/zjs_jerry_port.c
  )

if("${DEBUGGER}" STREQUAL "on")
  add_definitions(-DJERRY_DEBUGGER)
  add_definitions(-DZJS_DEBUGGER)
endif()

target_include_directories(app PRIVATE ${APP_INCLUDES})

target_sources(app PRIVATE ${APP_SRC})

target_link_libraries(app jerry-core jerry-ext)

include(cmake/jerry.cmake)
# additional configuration will be generated by analyze script
include(${CMAKE_BINARY_DIR}/generated.cmake)
