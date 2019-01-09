FROM ubuntu:16.04 AS base
MAINTAINER Sviatoslav Sydorenko <wk+freecad-cli-py3.7-docker@sydorenko.org.ua>

ENV PYTHON_VERSION 3.7.2
ENV PYTHON_MINOR_VERSION 3.7
ENV PYTHON_SUFFIX_VERSION .cpython-37m
ENV PYTHON_BIN_VERSION python3.7m
# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 18.1

ENV FREECAD_VERSION master
ENV FREECAD_REPO git://github.com/FreeCAD/FreeCAD.git

FROM base as builder
RUN \
    pack_build="git \
                wget \
                build-essential \
                cmake \
                libtool \
                libxerces-c-dev \
                libboost-dev \
                libboost-filesystem-dev \
                libboost-regex-dev \
                libboost-program-options-dev \
                libboost-signals-dev \
                libboost-thread-dev \
                libboost-python-dev \
                libqt4-dev \
                libqt4-opengl-dev \
                qt4-dev-tools \
                liboce-modeling-dev \
                liboce-visualization-dev \
                liboce-foundation-dev \
                liboce-ocaf-lite-dev \
                liboce-ocaf-dev \
                oce-draw \
                libeigen3-dev \
                libqtwebkit-dev \
                libode-dev \
                libzipios++-dev \
                libfreetype6 \
                libfreetype6-dev \
                netgen-headers \
                libmedc-dev \
                libvtk6-dev \
                libffi-dev \
                libproj-dev \
                gmsh " \
    && apt update \
    && apt install -y --no-install-recommends software-properties-common \
    && apt update \
    && apt install -y --no-install-recommends $pack_build


FROM builder AS python_builder

ENV GPG_KEY 0D96DF4D4110E5C43FBFB17F2D347EA6AA65421D

RUN set -ex \
	\
	&& wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
	&& rm -rf "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
	\
	&& cd /usr/src/python \
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& ./configure \
		--build="$gnuArch" \
		--enable-loadable-sqlite-extensions \
		--enable-shared \
		--with-system-expat \
		--with-system-ffi \
		--without-ensurepip \
	&& make -j "$(nproc)" \
	&& make install \
	&& ldconfig \
	\
	&& find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' + \
	&& rm -rf /usr/src/python \
	\
	&& python3 --version

RUN set -ex; \
    \
    wget -O get-pip.py 'https://bootstrap.pypa.io/get-pip.py'; \
    \
    python$PYTHON_MINOR_VERSION get-pip.py \
        --disable-pip-version-check \
        --no-cache-dir \
        "pip==$PYTHON_PIP_VERSION" \
    ; \
    pip --version; \
    \
    find /usr/local -depth \
        \( \
            \( -type d -a \( -name test -o -name tests \) \) \
            -o \
            \( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
        \) -exec rm -rf '{}' +; \
    rm -f get-pip.py

FROM python_builder AS clone_freecad
# get FreeCAD Git
RUN \
    cd \
    && git clone --branch "$FREECAD_VERSION" "$FREECAD_REPO"

FROM clone_freecad AS compile_fc

ENV PYTHONPATH "/usr/local/lib:$PYTHONPATH"

RUN \
    cd \
    && mkdir freecad-build \
    && cd freecad-build \
  # Build
    && cmake \
        -DBUILD_GUI=OFF \
        -DBUILD_QT5=OFF \
        -DPYTHON_EXECUTABLE=/usr/bin/$PYTHON_BIN_VERSION \
        -DPYTHON_INCLUDE_DIR=/usr/include/$PYTHON_BIN_VERSION \
        -DPYTHON_LIBRARY=/usr/lib/x86_64-linux-gnu/lib${PYTHON_BIN_VERSION}.so \
        -DPYTHON_BASENAME=$PYTHON_SUFFIX_VERSION \
        -DPYTHON_SUFFIX=$PYTHON_SUFFIX_VERSION \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_FEM_NETGEN=ON ../FreeCAD \
  \
    && make -j$(nproc) \
    && make install \
    && cd \
              \
              # Clean
                && rm FreeCAD/ freecad-build/ -fR \
                && ln -s /usr/local/bin/FreeCAD /usr/bin/freecad-git

# Clean
RUN apt-get clean \
    && rm /var/lib/apt/lists/* \
          /usr/share/doc/* \
          /usr/share/locale/* \
          /usr/share/man/* \
          /usr/share/info/* -fR    
