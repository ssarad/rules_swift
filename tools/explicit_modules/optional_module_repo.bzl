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

"""Lazy optional SDK aliases for one Xcode, including names absent from that Xcode."""

_AGGREGATES = ["all_modules", "implicit_modules", "all_cross_import_overlays"]

def module_catalog(names, additional_names = []):
    """Return the versioned public catalog, excluding aggregate target names."""
    return {
        "schema_version": 1,
        "modules": sorted({name: True for name in names + additional_names if name not in _AGGREGATES}),
    }

def optional_deps_bzl(names):
    """Render a BUILD helper that does not require repository-time SDK reads."""
    return """\
\"\"\"SDK candidates recognized by this hub; availability is resolved by Bazel.\"\"\"

_MODULES = %s

def optional_sdk_deps(module_names):
    \"\"\"Return optional SDK labels for recognized names, ignoring other names.

    Callers must first exclude modules supplied by their package dependencies.
    This function does not evaluate Swift conditional compilation expressions.
    \"\"\"
    return [Label(":optional/" + name) for name in sorted({name: True for name in module_names if name in _MODULES})]
""" % repr({name: True for name in names})

def optional_aliases_build(catalog, available, optional, sdk_repo):
    """Render aliases without referring to nonexistent targets in the SDK repo.

    Args:
        catalog: Candidate names exported by the hub.
        available: Module names present in this Xcode's inventory.
        optional: Names with optional aliases in this Xcode's BUILD file.
        sdk_repo: Apparent name of the sibling SDK repository, including `@`.

    Returns:
        The optional repository's BUILD file contents.
    """
    available = {name: True for name in available}
    optional = {name: True for name in optional}
    missing = sorted([name for name in catalog if name in available and name not in optional])
    if missing:
        fail("Optional SDK dependencies require a regenerated configure_xcode BUILD file for {}. Missing optional aliases: {}. Regenerate it with the current rules_swift scan tool.".format(sdk_repo, ", ".join(missing)))
    lines = [
        'load("@rules_swift//swift:swift.bzl", "system_module_group")',
        'package(default_visibility = ["//visibility:public"])',
        'system_module_group(name = "_empty", creates_module = False)',
    ]
    for name in catalog:
        actual = sdk_repo + "//:optional/" + name if name in available else ":_empty"
        lines.append("alias(name = {}, actual = {})".format(repr(name), repr(actual)))
    return "\n".join(lines) + "\n"

def _optional_module_repo_impl(rctx):
    catalog = json.decode(rctx.read(rctx.attr.catalog))
    if catalog.get("schema_version") != 1:
        fail("Unsupported SDK module catalog schema")
    available = json.decode(rctx.read(rctx.attr.module_names))
    optional = json.decode(rctx.read(rctx.attr.optional_module_names))
    rctx.file("BUILD.bazel", optional_aliases_build(catalog["modules"], available, optional, rctx.attr.sdk_repo))
    if hasattr(rctx, "repo_metadata"):
        return rctx.repo_metadata(reproducible = True)
    return None

optional_module_repo = repository_rule(
    implementation = _optional_module_repo_impl,
    attrs = {
        "catalog": attr.label(mandatory = True, allow_single_file = True),
        "module_names": attr.label(mandatory = True, allow_single_file = True),
        "optional_module_names": attr.label(mandatory = True, allow_single_file = True),
        "sdk_repo": attr.string(mandatory = True),
    },
    doc = "Resolve optional SDK names against one lazily fetched Xcode repository.",
)
