add_executable(const_fold_standalone
  main.cpp
  your_turn/populate_function.cpp
  solution/populate_function.cpp
)

target_compile_features(const_fold_standalone PRIVATE cxx_std_17)
target_include_directories(const_fold_standalone PRIVATE
  ${LLVM_INCLUDE_DIRS}
)
target_compile_options(const_fold_standalone PRIVATE
  ${LLVM_DEFINITIONS}
)

if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(const_fold_standalone PRIVATE -fno-rtti)
endif()

llvm_map_components_to_libnames(CONST_FOLD_LLVM_LIBS
  AsmParser
  Core
  Support
  TransformUtils
)
target_link_libraries(const_fold_standalone PRIVATE ${CONST_FOLD_LLVM_LIBS})
