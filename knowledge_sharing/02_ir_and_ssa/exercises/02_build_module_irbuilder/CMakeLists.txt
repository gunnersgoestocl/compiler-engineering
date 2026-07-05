add_executable(build_module_irbuilder
  main.cpp
  your_turn/populate_function.cpp
  solution/populate_function.cpp
)

target_compile_features(build_module_irbuilder PRIVATE cxx_std_17)
target_include_directories(build_module_irbuilder PRIVATE
  ${LLVM_INCLUDE_DIRS}
)
target_compile_options(build_module_irbuilder PRIVATE
  ${LLVM_DEFINITIONS}
)

if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(build_module_irbuilder PRIVATE -fno-rtti)
endif()

llvm_map_components_to_libnames(BUILD_MODULE_LLVM_LIBS
  Core
  Support
)
target_link_libraries(build_module_irbuilder PRIVATE ${BUILD_MODULE_LLVM_LIBS})
