add_executable(def_use_scope_change main.cpp)

target_compile_features(def_use_scope_change PRIVATE cxx_std_17)
target_include_directories(def_use_scope_change PRIVATE
  ${LLVM_INCLUDE_DIRS}
)
target_compile_options(def_use_scope_change PRIVATE
  ${LLVM_DEFINITIONS}
)

if(NOT LLVM_ENABLE_RTTI)
  target_compile_options(def_use_scope_change PRIVATE -fno-rtti)
endif()

llvm_map_components_to_libnames(DEF_USE_LLVM_LIBS
  AsmParser
  Core
  Support
)
target_link_libraries(def_use_scope_change PRIVATE ${DEF_USE_LLVM_LIBS})
