# SPDX-License-Identifier: Apache-2.0
"""Public API of rules_openxc7.

The rules take the names and attributes of
[rules_vivado](https://github.com/filmil/bazel_rules_vivado), so that a
project can move between the two by changing its `load` line:

```python
load("@rules_openxc7//openxc7:defs.bzl", "vivado_project", "vivado_synthesis")
```

This file is filled in rule by rule. The first rule arrives with the open
toolchain that runs it.
"""

OPENXC7_PARTS = [
    "xc7a200tfbg484-2",
]
"""The parts the rules are built and tested for.

Each part needs its die's chip database and its Project X-Ray part
directory. A part not in this list is refused rather than guessed at.
"""
