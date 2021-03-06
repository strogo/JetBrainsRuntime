#!/bin/bash -x

# The following parameters must be specified:
#   JBSDK_VERSION    - specifies the current version of OpenJDK e.g. 11_0_6
#   JDK_BUILD_NUMBER - specifies the number of OpenJDK build or the value of --with-version-build argument to configure
#   build_number     - specifies the number of JetBrainsRuntime build
#   bundle_type      - specifies bundle to bu built; possible values:
#                        jcef - the bundles 1) jbr with jcef+javafx, 2) jbrsdk and 3) test will be created
#                        jfx  - the bundle 1) jbr with javafx only will be created
#
# jbrsdk-${JBSDK_VERSION}-osx-x64-b${build_number}.tar.gz
# jbr-${JBSDK_VERSION}-osx-x64-b${build_number}.tar.gz
#
# $ ./java --version
# openjdk 11.0.6 2020-01-14
# OpenJDK Runtime Environment (build 11.0.6+${JDK_BUILD_NUMBER}-b${build_number})
# OpenJDK 64-Bit Server VM (build 11.0.6+${JDK_BUILD_NUMBER}-b${build_number}, mixed mode)
#
# Environment variables:
#   MODULAR_SDK_PATH - specifies the path to the directory where imported modules are located.
#               By default imported modules should be located in ./modular-sdk
#   JCEF_PATH - specifies the path to the directory where JCEF binaries are located.
#               By default imported modules should be located in ./jcef_linux_x64

JBSDK_VERSION=$1
JDK_BUILD_NUMBER=$2
build_number=$3
bundle_type=$4
JBSDK_VERSION_WITH_DOTS=$(echo $JBSDK_VERSION | sed 's/_/\./g')
WITH_IMPORT_MODULES="--with-import-modules=${MODULAR_SDK_PATH:=./modular-sdk}"
JCEF_PATH=${JCEF_PATH:=./jcef_linux_x64}

source jb/project/tools/common.sh

function create_jbr {

  case "$1" in
  "${bundle_type}_lw")
    JBR_BASE_NAME=jbr_${bundle_type}_lw-${JBSDK_VERSION}
    grep -v "jdk.compiler\|jdk.hotspot.agent" modules.list > modules_tmp.list
    ;;
  "jfx" | "jcef" | "dcevm" | "nomod")
    JBR_BASE_NAME=jbr_${bundle_type}-${JBSDK_VERSION}
    cat modules.list > modules_tmp.list
    ;;
  "jfx_jcef")
    JBR_BASE_NAME=jbr-${JBSDK_VERSION}
    cat modules.list > modules_tmp.list
    ;;
  *)
    echo "***ERR*** bundle was not specified" && exit 1
    ;;
  esac
  rm -rf ${BASE_DIR}/${JBR_BUNDLE}

  JBR=$JBR_BASE_NAME-linux-x64-b$build_number

  echo Running jlink....
  $JSDK/bin/jlink \
    --module-path $JSDK/jmods --no-man-pages --compress=2 \
    --add-modules $(xargs < modules_tmp.list | sed s/" "//g) --output $BASE_DIR/$JBR_BUNDLE

  if [[ "$bundle_type" == *jcef* ]] || [[ "$bundle_type" == *dcevm* ]]; then
    cp -R $BASE_DIR/$JBR_BUNDLE $BASE_DIR/jbr
    cp -R ${JCEF_PATH}/* $BASE_DIR/$JBR_BUNDLE/lib || exit $?
  fi
  grep -v "^JAVA_VERSION" $JSDK/release | grep -v "^MODULES" >> $BASE_DIR/$JBR_BUNDLE/release

  echo Creating $JBR.tar.gz ...
  rm -rf ${BASE_DIR}/jbr
  cp -R ${BASE_DIR}/${JBR_BUNDLE} ${BASE_DIR}/jbr
  tar -pcf $JBR.tar -C $BASE_DIR jbr || exit $?
  gzip $JBR.tar || exit $?
  rm -rf ${BASE_DIR}/${JBR_BUNDLE}
}

JBRSDK_BASE_NAME=jbrsdk-$JBSDK_VERSION
WITH_DEBUG_LEVEL="--with-debug-level=release"
RELEASE_NAME=linux-x86_64-normal-server-release
git checkout -- modules.list src/java.desktop/share/classes/module-info.java
case "$bundle_type" in
  "jfx")
    git apply -p0 < jb/project/tools/patches/exclude_jcef_module.patch
    ;;
  "jcef")
    git apply -p0 < jb/project/tools/patches/exclude_jfx_module.patch
    ;;
  "dcevm")
    git am jb/project/tools/patches/dcevm/*.patch
    ;;
  "nomod")
    git apply -p0 < jb/project/tools/patches/exclude_jcef_module.patch
    git apply -p0 < jb/project/tools/patches/exclude_jfx_module.patch
    WITH_IMPORT_MODULES=""
    ;;
esac

sh configure \
  --disable-warnings-as-errors \
  $WITH_DEBUG_LEVEL \
  --with-vendor-name="${VENDOR_NAME}" \
  --with-vendor-version-string="${VENDOR_VERSION_STRING}" \
  --with-version-pre= \
  --with-version-build=${JDK_BUILD_NUMBER} \
  --with-version-opt=b${build_number} \
  $WITH_IMPORT_MODULES \
  --enable-cds=yes || exit $?

make images CONF=$RELEASE_NAME || exit $?

JSDK=build/$RELEASE_NAME/images/jdk
JBSDK=$JBRSDK_BASE_NAME-linux-x64-b$build_number

echo Fixing permissions
chmod -R a+r $JSDK

BASE_DIR=build/$RELEASE_NAME/images
JBRSDK_BUNDLE=jbrsdk

rm -rf $BASE_DIR/$JBRSDK_BUNDLE
cp -r $JSDK $BASE_DIR/$JBRSDK_BUNDLE || exit $?

if [[ "$bundle_type" == *jcef* ]] || [[ "$bundle_type" == *dcevm* ]]; then
  cp -R ${JCEF_PATH}/* $BASE_DIR/$JBRSDK_BUNDLE/lib || exit $?
fi
if [ "$bundle_type" == "jfx_jcef" ]; then
  echo Creating $JBSDK.tar.gz ...
  sed 's/JBR/JBRSDK/g' ${BASE_DIR}/${JBRSDK_BUNDLE}/release > release
  mv release ${BASE_DIR}/${JBRSDK_BUNDLE}/release

  tar -pcf $JBSDK.tar --exclude=*.debuginfo --exclude=demo --exclude=sample --exclude=man \
    -C $BASE_DIR $JBRSDK_BUNDLE || exit $?
  gzip $JBSDK.tar || exit $?
fi

JBR_BUNDLE=jbr_${bundle_type}
create_jbr ${bundle_type}

if [ "$bundle_type" == "jfx_jcef" ]; then
  make test-image || exit $?

  JBRSDK_TEST=$JBRSDK_BASE_NAME-linux-test-x64-b$build_number

  echo Creating $JBSDK_TEST.tar.gz ...
  tar -pcf $JBRSDK_TEST.tar -C $BASE_DIR --exclude='test/jdk/demos' test || exit $?
  gzip $JBRSDK_TEST.tar || exit $?
fi