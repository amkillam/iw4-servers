#!/bin/bash

let package_name="$1"

if [ -z "$package_name" ]; then
	echo "You did not specify a package name - this will result in an error if there are more than two packages in the workspace."
	echo "USAGE: $0 <package_name>"
fi

script_dir="$(dirname $0)"
build_script="$script_dir/build-target.sh"
OLD_IFS=$IFS
export IFS=$'\n'

rm dist/successful_targets.txt
rm dist/failed_targets.txt
for target in $(rustc --print target-list); do
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
