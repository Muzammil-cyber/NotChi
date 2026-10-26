#!/usr/bin/env bash
# NotChi — https://github.com/Muzammil-cyber/NotChi
# Copyright (c) 2026 Muhammad Muzammil Loya (https://muzammilloya.dev)
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Required Notice: keep this header in copies and derivatives (see LICENSE.md).
#
# Fails when a first-party Swift file is missing the copyright/SPDX header, so credit
# travels with any file that gets copied out of the repo. Generated protobuf code is exempt.
set -euo pipefail

cd "$(dirname "$0")/.."
missing=0
while IFS= read -r file; do
  if ! head -n 5 "$file" | grep -q "SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0"; then
    echo "missing license header: $file"
    missing=1
  fi
done < <(find Sources -name '*.swift' ! -name '*.pb.swift' | sort)

if [[ $missing -ne 0 ]]; then
  echo "Add the header from any existing source file (see README → Reusing NotChi code)."
  exit 1
fi
echo "All Swift sources carry the license header."
