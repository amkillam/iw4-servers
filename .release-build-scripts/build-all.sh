#!/bin/bash

package_name="$1"
release_targets_filter="$2"

if [ -z "$package_name" ]; then
	echo "WARNING: You did not specify a package name - this will result in an error if there are more than two packages in the workspace."
	echo "USAGE: $0 <package_name> <release_targets_filter>"

	package_name="$(cargo metadata --format-version 1 | jq -r '.packages[].targets[] | select( .kind | map(. == "bin") | any ) | select ( .src_path | contains(".cargo/registry") | . != true ) | .name')"
fi

if [ -z $release_targets_filter ]; then
	wasm_filters='wasm\|asmjs\|emscripten\|wasi\|memory64\|function-references'
	no_std_filters='i586-pc-nto-qnx700\|mipsel-sony-ps\|-none$\|none-softfloat\|none-elf\|none-eabi\|uefi\|cuda\|nintendo-switch\|atmega328\|mipsisa\|nuttx\|arm-none-eabi-gcc'
	special_sdk_filters='apple-ios\|apple-visionos\|apple-tvos\|apple-watchos\|vita\|nintendo-3ds'
	extremely_obscure_os_filters='fuchsia\|solid_asp3\|qnx710\|aarch64-unknown-illumos\|teeos\|vxworks\|riscv64gc-unknown-hermit\|-ohos\|xous-elf\|hurd\|linux-sde'
	extremely_obscure_platform_filters='unikraft'
	extremely_obscure_arch_filters='bpfeb\|bpfel\|csky\|hexagon'
	broken_std_filters='gnu_ilp32\|aarch64_be-unknown-linux-gnu'
	broken_cross_filters='arm-unknown-linux-gnueabi'
	broken_glibc_filters='uclibc'
	no_cargo_cross_and_uncommon_filters='aarch64_be-unknown-netbsd\|arm64e-apple-darwin\|arm64ec-pc-windows-msvc\|riscv64gc-unknown-linux-musl\|x86_64-fortanix-unknown-sgx\|haiku\|powerpc64-ibm-aix\|powerpc64-unknown-netbsd\|powerpc64-unknown-linux-musl\|powerpc64le-unknown-linux-musl\|riscv32gc-unknown-linux-gnu\|riscv32gc-unknown-linux-musl\|riscv32im-risc0-zkvm-elf\|riscv32imac-esp-espidf\|riscv32imafc-esp-espidf\|riscv32imc-esp-espidf\|riscv64-linux-android\|riscv64gc-unknown-freebsd\|riscv64gc-unknown-netbsd\|s390x-unknown-linux-musl\|sparc-unknown-linux-gnu\|x86_64-uwp-windows-gnu\|x86_64h-apple-darwin\|xtensa-esp32-espidf\|xtensa-esp32s2-espidf\|x86_64-unknown-linux-gnux32\|thumbv7neon-unknown-linux-musleabihf\|loongarch64-unknown-linux-musl\|armv6-unknown-freebsd\|armv7-unknown-freebsd\|armv4t-unknown-linux-gnueabi\|armv5te-unknown-linux-gnueabi\|xtensa-esp32s3-espidf\|i686-uwp-windows-gnu'
	no_cargo_cross_to_be_fixed_filters='i686-apple-darwin\|aarch64-unknown-linux-musl'
	release_targets_filter="$wasm_filters\|$no_std_filters\|$special_sdk_filters\|$extremely_obscure_os_filters\|$extremely_obscure_platform_filters\|$extremely_obscure_arch_filters\|$broken_std_filters\|$broken_cross_filters\|$no_cargo_cross_and_uncommon_filters\|$broken_glibc_filters\|$no_cargo_cross_to_be_fixed_filters"
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

	if [ -f "./dist/${package_name}-${target}" ] || [ -f "./dist/${package_name}-${target}.exe" ]; then
		echo "Built successfully for target: $target"
		echo "$target" >>./dist/successful_targets.txt
	else
		echo "Failed to build for target: $target"
		echo "$target" >>./dist/failed_targets.txt
	fi
done

export IFS=$OLD_IFS
