include(FetchContent)

function(disable_msvc_warnings target_name)
	if(MSVC AND TARGET ${target_name})
		target_compile_options(${target_name} PRIVATE /wd4244 /wd4267 /wd4305 /wd4996)
	endif()
endfunction()

FetchContent_Declare(
	midifile_source
	URL https://github.com/craigsapp/midifile/archive/refs/heads/master.zip
)

FetchContent_Declare(
	tinysoundfont_source
	URL https://github.com/schellingb/TinySoundFont/archive/refs/heads/main.zip
)

FetchContent_GetProperties(midifile_source)
if(NOT midifile_source_POPULATED)
	FetchContent_Populate(midifile_source)
endif()

FetchContent_GetProperties(tinysoundfont_source)
if(NOT tinysoundfont_source_POPULATED)
	FetchContent_Populate(tinysoundfont_source)
endif()

set(MIDIFILE_ROOT "${midifile_source_SOURCE_DIR}")
set(TINYSOUNDFONT_ROOT "${tinysoundfont_source_SOURCE_DIR}")

add_library(midifile STATIC
	"${MIDIFILE_ROOT}/src/Binasc.cpp"
	"${MIDIFILE_ROOT}/src/MidiEvent.cpp"
	"${MIDIFILE_ROOT}/src/MidiEventList.cpp"
	"${MIDIFILE_ROOT}/src/MidiFile.cpp"
	"${MIDIFILE_ROOT}/src/MidiMessage.cpp"
)

target_compile_features(midifile PUBLIC cxx_std_17)
target_include_directories(midifile PUBLIC "${MIDIFILE_ROOT}/include")
set_target_properties(midifile PROPERTIES POSITION_INDEPENDENT_CODE ON)
disable_msvc_warnings(midifile)

add_library(extension SHARED extension.cpp)

set_target_properties(extension PROPERTIES
	OUTPUT_NAME "midisf2"
	SUFFIX ".hdll"
)

target_compile_features(extension PRIVATE cxx_std_17)
target_include_directories(extension PRIVATE
	"${MIDIFILE_ROOT}/include"
	"${TINYSOUNDFONT_ROOT}"
)

if(WIN32)
	target_include_directories(extension PRIVATE "$ENV{HASHLINK}/include")
	target_link_libraries(extension PRIVATE "$ENV{HASHLINK}/libhl.lib" winmm)
endif()

target_link_libraries(extension PRIVATE midifile)
disable_msvc_warnings(extension)
