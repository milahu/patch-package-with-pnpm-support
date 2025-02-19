#! /usr/bin/env bash

set -e

cd "$(dirname "$0")"

# silent (default)
enable_debug=false
set +x # trace off
patch_package_args=

# debug
#enable_debug=true
#set -x # trace all commands # this breaks snapshots
#patch_package_args="--debug" # this breaks snapshots

# TODO better: parse arguments
if [ "$1" = "--debug" ] || [ "$1" = "-d" ]; then
  enable_debug=true
  shift # consume $1
fi

#test_script="$1"
#test_script_list="$@"
# test/patch-parse-failure.sh

# FIXME test/shrinkwrap.sh
#    Patch file: patches/left-pad+1.1.3.patch
#    Patch was made for version: 1.1.3
#    Installed version: 1.1.1

# test
test_script_list=$(cat <<'EOF'
test/adding-and-deleting-files.sh
test/broken-patch-file.sh
test/collate-errors.sh
test/custom-patch-dir.sh
test/custom-resolutions.sh
test/delete-scripts.sh
test/error-on-fail.sh
test/fails-when-no-package.sh
test/ignores-scripts-when-making-patch.sh
test/no-symbolic-links.sh
test/patch-parse-failure.sh
EOF
)

# FIXME test/scoped-package.sh - dont run "npm install"

cat >/dev/null <<EOF
todo unit test
test/pnpm-workspaces.sh
test/scoped-package.sh

ignore:

test/ignore-whitespace.sh
test/shrinkwrap.sh
test/dev-only-patches.sh
test/package-gets-updated.sh

test/create-issue.sh
test/delete-old-patch-files.sh
test/happy-path-npm.sh
test/happy-path-yarn.sh
test/unexpected-patch-creation-failure.sh
test/lerna-canary.sh
test/nested-packages.sh
test/file-mode-changes.sh
test/nested-scoped-packages.sh
test/include-exclude-regex-relativity.sh
test/yarn-workspaces.sh
test/reverse-option.sh
test/include-exclude-paths.sh

EOF

