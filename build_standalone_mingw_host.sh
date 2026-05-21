#!/bin/bash
# Cross-compile hdc for Windows (x86_64) using MinGW on Linux
# Usage: cd ~/oh6/source && ./developtools/hdc/scripts/build_standalone_mingw_host.sh ~/oh6/source

set -e

CROSS=x86_64-w64-mingw32
CC=${CROSS}-gcc-posix
CXX=${CROSS}-g++-posix
AR=${CROSS}-ar
RANLIB=${CROSS}-ranlib

ohos_root=$1
ohos_hdc_build="ohos_hdc_build_win"
cwddir=$(pwd)

build_in_source=true
[ "X$ohos_root" == "X" ] && build_in_source=false

if [ "$build_in_source" == "true" ] ; then
	ohos_root_real=$(realpath $ohos_root)
fi

[ "X$KEEP" == "X" ] && [ -d "$ohos_hdc_build" ] && rm -fr $ohos_hdc_build
[ -d "$ohos_hdc_build" ] || mkdir $ohos_hdc_build

STATICLIB=""
INCLUDES=""

function build_libusb ()
{
	libusb_install=$(realpath libusb_win)
	[ "X$KEEP" == "X" ] && mkdir -pv ${libusb_install}/include ${libusb_install}/build
	if [ "$build_in_source" == "true" ] && [ -f "${ohos_root_real}/third_party/libusb/libusb-1.0.28.tar.gz" ]; then
		if [ "X$KEEP" == "X" ] || [ ! -f "${libusb_install}/libusb.a" ]; then
			"${ohos_root_real}/third_party/libusb/install.sh" "${libusb_install}/build" "${ohos_root_real}/third_party/libusb"
			pushd "${libusb_install}/build/libusb-1.0.28"
			${CC} -fPIC -DPLATFORM_WINDOWS \
				-Ilibusb -Ilibusb/os -I"${ohos_root_real}/third_party/libusb/windows" \
				-c \
				libusb/core.c \
				libusb/descriptor.c \
				libusb/hotplug.c \
				libusb/io.c \
				libusb/sync.c \
				libusb/strerror.c \
				libusb/os/events_windows.c \
				libusb/os/threads_windows.c \
				libusb/os/windows_common.c \
				libusb/os/windows_usbdk.c \
				libusb/os/windows_winusb.c
			${AR} rcs "${libusb_install}/libusb.a" *.o
			popd
		fi
		ln -svf "${libusb_install}/build/libusb-1.0.28/libusb" ${libusb_install}/include/libusb
		STATICLIB+="$(realpath ${libusb_install}/libusb.a) "
	else
		echo "ERROR: libusb source not found, cross-compile requires OH source tree"
		exit 1
	fi
	INCLUDES+="-I$(realpath ${libusb_install}/include) "
	INCLUDES+="-I$(realpath ${libusb_install}/include/libusb) "
}

