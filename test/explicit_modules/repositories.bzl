"""Small SDK repositories for testing optional dependencies without Xcode scans."""

load("//tools/explicit_modules:optional_module_repo.bzl", "optional_module_repo")
load("//tools/explicit_modules:xcode_explicit_module_hub_repo.bzl", "xcode_explicit_module_hub_repo")

def _sdk_impl(ctx):
    if ctx.attr.broken:
        fail("An unselected SDK repository was fetched")
    names = ["Foundation", "UIKit", "DeviceOnly"] if ctx.attr.new else ["Foundation"]
    ctx.file("module_names.json", json.encode(names))
    ctx.file("optional_module_names.json", json.encode(names))
    lines = [
        'load("@rules_swift//swift:swift.bzl", "system_module_group")',
        'package(default_visibility = ["//visibility:public"])',
        'system_module_group(name = "_empty", creates_module = False)',
        'config_setting(name = "ios", constraint_values = ["@platforms//os:ios"])',
        'config_setting(name = "device", constraint_values = ["@platforms//os:ios", "@apple_support//constraints:device"])',
    ]
    for name in names:
        lines.append('system_module_group(name = "{}")'.format(name))
        if name == "Foundation":
            lines.append('alias(name = "optional/Foundation", actual = ":Foundation")')
        else:
            condition = "ios" if name == "UIKit" else "device"
            lines.append('alias(name = "optional/{name}", actual = select({{":{condition}": ":{name}", "//conditions:default": ":_empty"}}))'.format(name = name, condition = condition))
    ctx.file("BUILD.bazel", "\n".join(lines))

_sdk = repository_rule(
    implementation = _sdk_impl,
    attrs = {"new": attr.bool(), "broken": attr.bool()},
)

def _fixtures_impl(_ctx):
    _sdk(name = "system_sdk_xcode_1_0_0_TEST")
    _sdk(name = "system_sdk_xcode_2_0_0_TEST", new = True)
    _sdk(name = "system_sdk_xcode_3_0_0_BROKEN", broken = True)
    xcode_explicit_module_hub_repo(
        name = "optional_test_hub",
        xcode_versions = ["1.0.0.TEST", "2.0.0.TEST", "3.0.0.BROKEN"],
        default_manifest = "@system_sdk_xcode_2_0_0_TEST//:module_names.json",
        additional_module_names = ["FutureModule"],
    )
    for version in ["1_0_0_TEST", "2_0_0_TEST", "3_0_0_BROKEN"]:
        optional_module_repo(
            name = "system_sdk_optional_xcode_" + version,
            catalog = "@optional_test_hub//:module_catalog.json",
            module_names = "@system_sdk_xcode_" + version + "//:module_names.json",
            optional_module_names = "@system_sdk_xcode_" + version + "//:optional_module_names.json",
            sdk_repo = "@system_sdk_xcode_" + version,
        )

optional_sdk_test_repositories = module_extension(implementation = _fixtures_impl)
