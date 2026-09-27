<!-- SPDX-License-Identifier: Apache-2.0 -->
# Instructions

Read `README.md` first.

The coding standard is the `ai-coding-sop` repository at
`https://github.com/filmil/ai-coding-sop`.
Its `AGENTS.md`, its `prose-readability` skill, its `git-commit-rules`
skill and its `hermetic`, `bazel` and `bazel-bzl-files` fragments apply
here in full.

# Rules particular to this repository

* **Hermetic.** Every tool comes from `MODULE.bazel`, by checksum or
  built by Bazel. `.bazelrc` turns off host C++ toolchain detection, so
  a missing toolchain fails the build. Every script is a Bazel target.
* **Public packages name no dev dependency.** A user of the module loads
  `//openxc7`, where `@stardoc`, `@bazel_lib` and `@toolchains_llvm` are
  not visible. Documentation targets live in `//docs`. The integration
  module (`cd integration && bazel test //...`) is the check: it loads
  the module as a user would.
* **The C++ toolchain is the root module's.** `toolchains_llvm` allows
  only the root module to configure it, so this repository's LLVM and
  sysroot are dev dependencies. A user building the tools from source
  brings a C++ toolchain of its own.
* **Documentation is generated.** After changing a `.bzl` file, run
  `bazel run //docs:update_docs`; `bazel test //...` fails until then.
* **Rules follow rules_vivado.** A rule that has a counterpart in
  `rules_vivado` takes its name and attributes, so that a project can
  switch with a `load` line. A difference is stated in the rule's
  documentation.
* **Commits for a BCR pull request carry no `Co-Authored-By` trailer**
  (the `bazel-bcr-publish` skill says why).

`CLAUDE.md` and `GEMINI.md` are symlinks to this file.
