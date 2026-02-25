ARG ARCH=x86_64
FROM quay.io/pypa/manylinux_2_28_${ARCH}
LABEL org.opencontainers.image.source="https://github.com/commaai/dependencies"

RUN dnf install -y nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd zstd && dnf clean all

ENV PATH="/opt/python/cp312-cp312/bin:$PATH"
ENV MANYLINUX=1
RUN pip install setuptools wheel
