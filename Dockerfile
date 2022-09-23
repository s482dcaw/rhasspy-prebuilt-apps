FROM ubuntu:focal as build-ubuntu

ENV TZ=Europe/Prague
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=DontWarn
ENV EIGEN3_ROOT=/eigen-3.4.0

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        wget curl ca-certificates \
        libatlas-base-dev libatlas3-base gfortran \
        automake autoconf unzip sox libtool patch \
        python3 \
        git zlib1g-dev patchelf rsync \
        libboost-all-dev cmake zlib1g-dev libbz2-dev liblzma-dev

ARG MAKE_THREADS=4

FROM build-ubuntu as build-amd64
FROM build-ubuntu as build-armv7
FROM build-ubuntu as build-arm64

# -----------------------------------------------------------------------------
# Openfst - used by kaldi, opengrm and phonetisaurus
# https://www.openfst.org/twiki/bin/view/FST/WebHome
# Release: https://www.openfst.org/twiki/pub/FST/FstDownload/openfst-1.7.2.tar.gz
# 
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as openfst

ADD sources/openfst-1.7.2.tar.gz /
RUN cd /openfst-1.7.2 && \
    ./configure --prefix=/openfst \
                --enable-far \
                --enable-static \
                --enable-shared \
                --enable-ngram-fsts \
		--enable-lookahead-fsts \
		--with-pici && \
    make -j $MAKE_THREADS && \
    make install && \
    cp Makefile /openfst


# -----------------------------------------------------------------------------
# Kaldi
# https://kaldi-asr.org
# Release: https://github.com/kaldi-asr/kaldi/archive/refs/heads/master.zip
# As Kaldi doesn't have a version, we're using the last commit date
# Output: /kaldi-bin-20220115.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as kaldi

COPY --from=openfst /openfst/ /openfst/

ADD sources/kaldi-20220115.tar.gz /

# Modify the dependencies check
COPY sources/check_dependencies.patch /
COPY sources/online2-cli.patch /
COPY sources/online2-cli-nnet3-decode-faster-confidence.cc /kaldi-master/src/online2bin

# Install tools
RUN cd /kaldi-master/tools && \
    patch -p0 < /check_dependencies.patch && \
    extras/install_mkl.sh && \
    sed -i 's/all: check_required_programs cub openfst/all: check_required_programs cub/g' Makefile && \ 
    make -j $MAKE_THREADS; 

# Fix things for aarch64 (arm64v8)
COPY sources/linux_atlas_aarch64.mk /kaldi-master/src/makefiles/
COPY sources/set-atlas-dir.sh /
RUN bash /set-atlas-dir.sh

RUN cd /kaldi-master/src && \
    ./configure --shared --fst-root=/openfst --mathlib=ATLAS --use-cuda=no; 

COPY sources/fix-configure.sh /
RUN bash /fix-configure.sh

# Build Kaldi
RUN cd /kaldi-master/src && \
    patch -p0 < /online2-cli.patch && \
    make depend -j $MAKE_THREADS && \
    make -j $MAKE_THREADS; 

