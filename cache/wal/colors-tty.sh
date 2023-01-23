#!/bin/sh
[ "${TERM:-none}" = "linux" ] && \
    printf '%b' '\e]P0100f0f
                 \e]P15C4831
                 \e]P29A241D
                 \e]P38F3227
                 \e]P4AF3628
                 \e]P5CA2F21
                 \e]P6A5452D
                 \e]P7dd9c8a
                 \e]P89a6d60
                 \e]P95C4831
                 \e]PA9A241D
                 \e]PB8F3227
                 \e]PCAF3628
                 \e]PDCA2F21
                 \e]PEA5452D
                 \e]PFdd9c8a
                 \ec'
