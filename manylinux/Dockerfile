ARG ARCH=x86_64
FROM quay.io/pypa/manylinux_2_28_${ARCH}

RUN dnf install -y nasm cmake gcc-c++ pkgconfig git perl-IPC-Cmd && dnf clean all

ENV PATH="/opt/python/cp312-cp312/bin:$PATH"
RUN pip install setuptools wheel
