#!/usr/bin/env bash
set -euo pipefail

workspace_dir="${containerWorkspaceFolder:-$(pwd)}"

build_submodule() {
    local source_dir="$1"

    if [ ! -d "${source_dir}" ]; then
        echo "${source_dir} is not checked out; skipping build."
        return
    fi

    if [ -f "${source_dir}/Makefile" ] || [ -f "${source_dir}/makefile" ]; then
        make -C "${source_dir}" -j"$(nproc)"
    elif [ -f "${source_dir}/CMakeLists.txt" ]; then
        cmake -S "${source_dir}" -B "${source_dir}/build" -G Ninja
        cmake --build "${source_dir}/build"
    else
        echo "No CMakeLists.txt or Makefile found in ${source_dir}; skipping build."
    fi
}

install_python_submodule() {
    local source_dir="$1"
    local venv_dir="${workspace_dir}/.venv"

    if [ ! -d "${source_dir}" ]; then
        echo "${source_dir} is not checked out; skipping install."
        return
    fi

    if [ ! -f "${source_dir}/pyproject.toml" ]; then
        echo "No pyproject.toml found in ${source_dir}; skipping install."
        return
    fi

    python3 -m venv "${venv_dir}"
    "${venv_dir}/bin/python" -m pip install --upgrade pip
    "${venv_dir}/bin/python" -m pip install -e "${source_dir}[fastcrc]"
    ln -sf "${venv_dir}/bin/scat" /usr/local/bin/scat
}

build_submodule "${workspace_dir}/quectel_QCom"
build_submodule "${workspace_dir}/quectel_qlog"
install_python_submodule "${workspace_dir}/scat"

echo "Serial devices visible in the container:"
ls -l /dev/ttyUSB* 2>/dev/null || echo "No /dev/ttyUSB* devices detected right now."