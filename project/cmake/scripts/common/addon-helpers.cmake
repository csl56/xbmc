# Workaround for the fact that cpack's filenames are not customizable.
# Each add-on is added as a separate component to facilitate zip/tgz packaging.
# The filenames are always of the form basename-component, which is 
# incompatible with the addonid-version scheme we want. This hack renames
# the files from the file names generated by the 'package' target.
# Sadly we cannot extend the 'package' target, as it is a builtin target, see 
# http://public.kitware.com/Bug/view.php?id=8438
# Thus, we have to add an 'addon-package' target.
add_custom_target(addon-package
                  COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target package)

macro(add_cpack_workaround target version ext)
  add_custom_command(TARGET addon-package PRE_BUILD
                     COMMAND ${CMAKE_COMMAND} -E rename addon-${target}-${version}.${ext} ${target}-${version}.${ext})
endmacro()

# Grab the version from a given add-on's addon.xml
macro (addon_version dir prefix)
  FILE(READ ${dir}/addon.xml ADDONXML)
  STRING(REGEX MATCH "<addon[^>]*version.?=.?.[0-9\\.]+" VERSION_STRING ${ADDONXML}) 
  STRING(REGEX REPLACE ".*version=.([0-9\\.]+).*" "\\1" ${prefix}_VERSION ${VERSION_STRING})
  message(STATUS ${prefix}_VERSION=${${prefix}_VERSION})
endmacro()

# Build, link and optionally package an add-on
macro (build_addon target prefix libs)
  ADD_LIBRARY(${target} ${${prefix}_SOURCES})
  TARGET_LINK_LIBRARIES(${target} ${${libs}})
  addon_version(${target} ${prefix})
  SET_TARGET_PROPERTIES(${target} PROPERTIES VERSION ${${prefix}_VERSION}
                                             SOVERSION ${APP_VERSION_MAJOR}.${APP_VERSION_MINOR}
                                             PREFIX "")
  IF(OS STREQUAL "android")
    SET_TARGET_PROPERTIES(${target} PROPERTIES PREFIX "lib")
  ENDIF(OS STREQUAL "android")

  # set zip as default if addon-package is called without PACKAGE_XXX
  SET(CPACK_GENERATOR "ZIP")
  SET(ext "zip")
  IF(PACKAGE_ZIP OR PACKAGE_TGZ)
    IF(PACKAGE_TGZ)
      SET(CPACK_GENERATOR "TGZ")
      SET(ext "tar.gz")
    ENDIF(PACKAGE_TGZ)
    SET(CPACK_INCLUDE_TOPLEVEL_DIRECTORY OFF)
    set(CPACK_PACKAGE_FILE_NAME addon)
    IF(CMAKE_BUILD_TYPE STREQUAL "Release")
      SET(CPACK_STRIP_FILES TRUE)
    ENDIF(CMAKE_BUILD_TYPE STREQUAL "Release")
    set(CPACK_ARCHIVE_COMPONENT_INSTALL ON)
    set(CPACK_COMPONENTS_IGNORE_GROUPS 1)
    list(APPEND CPACK_COMPONENTS_ALL ${target}-${${prefix}_VERSION})
    # Pack files together to create an archive
    INSTALL(DIRECTORY ${target} DESTINATION ./ COMPONENT ${target}-${${prefix}_VERSION})
    IF(WIN32)
      # get the installation location for the addon's target
      get_property(dll_location TARGET ${target} PROPERTY LOCATION)
      # in case of a VC++ project the installation location contains a $(Configuration) VS variable
      # we replace it with ${CMAKE_BUILD_TYPE} (which doesn't cover the case when the build configuration
      # is changed within Visual Studio)
      string(REPLACE "$(Configuration)" "${CMAKE_BUILD_TYPE}" dll_location "${dll_location}")

      INSTALL(PROGRAMS ${dll_location} DESTINATION ${target}
              COMPONENT ${target}-${${prefix}_VERSION})
    ELSE(WIN32)
      INSTALL(TARGETS ${target} DESTINATION ${target}
              COMPONENT ${target}-${${prefix}_VERSION})
    ENDIF(WIN32)
    add_cpack_workaround(${target} ${${prefix}_VERSION} ${ext})
  ELSE(PACKAGE_ZIP OR PACKAGE_TGZ)
    INSTALL(TARGETS ${target} DESTINATION lib/kodi/addons/${target})
    INSTALL(DIRECTORY ${target} DESTINATION share/kodi/addons)
  ENDIF(PACKAGE_ZIP OR PACKAGE_TGZ)
endmacro()

# finds a path to a given file (recursive)
function (kodi_find_path var_name filename search_path strip_file)
  file(GLOB_RECURSE PATH_TO_FILE ${search_path} ${filename})
  if(strip_file)
    string(REPLACE ${filename} "" PATH_TO_FILE ${PATH_TO_FILE})
  endif(strip_file)
  set (${var_name} ${PATH_TO_FILE} PARENT_SCOPE)
endfunction()

# Cmake build options
include(addoptions)
include(TestCXXAcceptsFlag)
OPTION(PACKAGE_ZIP "Package Zip file?" OFF)
OPTION(PACKAGE_TGZ "Package TGZ file?" OFF)
OPTION(BUILD_SHARED_LIBS "Build shared libs?" ON)

# LTO support?
CHECK_CXX_ACCEPTS_FLAG("-flto" HAVE_LTO)
IF(HAVE_LTO)
  OPTION(USE_LTO "use link time optimization" OFF)
  IF(USE_LTO)
    add_options(ALL_LANGUAGES ALL_BUILDS "-flto")
  ENDIF(USE_LTO)
ENDIF(HAVE_LTO) 

# set this to try linking dependencies as static as possible
IF(ADDONS_PREFER_STATIC_LIBS)
  SET(CMAKE_FIND_LIBRARY_SUFFIXES .lib .a ${CMAKE_FIND_LIBRARY_SUFFIXES})
ENDIF(ADDONS_PREFER_STATIC_LIBS)

