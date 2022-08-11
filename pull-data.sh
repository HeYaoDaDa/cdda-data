#!/usr/bin/env zsh
set -eo pipefail

echo "Fetching release list..."

release_json="$(curl -sL https://api.github.com/repos/CleverRaven/Cataclysm-DDA/releases)"

latest_build_number="$(jq -r '.[0].tag_name' <<< "$release_json" | cut -db -f2)"
echo '{"latest_build":"'"$latest_build_number"'"}' > latest-build.json

for i in {0..$(jq -r 'length - 1' <<< "$release_json")}; do
  # .tarball_url exists in the api response, but it's not urlencoded so it
  # 400s if there are non-ascii chars. hack around it by constructing the
  # tarball url manually and urlencoding the tag name.
  tarball_url="$(jq -r '@uri "https://api.github.com/repos/CleverRaven/Cataclysm-DDA/tarball/\(.['"$i"'].tag_name)"' <<< "$release_json")"
  tag_name="$(jq -r ".[$i].tag_name" <<< "$release_json")"
  build_number="$(cut -db -f2 <<< "$tag_name")"
  if [ 'cdda-experimental-2021-07-09-1837' = "$build_number" ]; then  # this release had broken json
    continue
  fi
  if [ 'cdda-experimental-2021-07-09-1719' = "$build_number" ]; then
    continue
  fi

  if [ ! -f "data/$build_number/all.json" ]; then
    echo "Fetching source for build $build_number..."
    mkdir -p "data/$build_number/src" && cd "data/$build_number/src"
    curl -sL "$tarball_url" | tar xz --strip-components=1

    echo "Collating JSON..."

    jq -n -c '{build_number: "'"$build_number"'", release: input['"$i"'], data: [inputs | .[] | .__filename = input_filename]}' /dev/stdin data/json/**/*.json <<< "$release_json" > ../all.json

    echo "Compiling lang JSON..."

    mkdir ../lang
    for po_file in lang/po/*.po; do
      npx gettext.js $po_file ../lang/$(basename ${po_file} .po).json
    done

    echo "Cleaning up..."

    cd ..
    rm -rf src
    cd ../..
  fi
done

echo "Collecting info from all builds..."
(
  cd data
  for build_number in *; do
    if [ "$build_number" = "latest" ]; then continue; fi
    prerelease="$(jq -n --stream 'first(inputs | select(.[0] == ["release", "prerelease"])) | .[1]' "$build_number"/all.json)"
    created_at="$(jq -n --stream 'first(inputs | select(.[0] == ["release", "created_at"])) | .[1]' "$build_number"/all.json)"
    langs="$(find "$build_number"/lang -type f -exec basename {} .json \; | jq -cR '[inputs]' || echo '[]')"
    echo '{"build_number": "'"$build_number"'", "prerelease": '"$prerelease"', "created_at": '"$created_at"', "langs": '"$langs"'}'
  done
) | jq -n '[inputs] | sort_by(.created_at) | reverse' >| builds.json

mkdir -p data/latest
ln -f data/"$latest_build_number"/all.json data/latest/all.json
mkdir -p data/latest/lang
for lang_json in data/"$latest_build_number"/lang/*.json; do
  ln -f "$lang_json" data/latest/lang/"$(basename "$lang_json")"
done
