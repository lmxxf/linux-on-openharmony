#!/bin/bash
# Copyright (C) 2021 Huawei Device Co., Ltd.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# gcc-9 needed
set -e

ohos_root=$1
ohos_hdc_build="ohos_hdc_build"
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
	libusb_install=$(realpath libusb)
	[ "X$KEEP" == "X" ] && mkdir -pv ${libusb_install}/include ${libusb_install}/build
	if [ "$build_in_source" == "true" ] && [ -f "${ohos_root_real}/third_party/libusb/libusb-1.0.28.tar.gz" ]; then
		if [ "X$KEEP" == "X" ] || [ ! -f "${libusb_install}/libusb.a" ]; then
			"${ohos_root_real}/third_party/libusb/install.sh" "${libusb_install}/build" "${ohos_root_real}/third_party/libusb"
			pushd "${libusb_install}/build/libusb-1.0.28"
			gcc -fPIC -DPLATFORM_POSIX -U__ANDROID__ -UUSE_UDEV \
				-Ilibusb -Ilibusb/os -I"${ohos_root_real}/third_party/libusb/linux" \
				-c \
				libusb/core.c \
				libusb/descriptor.c \
				libusb/hotplug.c \
				libusb/io.c \
				libusb/sync.c \
				libusb/strerror.c \
				libusb/os/events_posix.c \
				libusb/os/linux_netlink.c \
				libusb/os/linux_usbfs.c \
				libusb/os/threads_posix.c
			ar rcs "${libusb_install}/libusb.a" *.o
			popd
		fi
		ln -svf "${libusb_install}/build/libusb-1.0.28/libusb" ${libusb_install}/include/libusb
		STATICLIB+="$(realpath ${libusb_install}/libusb.a) "
	else
		ln -svf /usr/include/libusb-1.0 ${libusb_install}/include/libusb
		STATICLIB+="-lusb-1.0 "
	fi
	INCLUDES+="-I$(realpath ${libusb_install}/include) "
	INCLUDES+="-I$(realpath ${libusb_install}/include/libusb) "
}

function build_openssl ()
{
	pushd third_party_openssl
	[ "X$KEEP" == "X" ] && ./Configure no-shared linux-generic64 && make
	STATICLIB+="$(realpath libssl.a) "
	STATICLIB+="$(realpath libcrypto.a) "
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_libuv ()
{
	pushd third_party_libuv
	[ "X$KEEP" == "X" ] && cmake -DBUILD_TESTING=OFF -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF . && make uv_a
	if [ "X$KEEP" == "X" ] || ! nm libuv.a | grep -q "uv__log_impl"; then
		gcc -fPIC -Iinclude -Isrc -c src/unix/log_unix.c src/unix/trace_unix.c
		ar rcs libuv.a log_unix.o trace_unix.o
		[ -f libuv_a.a ] && ar rcs libuv_a.a log_unix.o trace_unix.o
	fi
	if [ -f libuv_a.a ]; then
		STATICLIB+="$(realpath libuv_a.a) "
	else
		STATICLIB+="$(realpath libuv.a) "
	fi
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_securec ()
{
	pushd third_party_bounds_checking_function
	[ "X$KEEP" == "X" ] && gcc src/*.c -I$(pwd)/include -c && ar rcs libsecurec.a *.o
	STATICLIB+="$(realpath libsecurec.a) "
	INCLUDES+="-I$(realpath include) "
	popd
}

function build_lz4 ()
{
	pushd third_party_lz4
	[ "X$KEEP" == "X" ] && make liblz4.a
	STATICLIB+="$(realpath lib/liblz4.a) "
	INCLUDES+="-I$(realpath lib) "
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
		-DHOST_LINUX
		-DUSE_CONFIG_UV_THREADS
		-DSIZE_THREAD_POOL=128
		-DOPENSSL_SUPPRESS_DEPRECATED
		-DHDC_SUPPORT_ENCRYPT_TCP
		-DHDC_SUPPORT_UART
		-DTEST_HASH
		'-DHDC_MSG_HASH="TEST"'
		-D__FILE_NAME__=__FILE__
	)
	export LDFLAGS="-Wl,--copy-dt-needed-entries"
	export CXXFLAGS="-std=c++17 -ggdb -O0"

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
	g++ "${DEFINES[@]}" ${CXXFLAGS} -Isrc/common -Isrc/host ${INCLUDES} ${HDC_SOURCES} -ldl -lrt -latomic -lpthread $STATICLIB -o hdc_std

	if [ -f hdc_std ]; then
		echo build success
		cp hdc_std $cwddir
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
