# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Create the user reference-able repo that points to explicit module targets."""

load(":optional_module_repo.bzl", "module_catalog", "optional_deps_bzl")

_XCODE_VERSION_FLAG = "@bazel_tools//tools/osx:xcode_version_flag_exact"

def _sanitize(v):
    return v.replace(".", "_").replace("-", "_")

def _xcode_config_settings(versions):
    """Create a config_setting per Xcode version"""
    parts = []
    for version in versions:
        name = "xcode_{}".format(_sanitize(version))
        parts.append(
            """\
config_setting(
    name = "{}",
    flag_values = {{
        "{}": "{}",
    }},
)
""".format(name, _XCODE_VERSION_FLAG, version),
        )

    return "\n".join(parts)

def _render_root_aliases(module_names, xcode_versions, optional = False):
    """Given a list of module names, write out an alias to each Xcode version repo."""
    lines = []
    for name in sorted(module_names):
        lines.append("alias(")
        lines.append('    name = "{}",'.format("optional/" + name if optional else name))
        lines.append("    actual = select({")
        for version in xcode_versions:
            lines.append('        ":xcode_{v}": "@system_sdk_{kind}xcode_{v}//:{n}",'.format(
                kind = "optional_" if optional else "",
                v = _sanitize(version),
                n = name,
            ))
        lines.append("    }),")
        lines.append(")\n")
    return "\n".join(lines)

def _xcode_explicit_module_hub_repo_impl(rctx):
    xcode_versions = rctx.attr.xcode_versions
    manifest = json.decode(rctx.read(rctx.attr.default_manifest))
    rctx.watch(rctx.attr.default_manifest)

    root_module_names = {
        "all_cross_import_overlays": True,
        "all_modules": True,
        "implicit_modules": True,
    }
    for name in manifest:
        root_module_names[name] = True

    catalog = module_catalog(manifest, rctx.attr.additional_module_names)
    rctx.file("module_catalog.json", json.encode(catalog))
    rctx.file("optional_sdk_deps.bzl", optional_deps_bzl(catalog["modules"]))
    xcode_settings_text = _xcode_config_settings(xcode_versions)
    rctx.file(
        "BUILD.bazel",
        'package(default_visibility = ["//visibility:public"])\n' +
        'exports_files(["module_catalog.json", "optional_sdk_deps.bzl"])\n' +
        xcode_settings_text + _render_root_aliases(
            root_module_names.keys(),
            xcode_versions,
        ) + _render_root_aliases(catalog["modules"], xcode_versions, optional = True),
    )
    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

xcode_explicit_module_hub_repo = repository_rule(
    implementation = _xcode_explicit_module_hub_repo_impl,
    attrs = {
        "additional_module_names": attr.string_list(),
        "default_manifest": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "Label of the default repo's module_names.json.",
        ),
        "xcode_versions": attr.string_list(
            mandatory = True,
            doc = "All canonical Xcode versions (default included).",
        ),
    },
    doc = "Export explicit module definitions referencing Xcode version specific repos.",
    environ = [
        "DEVELOPER_DIR",
        "XCODE_VERSION",
    ],
)
