#!/bin/bash
dir=${1:+${1}/}
src=${dir}main.typ
dst=${dir}main.pdf
root=${1}

if [ "${2}" = "true" ]; then
    typst watch --root "$root" ${src} ${dst} --open evince &
else
    typst compile --root "$root" ${src} ${dst}
fi