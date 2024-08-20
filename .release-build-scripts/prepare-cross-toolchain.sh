#!/bin/bash

toolchain="$1"
if [ -z "${toolchain}" ]; then
	echo "Usage: $0 <toolchain>"
	exit 1
fi

GCC_VERSION=13.1
MUSL_VERSION=1.2.2
GLIBC_VERSION=2.39
LINUX_VERSION=6.8.10

docker_socket_owner="$(stat -c '%U' /var/run/docker.sock)"
current_user="$(whoami)"
if [[ $docker_socket_owner != "${current_user}" ]]; then
	sudo chown ${current_user}:${current_user} /var/run/docker.sock
fi

scripts_dir="$(dirname "$0")"

original_dir="$(pwd)"
if [ ! -d ./target/cross ]; then
	git clone https://github.com/cross-rs/cross --recurse-submodules target/cross
	cd target/cross
else
	cd target/cross
	git fetch
	git pull
fi

declare -A apple_sdk_urls
apple_sdk_urls=(
	["aarch64-apple-darwin"]=https://github.com/joseluisq/macosx-sdks/releases/download/12.3/MacOSX12.3.sdk.tar.xz
	["x86_64-apple-darwin"]=https://github.com/joseluisq/macosx-sdks/releases/download/12.3/MacOSX12.3.sdk.tar.xz
	["i686-apple-darwin"]=https://github.com/joseluisq/macosx-sdks/releases/download/10.13/MacOSX10.13.sdk.tar.xz
	["aarch64-apple-ios"]=https://github.com/xybp888/iOS-SDKs/releases/download/iOS17.5-SDKs/iPhoneOS17.5.sdk.zip
)

declare -A apple_sdk_files
apple_sdk_files=(
	["aarch64-apple-darwin"]=MacOSX12.3.sdk.tar.xz
	["x86_64-apple-darwin"]=MacOSX12.3.sdk.tar.xz
	["i686-apple-darwin"]=MacOSX10.13.sdk.tar.xz
	["aarch64-apple-ios"]=iPhoneOS17.5.sdk.tar.xz
)

sdk_archive="./docker/${apple_sdk_files[${toolchain}]}"
if [[ "${toolchain}" == *apple* ]] && [ ! -f "$sdk_archive" ] && [ ! -f "$(echo "${sdk_archive}" | sed 's/\.zip/.tar.xz/g')" ]; then
	file_name=$(echo ${apple_sdk_urls[${toolchain}]} | rev | cut -d '/' -f1 | rev)
	xh ${apple_sdk_urls[${toolchain}]} --download --body --continue --pretty all --style monokai --output "$sdk_archive"
	if [[ "$file_name" == *zip ]]; then
		#convert zip to tar.xz
		mkdir /tmp/$file_name
		unzip "${sdk_archive}" -d /tmp/$file_name
		tar_name="$(echo "${sdk_archive}" | sed 's/\.zip/.tar.xz/g')"
		tar -cJf "./${tar_name}" -C /tmp/$file_name .
		rm -rf /tmp/$file_name
		rm "${sdk_archive}"
	fi
fi

cargo xtask configure-crosstool ${toolchain} --gcc-version $GCC_VERSION --glibc-version $GLIBC_VERSION --musl-version $MUSL_VERSION --linux-version $LINUX_VERSION
macos_sdk_args=""
if [[ ${toolchain} == *-darwin ]]; then
	macos_sdk_args="${macos_sdk_args}--build-arg MACOS_SDK_FILE=${apple_sdk_files[${toolchain}]}"
elif [[ ${toolchain} == *-ios ]]; then
	macos_sdk_args="${macos_sdk_args}--build-arg IOS_SDK_FILE=${apple_sdk_files[${toolchain}]}"
fi
cargo build-docker-image ${toolchain}-cross --tag local $macos_sdk_args

if [ ! -f ../../Cross.toml ] || [[ "$(cat ../../Cross.toml)" != *"[target.${toolchain}]"* ]]; then
	cat <<EOF >>../../Cross.toml
[target.${toolchain}]
image = "ghcr.io/cross-rs/${toolchain}-cross:local"
EOF
fi

cd "$original_dir"
