#!/bin/bash

target="$1"
package_name="$2"
if [ -z "$target" ]; then
	echo "Usage: $0 <target> <package_name>"
	exit 1
fi

if [ -z "$package_name" ]; then
	package_name="$(cargo metadata --format-version 1 | jq -r '.packages[].targets[] | select( .kind | map(. == "bin") | any ) | select ( .src_path | contains(".cargo/registry") | . != true ) | .name')"
	if [ -z "$package_name" ]; then
		echo "Failed to determine package name."
		exit 1
	elif [ "$(echo $package_name | wc -l)" -gt 1 ]; then
		echo "Multiple targets found. Please specify the target name."
		exit 1
	fi
fi

image_exists() {
	container_name="$1"
	docker_image_instances=$(docker image ls | grep -v "${container_name}[a-zA-Z]" | grep "$container_name")

	if [[ "$docker_image_instances" != "" ]]; then
		echo 1
	else
		echo 0
	fi
}

declare -a special_cross_toolchains
special_cross_toolchains=(
	"aarch64-apple-darwin"
	"aarch64-apple-ios"
	"aarch64-pc-windows-msvc"
	"aarch64_be-unknown-linux-gnu"
	"i686-apple-darwin"
	"i686-pc-windows-msvc"
	"s390x-unknown-linux-gnu"
	"thumbv7a-pc-windows-msvc"
	"thumbv7neon-unknown-linux-musleabihf"
	"x86_64-apple-darwin"
	"x86_64-pc-windows-msvc"
	"aarch64-unknown-linux-musl"
	"armeb-unknown-linux-gnueabi"
	"loongarch64-unknown-linux-gnu"
	"mips-unknown-linux-gnu"
	"mips64-unknown-linux-gnuabi64"
	"mips64-unknown-linux-muslabi64"
	"mips64el-unknown-linux-muslabi64"
	"arm-unknown-linux-musleabi"
)
cross_toolchain_generation_script="$(dirname "$0")/prepare-cross-toolchain.sh"

LIBWINDOWS_VERSION="0.52.0"

build_profile="release"
build_out_dir="$build_profile"

if [ -z $IW4_SERVERS_RELEASE_NO_CLEAN ]; then
	rm -rf "./target/${build_out_dir}"
	rm -rf "./target/${build_out_dir}"
fi
DIST_BUILD_DIR="./dist"
mkdir -p "${DIST_BUILD_DIR}"
mkdir -p ./target

case "$target" in
*msvc*)
	arch=$(echo $target | cut -d '-' -f 1)
	xwin_arch="$arch"

	if [[ "$arch" == "i586" ]]; then
		echo "Warning: i586 is not supported by xwin."
		xwin_arch="x86"
	elif [[ "$arch" == "i686" ]]; then
		xwin_arch="x86"
	elif [[ "$arch" == "thumbv7a" ]]; then
		xwin_arch="aarch"
	fi

	ln -sf "$HOME/.cache/cargo-xwin/xwin/sdk/lib/ucrt/aarch" "$HOME/.cache/cargo-xwin/xwin/sdk/lib/ucrt/thumbv7a"
	ln -sf "$HOME/.cache/cargo-xwin/xwin/sdk/lib/um/aarch" "$HOME/.cache/cargo-xwin/xwin/sdk/lib/um/thumbv7a"
	ln -sf "$HOME/.cache/cargo-xwin/xwin/crt/lib/aarch" "$HOME/.cache/cargo-xwin/xwin/crt/lib/thumbv7a"

	cd ./target
	xh --pretty all --style monokai --download --body https://github.com/microsoft/windows-rs/archive/refs/tags/0.52.0.tar.gz --output "./${LIBWINDOWS_VERSION}.tar.gz"
	tar xvf "./${LIBWINDOWS_VERSION}.tar.gz" && rm "./${LIBWINDOWS_VERSION}.tar.gz"
	cd "./windows-rs-${LIBWINDOWS_VERSION}"

	cargo xwin build --target "${target}" -Zbuild-std=std,core,alloc,panic_abort --xwin-arch x86_64,x86,aarch64 --xwin-variant desktop --package windows --release
	cp ./target/${target}/release/libwindows.rlib ../../windows.${LIBWINDOWS_VERSION}.lib
	cd ../../

	cargo xwin build --target "${target}" --profile "$build_profile" -Zbuild-std=std,core,alloc,panic_abort,compiler_builtins,proc_macro --package $package_name --xwin-arch "$xwin_arch" --xwin-variant desktop

	rm ./windows.${LIBWINDOWS_VERSION}.lib
	if [ $? -ne 0 ]; then
		echo "Failed to build target $target."
	else
		llvm-strip --strip-all "./target/${target}/${build_out_dir}/${package_name}.exe"
		cp "./target/${target}/${build_out_dir}/${package_name}.exe" "${DIST_BUILD_DIR}/${package_name}-${target}.exe"
	fi
	;;
