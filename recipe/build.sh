set -exou

# if [[ $(arch) == "aarch64" || $(uname) == "Darwin" ]]; then
# pushd src/3rdparty
#
# # Ensure that Chromium is built using the correct sysroot in Mac
# awk 'NR==77{$0="    rebase_path(\"'$CONDA_BUILD_SYSROOT'\", root_build_dir),"}1' chromium/build/config/mac/BUILD.gn > chromium/build/config/mac/BUILD.gn.tmp
# rm chromium/build/config/mac/BUILD.gn
# mv chromium/build/config/mac/BUILD.gn.tmp chromium/build/config/mac/BUILD.gn
# popd
# fi

mkdir qtwebengine-build
pushd qtwebengine-build

USED_BUILD_PREFIX=${BUILD_PREFIX:-${PREFIX}}
echo USED_BUILD_PREFIX=${BUILD_PREFIX}

# qtwebengine needs python 2
mamba create --yes --prefix "${SRC_DIR}/python2_hack" --channel conda-forge --no-deps python=2
export PATH=${SRC_DIR}/python2_hack/bin:${PATH}

if [[ $(uname) == "Linux" ]]; then
    ln -s ${GXX} g++ || true
    ln -s ${GCC} gcc || true
    ln -s ${USED_BUILD_PREFIX}/bin/${HOST}-gcc-ar gcc-ar || true

    export LD=${GXX}
    export CC=${GCC}
    export CXX=${GXX}

    chmod +x g++ gcc gcc-ar
    export PATH=$PREFIX/bin:${PWD}:${PATH}

    which pkg-config
    export PKG_CONFIG_EXECUTABLE=$(which pkg-config)
    export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig/:$BUILD_PREFIX/lib/pkgconfig/

    # Set QMake prefix to $PREFIX
    qmake -set prefix $PREFIX

    qmake QMAKE_LIBDIR=${PREFIX}/lib \
        QMAKE_LFLAGS+="-Wl,-rpath,$PREFIX/lib -Wl,-rpath-link,$PREFIX/lib -L$PREFIX/lib" \
        INCLUDEPATH+="${PREFIX}/include" \
        PKG_CONFIG_EXECUTABLE=$(which pkg-config) \
        ..

    # Cleanup before final version
    # https://github.com/conda-forge/qt-webengine-feedstock/pull/15#issuecomment-1336593298
    pushd "${PREFIX}/lib"
    for f in *.prl; do
        sed -i "s,\$.CONDA_BUILD_SYSROOT),${CONDA_BUILD_SYSROOT},g" ${f};
    done
    popd

    pushd "${PREFIX}/mkspecs"
    for f in *.pri; do
        sed -i "s,\$.CONDA_BUILD_SYSROOT),${CONDA_BUILD_SYSROOT},g" ${f}
    done
    popd

    pushd
    cd "${PREFIX}/mkspecs/modules"
    for f in *.pri; do
        sed -i "s,\$.CONDA_BUILD_SYSROOT),${CONDA_BUILD_SYSROOT},g" ${f}
    done
    popd

    CPATH=$PREFIX/include:$BUILD_PREFIX/src/core/api make -j$CPU_COUNT
    make install
fi

if [[ $(uname) == "Darwin" ]]; then
    # Let Qt set its own flags and vars
    for x in OSX_ARCH CFLAGS CXXFLAGS LDFLAGS
    do
        unset $x
    done

    # Qt passes clang flags to LD (e.g. -stdlib=c++)
    export LD=${CXX}
    export PATH=${PWD}:${PATH}

    # Use xcode-avoidance scripts
    export PATH=$PREFIX/bin/xc-avoidance:$PATH

    export APPLICATION_EXTENSION_API_ONLY=NO

    EXTRA_FLAGS=""
    if [[ $(arch) == "arm64" ]]; then
      EXTRA_FLAGS="QMAKE_APPLE_DEVICE_ARCHS=arm64"
    fi

    if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" == "1" ]]; then
      # The python2_hack does not know about _sysconfigdata_arm64_apple_darwin20_0_0, so unset the data name
      unset _CONDA_PYTHON_SYSCONFIGDATA_NAME
    fi

    # Set QMake prefix to $PREFIX
    qmake -set prefix $PREFIX

    # sed -i '' -e 's/-Werror//' $PREFIX/mkspecs/features/qt_module_headers.prf

    qmake QMAKE_LIBDIR=${PREFIX}/lib \
        INCLUDEPATH+="${PREFIX}/include" \
        CONFIG+="warn_off" \
        QMAKE_CFLAGS_WARN_ON="-w" \
        QMAKE_CXXFLAGS_WARN_ON="-w" \
        QMAKE_CFLAGS+="-Wno-everything" \
        QMAKE_CXXFLAGS+="-Wno-everything" \
        $EXTRA_FLAGS \
        QMAKE_LFLAGS+="-Wno-everything -Wl,-rpath,$PREFIX/lib -L$PREFIX/lib" \
        PKG_CONFIG_EXECUTABLE=$(which pkg-config) \
        ..

    # find . -type f -exec sed -i '' -e 's/-Wl,-fatal_warnings//g' {} +
    # sed -i '' -e 's/-Werror//' $PREFIX/mkspecs/features/qt_module_headers.prf

    make -j$CPU_COUNT
    make install
fi

# Post build setup
# ----------------
# Remove static libraries that are not part of the Qt SDK.
pushd "${PREFIX}"/lib > /dev/null
    find . -name "*.a" -and -not -name "libQt*" -exec rm -f {} \;
popd > /dev/null
