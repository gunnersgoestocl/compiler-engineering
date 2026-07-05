cmake_minimum_required(VERSION 3.20)
project(LLVMIRAndSSALab LANGUAGES C CXX)

find_package(LLVM REQUIRED CONFIG)

message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

function(add_ir_ssa_lab_pass_plugin target_name source_file)
  add_library(${target_name} MODULE ${source_file})

  target_compile_features(${target_name} PRIVATE cxx_std_17)
  target_include_directories(${target_name} PRIVATE
    ${LLVM_INCLUDE_DIRS}
  )
  target_compile_options(${target_name} PRIVATE
    ${LLVM_DEFINITIONS}
  )

  if(NOT LLVM_ENABLE_RTTI)
    target_compile_options(${target_name} PRIVATE -fno-rtti)
  endif()

  set_target_properties(${target_name} PROPERTIES
    PREFIX ""
  )

  if(APPLE)
    # LLVM pass plugins are loaded by opt. On macOS, unresolved LLVM symbols
    # are intentionally resolved from the host process at load time.
    set_target_properties(${target_name} PROPERTIES
      SUFFIX ".dylib"
      LINK_FLAGS "-undefined dynamic_lookup"
    )
  else()
    llvm_map_components_to_libnames(LLVM_LIBS
      Analysis
      Core
      Support
      TransformUtils
    )
    target_link_libraries(${target_name} PRIVATE ${LLVM_LIBS})
  endif()
endfunction()

add_ir_ssa_lab_pass_plugin(IRAndSSALabPass src/IRAndSSALabPass.cpp)

# Builds the student template as-is (with its TODOs unfilled, this loads and
# runs but prints nothing and folds nothing). Point opt at this plugin while
# filling in template/IRAndSSALabPass.cpp to iterate without touching src/.
add_ir_ssa_lab_pass_plugin(IRAndSSALabPassTemplate template/IRAndSSALabPass.cpp)

add_subdirectory(exercises/01_const_fold_standalone)
add_subdirectory(exercises/02_build_module_irbuilder)
add_subdirectory(exercises/03_def_use_scope_change)