*redox*)
	[[ "$(redoxer version 2>/dev/null)" != "0.2.44" ]] && cargo install --force --git https://github.com/amkillam/redoxer redoxer

	TARGET="${target}" redoxer build --target "${target}" --profile "${build_profile}" --package "$package_name" -Zbuild-std=std,core,alloc,panic_abort,compiler_builtins,proc_macro
	if [ $? -ne 0 ]; then
		echo "Failed to build target $target."
	else
		llvm-strip --strip-all "./target/${target}/${build_out_dir}/${package_name}"
		cp "./target/${target}/${build_out_dir}/${package_name}" "${DIST_BUILD_DIR}/${package_name}-${target}"
	fi
	;;
*)
	real_work_dir="$(pwd)"

	if [ $(image_exists "cargo-cross:latest") -eq 0 ]; then
		docker build ./ -t cargo-cross -f "$(dirname "$0")/Dockerfile"
	fi

	if [ $(echo "${special_cross_toolchains[@]}" | grep -oP "((?<=^)|(?<= ))${target}(?=( |\$))" | wc -l) -gt 0 ]; then
		if [ ! -f "$cross_toolchain_generation_script" ]; then
			echo "Cross toolchain generation script not found."
			exit 1
		elif [ ! -x "$cross_toolchain_generation_script" ]; then
			chmod +x "$cross_toolchain_generation_script"
		fi
		if [ $(image_exists "ghcr.io/cross-rs/${toolchain}-cross:local") -eq 0 ] && [ $(image_exists "ghcr.io/cross-rs/${toolchain}:latest") -eq 0 ]; then
			echo "Generating cross toolchain for target $target."
			"$cross_toolchain_generation_script" "$target"
		fi
	fi

	build_std="-Zbuild-std=std,core,alloc,panic_abort,compiler_builtins,proc_macro"
	cross_build_zig=""
	if [[ "$target" == *gnu* ]] && [[ "$target" != *riscv64gc* ]] &&
		[[ "$target" != sparc* ]] && [[ "$target" != thumbv7neon* ]] &&
		[[ "$target" != armeb* ]] && [[ "$target" != armv4t* ]] &&
		[[ "$target" != mipsel* ]] && [[ "$target" != armv5te* ]] &&
		[[ "$target" != *-windows-* ]] && [[ "$target" != s390x* ]]; then
		cross_build_zig="CROSS_BUILD_ZIG=2.15 "
	fi

	if [[ "$target" == *windows-gnu* ]]; then
		rustc --target=${target} --emit=obj -o ./target/rsbegin.o $(rustc --print sysroot)/lib/rustlib/src/rust/library/rtstartup/rsbegin.rs
		rustc --target=${target} --emit=obj -o ./target/rsend.o $(rustc --print sysroot)/lib/rustlib/src/rust/library/rtstartup/rsend.rs
	fi

	docker run -v /var/run/docker.sock:/var/run/docker.sock \
		-v .:"$real_work_dir" \
		-w "$real_work_dir" cargo-cross bash -c \
		"cd ./target && ${cross_build_zig}CROSS_CONTAINER_OPTS=\"-w $real_work_dir\" cross build --target ${target} --profile ${build_profile} --package $package_name $build_std "

	rm -f ./target/rsbegin.o ./target/rsend.o
	binary_extension=""
	if [[ "$target" == *windows* ]]; then
		binary_extension=".exe"
	fi
	package_out="./target/${target}/${build_out_dir}/${package_name}${binary_extension}"
	if [ ! -f "$package_out" ]; then
		echo "Failed to build target $target."
	else
		llvm-strip --strip-all "$package_out"
		cp "$package_out" "${DIST_BUILD_DIR}/${package_name}-${target}${binary_extension}"
	fi
	;;
esac
rm -rf ./target
