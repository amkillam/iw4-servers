#!/bin/bash

package_name="$1"
release_targets_filter="$2"

if [ -z "$package_name" ]; then
	echo "You did not specify a package name - this will result in an error if there are more than two packages in the workspace."
	echo "USAGE: $0 <package_name> <release_targets_filter>"
fi

if [ -z $release_targets_filter ]; then
	wasm_filters='wasm\|asmjs\|emscripten\|wasi\|memory64\|function-references'
	no_std_filters='i586-pc-nto-qnx700\|powerpc-unknown-openbsd\|mipsel-sony-ps\|-none$\|none-softfloat\|none-elf\|none-eabi\|uefi\|cuda\|nintendo-switch\|atmega328\|mipsisa\|nuttx'
	special_sdk_filters='apple-ios\|apple-visionos\|apple-tvos\|apple-watchos'
	extremely_obscure_os_filters='fuchsia\|solid_asp3\|qnx710\|illumos\|teeos\|vxworks\|hermit\|-ohos'
	extremely_obscure_platform_filters='unikraft'
	extremely_obscure_arch_filters='bpfeb\|bpfel\|csky\|hexagon'
	broken_std_filters='gnu_ilp32\|aarch64_be-unknown-linux-gnu\|i586-unknown-netbsd'
	broken_cross_filters='arm-unknown-linux-gnueabi'
	no_cargo_cross_and_uncommon_filters="aarch64-unknown-netbsd\|arm64e-apple-darwin\|arm64ec-pc-windows-msvc\|haiku"
	#	other_known_broken_filters='' # TODO
	release_targets_filter="$wasm_filters\|$no_std_filters\|$special_sdk_filters\|$extremely_obscure_os_filters\|$extremely_obscure_platform_filters\|$extremely_obscure_arch_filters\|$broken_std_filters\|$broken_cross_filters\|$no_cargo_cross_and_uncommon_filters"
fi

script_dir="$(dirname $0)"
build_script="$script_dir/build-target.sh"
OLD_IFS=$IFS
export IFS=$'\n'

rm -f dist/successful_targets.txt
rm -f dist/failed_targets.txt
for target in $(rustc --print target-list | grep -vi "$release_targets_filter"); do
	echo "Building for target: $target"
	IFS=$OLD_IFS $build_script $target $package_name

	if [ -f ./dist/*${target}* ]; then
		echo "Built successfully for target: $target"
		echo "$target" >>./dist/successful_targets.txt
	else
		echo "Failed to build for target: $target"
		echo "$target" >>./dist/failed_targets.txt
	fi
done

export IFS=$OLD_IFS