# Fix symbolic links in kaldi/src/lib
COPY sources/fix-links.sh /
RUN bash /fix-links.sh /kaldi-master/src/lib/*.so* && \
    mkdir -p /dist/kaldi/egs && \
    cp -R /kaldi-master/egs/wsj /dist/kaldi/egs/ && \
    find /kaldi-master/src/ -type f -executable -exec cp {} /dist/kaldi/ \; && \
    cp /kaldi-master/src/lib/*.so* /dist/kaldi/ && \
    rsync -av --include='*.so*' --include='fst' --exclude='*' /openfst/lib/ /dist/kaldi/ && \
    cp /openfst/bin/* /dist/kaldi/ && \
    find /dist/kaldi/ -type f -exec patchelf --set-rpath '$ORIGIN' {} \; && \
    (strip --strip-unneeded -- /dist/kaldi/* || true) && \
    tar -C /dist -czvf /kaldi-bin-20220115.tar.gz kaldi; 

# -----------------------------------------------------------------------------
# Julius
# https://github.com/julius-speech/julius
# Release: https://github.com/julius-speech/julius/archive/refs/tags/v4.6.tar.gz
# Output: /julius-bin-4.6.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as julius

ADD sources/julius-4.6.tar.gz /
RUN cd /julius-4.6 && \
    ./configure --prefix=/build/julius --enable-words-int && \
    make -j $MAKE_THREADS  && \
    make install

RUN cd /build/julius/bin && tar -czvf /julius-bin-4.6.tar.gz *

# -----------------------------------------------------------------------------
# KenLM
# https://kheafield.com/code/kenlm/
# Release: https://kheafield.com/code/kenlm.tar.gz
# Prerequisite: Eigen
# https://eigen.tuxfamily.org/index.php?title=Main_Page
# https://gitlab.com/libeigen/eigen/-/archive/3.4.0/eigen-3.4.0.tar.gz
# As kenlm doesn't have a version, we're using the download date
# Output: /kenlm-bin-20220116.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as kenlm

ADD sources/eigen-3.4.0.tar.gz /
RUN cd /eigen-3.4.0 && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make -j $MAKE_THREADS install

ADD sources/kenlm-20220116.tar.gz /

# Build kenlm
RUN cd /kenlm && \
    mkdir -p build && \
    cd build && \
    cmake .. && \
    make -j $MAKE_THREADS

RUN cd /kenlm/build/bin && \
    (strip --strip-unneeded -- * || true) && \
    tar -czvf /kenlm-bin-20220116.tar.gz *

# -----------------------------------------------------------------------------
# NanoTTS
# https://github.com/gmn/nanotts
# Release: https://github.com/gmn/nanotts/archive/refs/heads/master.zip
# As Nanotts doesn't have a version, we're using the last commit date
# Output: /nanotts-bin-20210222.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as nanotts

ADD sources/nanotts-20210222.tar.gz /
RUN cd /nanotts-master && \
    make -j $MAKE_THREADS noalsa

RUN mkdir -p /build/nanotts/bin && \
    mkdir -p /build/nanotts/share/pico && \
    cp /nanotts-master/nanotts /build/nanotts/bin/ && \
    cp -R /nanotts-master/lang /build/nanotts/share/pico/

RUN cd /build/nanotts && tar -czvf /nanotts-bin-20210222.tar.gz *

# -----------------------------------------------------------------------------
# Opengrm 
# http://www.opengrm.org/twiki/bin/view/GRM/NGramLibrary
# Release: https://www.opengrm.org/twiki/pub/GRM/NGramDownload/ngram-1.3.7.tar.gz
# Output: /ngram-bin-1.3.7.tar.gz
# 
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT

FROM build-$TARGETARCH$TARGETVARIANT as opengrm
COPY --from=openfst /openfst/ /openfst/

ADD sources/ngram-1.3.7.tar.gz /
RUN cd /ngram-1.3.7 && \
    mkdir -p build && \
    export CXXFLAGS=-I/openfst/include && \
    export LDFLAGS=-L/openfst/lib && \
    ./configure --prefix=/build/ngram && \
    make -j $MAKE_THREADS && \
    make install

COPY sources/ensure_symlinks.py /

RUN cd /build/ngram && \
    cp /openfst/bin/* bin/ && \
    cp /openfst/lib/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    python3 /ensure_symlinks.py lib/*.so* && \
    (strip --strip-unneeded -- bin/* lib/* lib/fst/* || true) && \
    tar -czf /ngram-bin-1.3.7.tar.gz -- *

# -----------------------------------------------------------------------------
# Phonetisaurus
# https://github.com/AdolfVonKleist/Phonetisaurus
# Release: https://github.com/AdolfVonKleist/Phonetisaurus/archive/refs/heads/master.zip
# As Phonetisaurus doesn't have a version, we're using the last commit date
# Output: /phonetisaurus-bin-20211003.tar.gz
# -----------------------------------------------------------------------------

ARG TARGETARCH
ARG TARGETVARIANT
FROM build-$TARGETARCH$TARGETVARIANT as phonetisaurus

COPY --from=openfst /openfst/ /openfst/
ADD sources/phonetisaurus-20211003.tar.gz /

RUN cd /Phonetisaurus-master && \
    ./configure --prefix=/build/phonetisaurus \
                --with-openfst-includes=/openfst/include \
                --with-openfst-libs=/openfst/lib && \
    make -j $MAKE_THREADS && \
    make install

COPY sources/ensure_symlinks.py /

RUN cd /build/phonetisaurus && \
    mkdir -p bin lib && \
    cp /openfst/bin/* bin/ && \
    cp /openfst/lib/*.so* lib/ && \
    rm -f lib/*.a lib/fst/*.a && \
    python3 /ensure_symlinks.py lib/*.so* && \
    (strip --strip-unneeded -- bin/* lib/* || true) && \
    tar -czf /phonetisaurus-bin-20211003.tar.gz -- *


FROM scratch
ARG TARGETARCH
ARG TARGETVARIANT

ENV TARGET=${TARGETARCH}${TARGETVARIANT}

COPY --from=nanotts /nanotts-bin-20210222.tar.gz /nanotts-bin-20210222_${TARGET}.tar.gz
COPY --from=julius /julius-bin-4.6.tar.gz /julius-bin-4.6_${TARGET}.tar.gz
COPY --from=kenlm /kenlm-bin-20220116.tar.gz /kenlm-bin-20220116_${TARGET}.tar.gz
COPY --from=kaldi /kaldi-bin-20220115.tar.gz /kaldi-bin-20220115_${TARGET}.tar.gz
COPY --from=opengrm /ngram-bin-1.3.7.tar.gz /ngram-bin-1.3.7_${TARGET}.tar.gz
COPY --from=phonetisaurus /phonetisaurus-bin-20211003.tar.gz /phonetisaurus-bin-20211003_${TARGET}.tar.gz

