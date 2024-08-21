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
	"x86_64-unknown-linux-gnu-sde"
)
cross_toolchain_generation_script="$(dirname "$0")/prepare-cross-toolchain.sh"

build_profile="release"
build_out_dir="$build_profile"

if [ -z $IW4_SERVERS_RELEASE_NO_CLEAN ]; then
	rm -rf "./target/${build_out_dir}"
	rm -rf "./target/${build_out_dir}"
fi
DIST_BUILD_DIR="./dist"
mkdir -p "${DIST_BUILD_DIR}"

case "$target" in
*msvc*)
	cargo xwin build --target ${target} --profile "$build_profile" -Zbuild-std=std,core,panic_abort --package $package_name
	if [ $? -ne 0 ]; then
		echo "Failed to build target $target."
	else
		llvm-strip --strip-all "./target/${target}/${build_out_dir}/${package_name}.exe"
		cp "./target/${target}/${build_out_dir}/${package_name}.exe" "${DIST_BUILD_DIR}/${package_name}-${target}.exe"
	fi
	;;
*redox*)
	redoxer build --target ${target} --profile ${build_profile} --package $package_name -Zbuild-std=std,core,alloc,panic_abort
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

	if [ $(echo "${special_cross_toolchains[@]}" | grep -v "${target}[a-zA-Z]" | grep -v "${target}-" | grep -v "[a-zA-Z]${target}" | grep -v "\-${target}" | grep -c "$target") -gt 0 ]; then
		if [ ! -f "$cross_toolchain_generation_script" ]; then
			echo "Cross toolchain generation script not found."
			exit 1
		fi
		if [ ! -x "$cross_toolchain_generation_script" ]; then
			chmod +x "$cross_toolchain_generation_script"
		fi
		if [ $(image_exists "ghcr.io/cross-rs/${toolchain}-cross:local") -eq 0 ] && [ $(image_exists "ghcr.io/cross-rs/${toolchain}:latest") -eq 0 ]; then
			echo "Generating cross toolchain for target $target."
			"$cross_toolchain_generation_script" "$target"
		fi
	fi

	build_std="-Zbuild-std=std,core,alloc,panic_abort"
	cross_build_zig=""
	if [[ "$target" == *gnu* ]] && [[ "$target" != *riscv64gc* ]] && [[ "$target" != sparc* ]] && [[ "$target" != thumbv7neon* ]]; then
		cross_build_zig="CROSS_BUILD_ZIG=2.15 "
	fi

	docker run -v /var/run/docker.sock:/var/run/docker.sock \
		-v .:"$real_work_dir" \
		-w "$real_work_dir" cargo-cross bash -c \
		"${cross_build_zig}CROSS_CONTAINER_OPTS=\"-w $real_work_dir\" cross build --target ${target} --profile ${build_profile} --package $package_name $build_std"

	package_out="./target/${target}/${build_out_dir}/${package_name}"
	if [[ "$target" == *windows* ]]; then
		package_out="${package_out}.exe"
	fi
	if [ ! -f "$package_out" ]; then
		echo "Failed to build target $target."
	else
		llvm-strip --strip-all "$package_out"
		cp "$package_out" "${DIST_BUILD_DIR}/${package_name}-${target}${binary_extension}"
	fi
	;;
esac