function build_openssl ()
{
	pushd third_party_openssl
	if [ "X$KEEP" == "X" ]; then
		./Configure no-shared mingw64 --cross-compile-prefix=${CROSS}- && make CC=${CC} AR=${AR} RANLIB=${RANLIB}
	fi
	STATICLIB+="$(realpath libssl.a) "
	STATICLIB+="$(realpath libcrypto.a) "
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_libuv ()
{
	pushd third_party_libuv
	if [ "X$KEEP" == "X" ]; then
		mkdir -p build_win && cd build_win
		cmake -DCMAKE_SYSTEM_NAME=Windows \
			-DCMAKE_C_COMPILER=${CC} \
			-DCMAKE_CXX_COMPILER=${CXX} \
			-DCMAKE_AR=$(which ${AR}) \
			-DCMAKE_RANLIB=$(which ${RANLIB}) \
			-DBUILD_TESTING=OFF \
			-DLIBUV_BUILD_TESTS=OFF \
			-DLIBUV_BUILD_BENCH=OFF \
			..
		make uv_a
		cd ..
	fi
	if ! nm build_win/libuv.a 2>/dev/null | grep -q "uv__log_impl"; then
		${CC} -Iinclude -Isrc -c src/win/log_win.c src/win/trace_win.c
		${AR} rcs build_win/libuv.a log_win.o trace_win.o
		[ -f build_win/libuv_a.a ] && ${AR} rcs build_win/libuv_a.a log_win.o trace_win.o
	fi
	if [ -f build_win/libuv_a.a ]; then
		STATICLIB+="$(realpath build_win/libuv_a.a) "
	elif [ -f build_win/libuv.a ]; then
		STATICLIB+="$(realpath build_win/libuv.a) "
	fi
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_securec ()
{
	pushd third_party_bounds_checking_function
	[ "X$KEEP" == "X" ] && ${CC} src/*.c -I$(pwd)/include -c && ${AR} rcs libsecurec.a *.o
	STATICLIB+="$(realpath libsecurec.a) "
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_lz4 ()
{
	pushd third_party_lz4/lib
	if [ "X$KEEP" == "X" ] || [ ! -f liblz4.a ]; then
		${CC} -O3 -c lz4.c lz4hc.c lz4frame.c xxhash.c
		${AR} rcs liblz4.a lz4.o lz4hc.o lz4frame.o xxhash.o
	fi
	STATICLIB+="$(realpath liblz4.a) "
	INCLUDES+="-I$(realpath .) "
	popd
}

function build_hdc ()
{
	pushd developtools_hdc
	echo $STATICLIB
	echo $INCLUDES

	DEFINES=(
		-DHDC_HOST
		-DHARMONY_PROJECT
		-DHOST_MINGW
		-D_WIN32
		-DUSE_CONFIG_UV_THREADS
		-DSIZE_THREAD_POOL=128
		-DOPENSSL_SUPPRESS_DEPRECATED
		-DHDC_SUPPORT_ENCRYPT_TCP
		-DHDC_SUPPORT_UART
		-DTEST_HASH
		'-DHDC_MSG_HASH="TEST"'
		-D__FILE_NAME__=__FILE__
	)
	export CXXFLAGS="-std=c++17 -ggdb -O0 -fpermissive -D_WIN32_WINNT=0x0600"

	HDC_SOURCES="
		src/common/async_cmd.cpp
		src/common/auth.cpp
		src/common/base.cpp
		src/common/channel.cpp
		src/common/circle_buffer.cpp
		src/common/compress.cpp
		src/common/debug.cpp
		src/common/decompress.cpp
		src/common/entry.cpp
		src/common/file.cpp
		src/common/file_descriptor.cpp
		src/common/forward.cpp
		src/common/header.cpp
		src/common/heartbeat.cpp
		src/common/server_cmd_log.cpp
		src/common/session.cpp
		src/common/hdc_ssl.cpp
		src/common/task.cpp
		src/common/tcp.cpp
		src/common/tlv.cpp
		src/common/transfer.cpp
		src/common/usb.cpp
		src/common/uv_status.cpp
		src/common/uart.cpp
		src/host/client.cpp
		src/host/ext_client.cpp
		src/host/host_app.cpp
		src/host/host_forward.cpp
		src/host/host_shell_option.cpp
		src/host/host_ssl.cpp
		src/host/host_tcp.cpp
		src/host/host_unity.cpp
		src/host/host_updater.cpp
		src/host/host_usb.cpp
		src/host/host_uart.cpp
		src/host/main.cpp
		src/host/server.cpp
		src/host/server_for_client.cpp
		src/host/translate.cpp
	"
	${CXX} "${DEFINES[@]}" ${CXXFLAGS} -Isrc/common -Isrc/host ${INCLUDES} ${HDC_SOURCES} \
		$STATICLIB \
		-lws2_32 -lshlwapi -liphlpapi -lsetupapi -lole32 -luserenv -ldbghelp -lcrypt32 -lbcrypt \
		-lpthread -latomic -static \
		-o hdc_std.exe

	if [ -f hdc_std.exe ]; then
		echo build success
		cp hdc_std.exe $cwddir
	else
		echo build fail
	fi
	popd
}

pushd $ohos_hdc_build

if [ "X$KEEP" == "X" ]; then
	for name in "developtools/hdc" "third_party/libuv" "third_party/openssl" "third_party/bounds_checking_function" "third_party/lz4"; do
		reponame=$(echo $name | sed "s/\//_/g")
		if [ "$build_in_source" == "true" ] ; then
			cp -ra ${ohos_root_real}/${name} ${reponame} || exit 1
		else
			git clone https://gitee.com/openharmony/${reponame}
		fi
	done
fi

build_openssl
build_libuv
build_securec
build_lz4
build_libusb

build_hdc

popd