if (( $# > 0 )); then
  test_script_list="$*"
  echo "using test_script_list from argv: $test_script_list"
fi

function pkg_jq() {
  # yes i know sponge. this is portable
  cat package.json | jq "$@" >package.json.1
  mv package.json.1 package.json
}

if $enable_debug; then
function debug() {
  # 8 = dark grey
  # TODO also for "set -x" messages -> PS3?
  echo "$(tput setaf 8)$*$(tput sgr0)"
}
else
function debug(){ :; }
fi

if $enable_debug; then
function echo_on(){ :; }
function echo_off(){ :; }
else
# https://stackoverflow.com/questions/17840322/how-to-undo-exec-dev-null-in-bash
function echo_on() {
  exec 1>&5
  exec 1>&6
}

function echo_off() {
  # TODO write to logfile instead of /dev/null -> help to debug
  exec 5>&1 1>/dev/null
  exec 6>&2 2>/dev/null
}
fi
# color demo:
# for n in $(seq 0 16); do printf "$(tput setaf $n)$n$(tput sgr0) "; done; echo
# 7 = light gray
# 8 = dark gray



echo "generating *.tgz files ..."
../packages/pack.sh
echo "generating *.tgz files done"



for test_script in $test_script_list
do

#echo "$(tput setaf 6)TEST$(tput sgr0) $test_script" # cyan
#echo "$(tput setaf 11)TEST$(tput sgr0) $test_script" # yellow
#echo "TEST $test_script"
echo "./test/integration/run.sh $test_script"

if (echo "$test_script" | grep -q '\.FIXME$')
then
  echo "skip"
  echo
  continue
fi

[ -e "$test_script" ] || {
  echo "no such file: $test_script" >&2
  exit 1
}

test_name="$(basename "$test_script" .sh)"

test_script="$(readlink -f "$test_script")" # absolute path
test_script_base="${test_script%.*}"

# TODO move files to test/integration
#test_src="$(readlink -f "../../integration-tests/$test_name")"
#patches_src="$(readlink -f "../../integration-tests/$test_name/patches")"
test_src="$(readlink -f "src/$test_name")"
export TEST_SRC="$test_src"

patches_src="$(readlink -f "src/$test_name/patches")"

snapshot_index=-1

function expect_error() {
  echo_on
  expect_return "!=0" "$@"
  echo_off
}

function expect_ok() {
  echo_on
  expect_return "==0" "$@"
  echo_off
}

function expect_return() {
  snapshot_index=$((snapshot_index + 1)) # global
  local t1
  local t2
  local dt
  local name
  local rc_condition
  local rc
  local enable_snapshot=false
  rc_condition="$1"
  shift
  if [ "$1" = "-s" ]; then
    enable_snapshot=true
    shift
  fi
  name="$1"
  shift
  #git add . >/dev/null
  #git commit -m 'before expect_error' >/dev/null || true
  rc=0
  debug "exec: $*"
  t1=$(date +%s.%N)

  # run the command
  out=$("$@" 2>&1) || rc=$? # https://stackoverflow.com/questions/18621990

  t2=$(date +%s.%N)
  dt=$(echo "$t2" "$t1" | awk '{ print $1 - $2 }')
  debug "exec took $dt seconds"
  debug "rc = $rc"
  if (( "$rc" $rc_condition ))
  then
    # passed the rc check
    echo "$(tput setaf 2)PASS$(tput sgr0) $name ($rc $rc_condition)"
    #git add . >/dev/null
    #git commit -m 'after expect_error' >/dev/null || true
    #shot="$snapshot_dir/$test_name/$snapshot_index.txt"
    #shot="$test_script_base.out-$snapshot_index.txt"

    if $enable_snapshot; then

      # cleanup snapshot
      # # generated by patch-package 0.0.0 on 2022-04-13 20:43:55
      # FIXME: patch-package should have a "timeless" option (both CLI and env) -> all times are unix zero = 1970-01-01 00:00:00
      #out="$(echo "$out" | sed -E 's/^# generated by patch-package 0.0.0 on [0-9 :-]+$/# generated by patch-package 0.0.0 on 1970-01-01 00:00:00/')"
      #out="$(echo "$out" | sed -E 's/^patch-package [0-9]+\.[0-9]+\.[0-9]+$/patch-package 0.0.0/')"
      # done by setting TEST_PATCH_PACKAGE=true
      shot="$test_script.$snapshot_index.txt"
      debug "using snapshot file: $shot"
      # to update a snapshot, delete the old snapshot file
      if [ -e "$shot" ]; then
        debug comparing snapshot
        if diff -u --color <(echo "$out") "$shot" # returns 0 if equal, print diff if not equal
        then
          echo "$(tput setaf 2)PASS$(tput sgr0) $name (snapshot)"
        else
          echo "$(tput setaf 1)FAIL$(tput sgr0) $name (snapshot)"
          return 1
        fi
      else
        debug writing snapshot
        echo "writing snapshot $(basename "$shot")"
        echo "$out" >"$shot"
      fi
    fi
    return 0
  else
    # fail
    #git add . >/dev/null
    #git commit -m 'after expect_error' >/dev/null || true
    echo "$(tput setaf 1)FAIL$(tput sgr0) $name. actual $rc vs expected $rc_condition"
    if [ "$rc" = 127 ]; then
      echo  "internal error? rc=$rc can mean: command not found. maybe you forgot 'npx' before the command? command was: $*"
    fi
    echo "out: $out"
    # TODO expected $out
    return 1
  fi
}

work_dir="work/$test_name"
rm -rf "$work_dir" || true
mkdir -p "$work_dir"

debug "copying all *.tgz package files to $work_dir"
cp ../../test/packages/*.tgz "$work_dir"/

if [ -v PATCH_PACKAGE_BIN ]; then
  # was set in run-tests.sh
  debug "using env: PATCH_PACKAGE_BIN = $PATCH_PACKAGE_BIN"
else
  # this happens when run.sh is called directly, not from run-tests.sh
  PATCH_PACKAGE_BIN="$(readlink -f ../../dist/index.js)"
  debug "setting PATCH_PACKAGE_BIN = $PATCH_PACKAGE_BIN"
fi

false && {
# too slow
# only needed for test/integration/test/scoped-package.sh
if [ -v PATCH_PACKAGE_TGZ ]; then
  # was set in run-tests.sh
  debug "using env: PATCH_PACKAGE_TGZ = $PATCH_PACKAGE_TGZ"
else
  # this happens when run.sh is called directly, not from run-tests.sh
  PATCH_PACKAGE_TGZ="$(ls -t ../../patch-package.test*.tgz | head -n1)"
  PATCH_PACKAGE_TGZ="$(readlink -f $PATCH_PACKAGE_TGZ)" # TODO use latest version
  debug "setting PATCH_PACKAGE_TGZ = $PATCH_PACKAGE_TGZ"
fi
export PATCH_PACKAGE_TGZ
}

export PATCH_PACKAGE_BIN

# we must export PATCH_PACKAGE_BIN
# so it's usable in function patch_package
# otherwise calling patch_package hangs forever
export PATCH_PACKAGE_BIN

function patch_package() {
  node "$PATCH_PACKAGE_BIN" $patch_package_args "$@"
}
#export -f patch_package # not needed

function npm_install() {
  local name
  local version
  local tarfile
  local t1
  local t2
  local dt
  t1=$(date +%s.%N)
  mkdir node_modules
  #jq -r -n '{"a":"a a a","b":2} | to_entries | .[] | @sh "title=\(.key) v=\(.value)"' package.json
  jq -r '.dependencies | to_entries | .[] | @sh "name=\(.key) version=\(.value)"' package.json | while read -r spec; do
    name=
    version=
    eval "$spec" # set name and version
    mkdir "node_modules/$name"
    tarfile="${version:5}" # remove the "file:" prefix
    debug "npm_install: installing $name@$version"
    tar -x --strip-components=1 -f "$tarfile" -C "node_modules/$name"
  done
  t2=$(date +%s.%N)
  dt=$(echo "$t2" "$t1" | awk '{ print $1 - $2 }')
  touch package-lock.json # for detectPackageManager.ts
  debug "npm_install: took $dt seconds"
}
#time npm_install
#time npm install
#time pnpm install
#
# benchmark
#
# this: 0.016 sec = 100x faster than npm 0__o
# npm: 1.850 sec
# pnpm: 2.420 sec

(
cd "$work_dir"

debug "copying package.json for this test"
cp "$test_src/package.json" .

#debug "copying package-lock.json for this test"
#cp "$test_src/package-lock.json" . || true



#debug "copying *.tgz package files for this test:"
#(
#  # debug
#  cd "$test_src"
#  find . -maxdepth 1 -name '*.tgz' -type f | while read -r f; do f="${f:2}"; debug "$f"; done
#)
#cp "$test_src"/*.tgz . || true

if [ -d "$patches_src" ]; then
  debug "copying patches for this test:"
  (
    # debug
    cd "$test_src"
    find patches/ -type f | while read -r f; do debug "$f"; done
  )
  cp -r "$patches_src" .
fi

#git add . >/dev/null
#git commit -m before >/dev/null || true



# prepare

# for makePatch.ts: set patch-package version to 0.0.0
export TEST=true

export CI=true # needed so patch-package returns 1 on error
# see shouldExitWithError in applyPatches.ts
# see run-tests.sh
# FIXME? patch-package should always return 1 on error
# tests:
# test/fails-when-no-package.sh
# test/broken-patch-file.sh
# ...

export NODE_ENV="" # test/error-on-fail.sh sets NODE_ENV="development"

export TEST_PATCH_PACKAGE="true"
# -> isTest == true

#npm install



# run

t1=$(date +%s.%N)

debug "writing logfile $test_script.log"
debug "sourcing $test_script ..."
echo_off

# run test
source "$test_script"

echo_on
debug "sourcing $test_script done"

t2=$(date +%s.%N)
dt=$(echo "$t2" "$t1" | awk '{ print $1 - $2 }')
debug "test took $dt seconds"

#git add . >/dev/null
#git commit -m after >/dev/null || true

# TODO
)

echo # empty line after each test

done

echo "$(tput setaf 2)PASS ALL$(tput sgr0)"

